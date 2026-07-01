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
  deferIfTier2Cron,
  digestIssueExistsForDate,
  postSentryHeartbeat,
  resolveOutputAwareOk,
  ensureScheduledAuditIssue,
  finalizeOutputAwareHeartbeat,
  DeployInProgressError,
  DEFAULT_CRON_TOKEN_PERMISSIONS,
  REPO_NAME,
  type HandlerArgs,
} from "./_cron-shared";
import {
  setupEphemeralWorkspace,
  teardownEphemeralWorkspace,
  spawnClaudeEval,
  makeThrewSpawnResult,
  type SpawnResult,
} from "./_cron-claude-eval-substrate";
import { safeCommitAndPr } from "./_cron-safe-commit";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import { EXECUTION_MODEL } from "@/server/inngest/model-tiers";

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
//
// #4993 — headless /soleur:* skill resolution (fleet fix mirroring #4987 /
// PR #4989): `--plugin-dir plugins/soleur` registers the plugin (clone's tracked tree — #5091) under
// `--print` (a bare plugins/ dir is NOT auto-discovered in headless mode), and
// `Skill` (+`Task` for subagent fan-out) in --allowedTools gates skill invocation.
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  EXECUTION_MODEL,
  "--max-turns",
  "40",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep,Skill,Task",
  "--plugin-dir",
  "plugins/soleur",
  "--",
];

// Verbatim prompt extracted from
// .github/workflows/scheduled-campaign-calendar.yml. #5111 removed the
// prompt-level commit block (the platform persists handler-side via
// safeCommitAndPr — the #5091 consolidation pattern).
const CAMPAIGN_CALENDAR_PROMPT = `IMPORTANT: This is an automated CI workflow. Do NOT push directly to main.

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

PERSISTENCE: Do NOT run git add, git commit, git push, or gh pr create/merge.
The platform commits and opens a PR for your changes automatically after the run.
Only changes under knowledge-base/marketing/campaign-calendar.md and knowledge-base/marketing/content-strategy.md are persisted — keep all edits inside those paths.
Creating the calendar issues above (STEP 2 or the STEP 2.5 heartbeat) is REQUIRED: the platform only persists your changes after it verifies the issue exists.
`;

