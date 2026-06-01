// TR9 Phase 2 — Migrated from the GHA scheduled-campaign-calendar workflow
// (deleted in the same PR per TR9 I-13 hygiene). claude-code-spawn pattern;
// structural template is cron-roadmap-review.ts.
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — claude binary spawned INSIDE step.run (Inngest replay memoization).
//   I2 — Operator ANTHROPIC_API_KEY only; never founder BYOK. Enforced at
//        build time by test/server/cron-no-byok-lease-sweep.test.ts.
//   I3 — AbortSignal aborts at MAX_TURN_DURATION_MS (30 min). Manual
//        SIGTERM→SIGKILL escalation via process-group kill (detached:true).
//   I4 — claude binary resolved at spawn time via filesystem checks; the
//        CLAUDE_BIN env var is the override hatch for fresh-host bootstraps.
//   I5 — Deterministic step.run return shape: {ok, exitCode, signal,
//        abortedByTimeout, durationMs}. stdout is NOT captured.
//   I6 — Event payloads emitted by cron-*.ts MUST carry actor: "platform".
//        (This handler emits none.)

import {
  redactToken,
  mintInstallationToken,
  postSentryHeartbeat,
  resolveOutputAwareOk,
  type HandlerArgs,
} from "./_cron-shared";
import {
  setupEphemeralWorkspace,
  teardownEphemeralWorkspace,
  spawnClaudeEval,
  type SpawnResult,
} from "./_cron-claude-eval-substrate";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-campaign-calendar";

// Token-lifetime floor passed to generateInstallationToken: claude-eval's
// 30-min wall-clock budget + 10-min slack for setup + teardown + retry.
const TOKEN_MIN_LIFETIME_MS = 30 * 60 * 1000 + 10 * 60 * 1000;

// 30 min wall-clock budget. Math: 30min / 40turns = 0.75 min/turn.
// Exported for test parity.
export const MAX_TURN_DURATION_MS = 30 * 60 * 1000;
export { KILL_ESCALATION_MS } from "./_cron-claude-eval-substrate";

// claude-code spawn argv. `--` is load-bearing per #4017 bug 8/8 (variadic
// --allowedTools consumes the prompt as a tool name without the end-of-
// options marker). The prompt is the SOLE positional argument after `--`.
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  "claude-sonnet-4-6",
  "--max-turns",
  "40",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep",
  "--",
];

// Verbatim prompt extracted from
// .github/workflows/scheduled-campaign-calendar.yml.
const CAMPAIGN_CALENDAR_PROMPT = `IMPORTANT: This is an automated CI workflow. Do NOT push directly to main. Use the PR-based commit pattern in the MANDATORY FINAL STEP.

STEP 1 — Refresh campaign calendar:
Run /soleur:campaign-calendar on this repository.

STEP 2 — Flag overdue distribution content (with dedup):
Scan all files in knowledge-base/marketing/distribution-content/ for items where:
- status is "scheduled" AND publish_date is in the past (before today)
- status is "draft" AND publish_date is non-empty and in the past

For each overdue item, before creating an issue:
(a) Search for an existing OPEN issue with title "[Content] Overdue: <title> (was scheduled for <date>)" and label scheduled-campaign-calendar
(b) If found, comment with a heartbeat note. Do NOT create a new issue.
(c) If not found, create a new issue with labels "action-required,scheduled-campaign-calendar" and --milestone "Post-MVP / Later"

Track counters: NEW (issues created), DEDUP (existing issues commented), OVERDUE (total scanned).

STEP 2.5 — Heartbeat audit issue (runs when NEW == 0):
If no new issues were created, create and immediately close a heartbeat audit issue so the watchdog sees recent activity:
  Title: "[Scheduled] Campaign Calendar - <today> (heartbeat)"
  Label: scheduled-campaign-calendar
  Milestone: "Post-MVP / Later"

STEP 3 — Update content-strategy review date:
In knowledge-base/marketing/content-strategy.md, update the frontmatter last_reviewed field to today's date.

MANDATORY FINAL STEP — persist via PR:
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add knowledge-base/marketing/campaign-calendar.md knowledge-base/marketing/content-strategy.md
git diff --cached --quiet && echo "No changes to commit" && exit 0
BRANCH="ci/campaign-calendar-$(date -u +%Y-%m-%d-%H%M%S)"
git checkout -b "$BRANCH"
git commit -m "ci: update campaign calendar and content-strategy review"
git push -u origin "$BRANCH"
gh pr create --title "ci: update campaign calendar $(date -u +%Y-%m-%d)" --body "Automated commit from campaign calendar workflow." --base main --head "$BRANCH"
gh pr merge "$BRANCH" --squash --auto
`;