// Persistence allowlist (#5111): verbatim from the prompt's former scoped
// staging list (the two files the calendar refresh and review-date bump edit).
const CAMPAIGN_CALENDAR_ALLOWED_PATHS = [
  "knowledge-base/marketing/campaign-calendar.md",
  "knowledge-base/marketing/content-strategy.md",
] as const;

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
  attempt,
  maxAttempts,
  runId,
}: HandlerArgs): Promise<{ ok: boolean }> {
  // D6 (#5018) / #5046 PR-2: still Tier-2-deferred — the firewall landed but
  // this cron needs per-construct Bash-allowlist refinement or non-GitHub
  // egress coverage before restore (see TIER2_DEFERRED_CRONS). Posts an
  // honest on-schedule check-in and skips the claude spawn (no fail-closed
  // FAILED-issue/RED-monitor storm); the scheduled output issue visibly stops.
  if (
    await deferIfTier2Cron({
      cronName: "cron-campaign-calendar",
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      step,
      logger,
    })
  ) {
    return { ok: true };
  }

  // Run-window start — the lower bound for the post-run output check. Captured
  // before the mint step (memoized across Inngest replays) so a replay reuses
  // the original window rather than re-stamping a later "now".
  const runStartedAt = await step.run(
    "run-started-at",
    async () => new Date().toISOString(),
  );

  // #5786 — producer-side date-dedup (extends the #5751 community-monitor fix).
  // Campaign-calendar's producer digest carries a trailing ` (heartbeat)` suffix
  // (STEP 2.5, minted only when NEW == 0), so the matcher anchors on
  // `[Scheduled] Campaign Calendar - <date> (heartbeat)`.
  //
  // PARTIAL-DEDUP ASYMMETRY (intentional, fail-OPEN): unlike the 6 always-create
  // crons, campaign-calendar mints the `(heartbeat)` digest ONLY on quiet
  // (NEW == 0) days. On an overdue day (NEW > 0) invocation #1 files
  // `[Content] Overdue: …` issues and NO `(heartbeat)` digest, so this check
  // finds nothing → invocation #2 re-spawns. That is SAFE (the in-prompt STEP 2(b)
  // per-item dedup bounds the duplicate-issue damage) but means the producer-side
  // dedup only fires on NEW == 0 days — a structurally weaker guarantee than the
  // cohort. Do NOT assume an exactly-one digest invariant here.
  //
  // The skip path MUST post a healthy OK heartbeat inline and return BEFORE
  // reaching verify-output/finalizeOutputAwareHeartbeat, whose run-window
  // (updated_at >= THIS runStartedAt) would exclude the earlier issue and
  // false-RED the skip. concurrency:{scope:"fn",limit:1} serializes the two
  // invocations so the second's FRESH LIST read sees the first's create. Date
  // anchor is runStartedAt.slice(0,10) (replay-stable). Fail-OPEN: a read error
  // → spawn (a duplicate paper-cut beats a missed digest).
  const digestAlreadyExists = await step.run("dedup-digest-check", async () =>
    digestIssueExistsForDate({
      label: SENTRY_MONITOR_SLUG,
      titlePrefix: "[Scheduled] Campaign Calendar -",
      titleSuffix: " (heartbeat)",
      date: runStartedAt.slice(0, 10),
      cronName: "cron-campaign-calendar",
    }),
  );
  if (digestAlreadyExists) {
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({
        ok: true,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-campaign-calendar",
        logger,
      });
    });
    return { ok: true };
  }

  // --- Step 1: mint installation token (memoized across replays) ---
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
        permissions: DEFAULT_CRON_TOKEN_PERMISSIONS,
        repositories: [REPO_NAME],
      });
    },
  );

  // --- Step 2: setup ephemeral workspace (clone + settings + sentinel) ---
  let ephemeralRoot: string | null = null;
  let spawnCwd: string | null = null;
  try {
    const workspace = await step.run("setup-workspace", async () => {
      return setupEphemeralWorkspace({ installationToken, cronName: "cron-campaign-calendar" });
    });
    ephemeralRoot = workspace.ephemeralRoot;
    spawnCwd = workspace.spawnCwd;
  } catch (err) {
    // #5728 G1 — benign deploy-in-progress defer (ADR-076): rethrow bare, no heartbeat.
    if (err instanceof DeployInProgressError) throw err;
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
    // #5728 — flag pattern. The body (claude-eval → verify-output →
    // safe-commit-pr) runs in an inner try whose throw sets `threw`; the single
    // terminal heartbeat is posted (or skipped-for-retry) by
    // finalizeOutputAwareHeartbeat below — NOT from a second catch-site (which,
    // under retries:1 memoization, would replay a stale `ok` while posting a
    // conflicting `error`). A throw before the heartbeat previously propagated
    // out → the heartbeat step never ran → silent `missed` (the 06-13→06-21
    // class). spawnResult is hoisted so the silence-hole audit issue can read it
    // even when a later step threw.
    let heartbeatOk = false;
    let threw = false;
    let spawnResult: SpawnResult | null = null;
    try {
      // --- Step 3: claude-eval (30-min AbortController) ---
      spawnResult = await step.run(
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
            runId,
            attempt,
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
      heartbeatOk = await step.run("verify-output", async () =>
        resolveOutputAwareOk({
          spawnOk: spawnResult!.ok,
          label: SENTRY_MONITOR_SLUG,
          runStartedAt,
          cronName: "cron-campaign-calendar",
          stderrTail: spawnResult!.stderrTail,
          exitCode: spawnResult!.exitCode,
          stdoutTail: spawnResult!.stdoutTail,
        }),
      );
      // --- Step 4.5: deterministic persistence (#5111, pattern from #5091 /
      //     cron-seo-aeo-audit.ts). Gated on the issue-verified output rather
      //     than the spawn exit code: exit-0-with-no-issue is unverified
      //     (possibly mid-edit) work that must not auto-merge, while
      //     issue-created + non-zero exit is the documented healthy #4747 case
      //     whose diff must not be discarded. (Caveat: resolveOutputAwareOk
      //     falls back to the spawn exit code when its GitHub verify-read
      //     THROWS — a tri-state gate is tracked in #5139.) abortedByTimeout also skips —
      //     a hard kill can land mid-edit, and the timeout is already loud via
      //     the reportSilentFallback above. Guard aborts / persistence failures
      //     self-report inside the helper (Sentry + issue comment).
      if (heartbeatOk && !spawnResult.abortedByTimeout) {
        await step.run("safe-commit-pr", async () =>
          safeCommitAndPr({
            spawnCwd: spawnCwd!,
            installationToken,
            cronName: "cron-campaign-calendar",
            commitMessage: "ci: update campaign calendar and content-strategy review",
            allowedPaths: CAMPAIGN_CALENDAR_ALLOWED_PATHS,
            runStartedAt,
            scheduledIssueLabel: SENTRY_MONITOR_SLUG,
            logger,
          }),
        );
      }
    } catch (err) {
      if (err instanceof DeployInProgressError) throw err;
      threw = true;
      const e = err as Error;
      const redactedMsg = redactToken(e.message ?? "", installationToken);
      const redacted = new Error(redactedMsg);
      redacted.name = e.name;
      reportSilentFallback(redacted, {
        feature: "cron-campaign-calendar",
        op: "handler-body-threw",
        message: "cron-campaign-calendar body threw before the terminal heartbeat",
        extra: { fn: "cron-campaign-calendar", attempt: attempt ?? 0, producedOutput: heartbeatOk },
      });
    }

    // --- Single authoritative terminal heartbeat (memoization-safe,
    //     final-attempt gated). On a genuine non-final failure the helper skips
    //     the whole heartbeat step and returns retry:true (we rethrow to trigger
    //     the Inngest retry, filing NO premature FAILED issue). On the post path,
    //     the Step-5 silence-hole fallback (#4960/#4978) files a FAILED audit
    //     issue when red, ordered BEFORE the heartbeat so the heartbeat stays the
    //     genuine last step. ---
    const { retry } = await finalizeOutputAwareHeartbeat({
      step,
      heartbeatOk,
      threw,
      attempt,
      maxAttempts,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-campaign-calendar",
      logger,
      onBeforeHeartbeat: heartbeatOk
        ? undefined
        : async () => {
            await step.run("ensure-audit-issue", async () => {
              try {
                await ensureScheduledAuditIssue({
                  label: SENTRY_MONITOR_SLUG,
                  titlePrefix: "[Scheduled] Campaign Calendar -",
                  cronName: "cron-campaign-calendar",
                  runStartedAt,
                  spawnResult: spawnResult ?? makeThrewSpawnResult("cron-campaign-calendar"),
                  installationToken,
                });
              } catch (err) {
                reportSilentFallback(err, {
                  feature: "cron-campaign-calendar",
                  op: "ensure-audit-issue-failed",
                  message:
                    "Handler-level fallback audit-issue create failed; run remains silent until watchdog threshold",
                  extra: { fn: "cron-campaign-calendar", runStartedAt },
                });
              }
            });
          },
    });
    if (retry) {
      throw new Error(
        "cron-campaign-calendar failed on a non-final attempt; retrying",
      );
    }

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