// Spawn-env allowlist (NOT a denylist). The keys below are the COMPLETE set
// the spawned claude is allowed to see; anything not listed (notably
// RESEND_API_KEY, SENTRY_*, DOPPLER_*, GITHUB_APP_PRIVATE_KEY) is excluded.
function buildSpawnEnv(installationToken: string): NodeJS.ProcessEnv {
  return {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    NODE_ENV: process.env.NODE_ENV,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
    GH_TOKEN: installationToken,
  };
}

// =============================================================================
// Handler
// =============================================================================

export async function cronCampaignCalendarHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean }> {
  // Run-window start — the lower bound for the post-run output check. Captured
  // before the mint step (memoized across Inngest replays) so a replay reuses
  // the original window rather than re-stamping a later "now".
  const runStartedAt = await step.run(
    "run-started-at",
    async () => new Date().toISOString(),
  );

  // --- Step 1: mint installation token (memoized across replays) ---
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS });
    },
  );

  // --- Step 2: setup ephemeral workspace (clone + symlink + sentinel) ---
  let ephemeralRoot: string | null = null;
  let spawnCwd: string | null = null;
  try {
    const workspace = await step.run("setup-workspace", async () => {
      return setupEphemeralWorkspace({ installationToken, cronName: "cron-campaign-calendar" });
    });
    ephemeralRoot = workspace.ephemeralRoot;
    spawnCwd = workspace.spawnCwd;
  } catch (err) {
    const e = err as Error;
    const redactedMsg = redactToken(e.message ?? "", installationToken);
    const redacted = new Error(redactedMsg);
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: "cron-campaign-calendar",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-campaign-calendar" },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-campaign-calendar", logger });
    });
    return { ok: false };
  }

  try {
    // --- Step 3: claude-eval (30-min AbortController) ---
    const spawnResult = await step.run(
      "claude-eval",
      async (): Promise<SpawnResult> => {
        return spawnClaudeEval({
          spawnCwd: spawnCwd!,
          installationToken,
          flags: CLAUDE_CODE_FLAGS,
          prompt: CAMPAIGN_CALENDAR_PROMPT,
          maxTurnDurationMs: MAX_TURN_DURATION_MS,
          cronName: "cron-campaign-calendar",
          buildSpawnEnv,
          logger,
        });
      },
    );

    if (spawnResult.abortedByTimeout) {
      reportSilentFallback(
        new Error(
          `claude-eval aborted by timeout (${MAX_TURN_DURATION_MS}ms budget exceeded)`,
        ),
        {
          feature: "cron-campaign-calendar",
          op: "claude-eval-timeout",
          message: "claude-eval aborted by AbortController",
          extra: {
            fn: "cron-campaign-calendar",
            durationMs: spawnResult.durationMs,
            maxMs: MAX_TURN_DURATION_MS,
          },
        },
      );
    }

    // --- Step 4: output-aware heartbeat. This cron is an always-create
    //     producer, NOT best-effort: STEP 2(c) files a per-overdue
    //     `scheduled-campaign-calendar` issue, and STEP 2.5 files (then
    //     immediately closes) a heartbeat audit issue with the SAME label when
    //     NEW == 0 — so a `scheduled-campaign-calendar` artifact lands in the
    //     run window on EVERY run (create, or comment-bump via STEP 2(b), both
    //     of which `verifyScheduledIssueCreated` counts via updated_at). A clean
    //     exit that produced none turns the monitor RED (and emits
    //     `scheduled-output-missing`) instead of false-green on claude's exit
    //     code. Mirrors the producers wired by PR #4714 (#4730). Infra faults
    //     still page via the early-return status=error heartbeats. ---
    const heartbeatOk = await step.run("verify-output", async () =>
      resolveOutputAwareOk({
        spawnOk: spawnResult.ok,
        label: SENTRY_MONITOR_SLUG,
        runStartedAt,
        cronName: "cron-campaign-calendar",
      }),
    );
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: heartbeatOk, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-campaign-calendar", logger });
    });

    return { ok: heartbeatOk };
  } finally {
    await teardownEphemeralWorkspace(ephemeralRoot, "cron-campaign-calendar").catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-campaign-calendar",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-campaign-calendar", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: scheduled cron (0 16 * * 1 UTC — weekly Monday 16:00) + manual
// operator event `cron/campaign-calendar.manual-trigger`. account-scope
// concurrency "cron-platform" limits to 1 simultaneous cron-* invocation.

export const cronCampaignCalendar = inngest.createFunction(
  {
    id: "cron-campaign-calendar",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 16 * * 1" },
    { event: "cron/campaign-calendar.manual-trigger" },
  ],
  cronCampaignCalendarHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
