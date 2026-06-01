// TR9 Phase 2 — Migrated from the GHA scheduled-growth-audit workflow
// (deleted in the same PR per TR9 I-13 hygiene). claude-code-spawn pattern;
// structural template is cron-roadmap-review.ts.
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — claude binary spawned INSIDE step.run (Inngest replay memoization).
//   I2 — Operator ANTHROPIC_API_KEY only; never founder BYOK. Enforced at
//        build time by test/server/cron-no-byok-lease-sweep.test.ts.
//   I3 — AbortSignal aborts at MAX_TURN_DURATION_MS (70 min). Manual
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

const SENTRY_MONITOR_SLUG = "scheduled-growth-audit";

// Token-lifetime floor passed to generateInstallationToken: claude-eval's
// 70-min wall-clock budget + 10-min slack for setup + teardown + retry.
const TOKEN_MIN_LIFETIME_MS = 70 * 60 * 1000 + 10 * 60 * 1000;

// 70 min wall-clock budget (from 75 min GHA timeout minus headroom).
// Exported for test parity.
export const MAX_TURN_DURATION_MS = 70 * 60 * 1000;
export { KILL_ESCALATION_MS } from "./_cron-claude-eval-substrate";

// claude-code spawn argv. `--` is load-bearing per #4017 bug 8/8 (variadic
// --allowedTools consumes the prompt as a tool name without the end-of-
// options marker). The prompt is the SOLE positional argument after `--`.
//
// NOTE: claude-opus-4-7 model for deep multi-step growth audit.
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  "claude-opus-4-7",
  "--max-turns",
  "70",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch",
  "--",
];

// Verbatim prompt extracted from
// .github/workflows/scheduled-growth-audit.yml.
const GROWTH_AUDIT_PROMPT = `IMPORTANT: This is an automated CI workflow. Do NOT push directly to main. Use the PR-based commit pattern in the MANDATORY FINAL STEP.

MILESTONE RULE: Every gh issue create command must include --milestone. Use --milestone "Post-MVP / Later" for operational issues. For feature issues, read knowledge-base/product/roadmap.md.

Today's date is $(date +%Y-%m-%d). Run a full growth audit of https://soleur.ai.

Step 1: Content Audit
Run /soleur:growth auditing on this repository. Save the report to knowledge-base/marketing/audits/soleur-ai/<today>-content-audit.md

Step 2: AEO Audit
Run /soleur:growth auditing --aeo on this repository. Save the report to knowledge-base/marketing/audits/soleur-ai/<today>-aeo-audit.md

Step 3: Technical SEO Audit
Run /soleur:seo-aeo on this repository. Save the report to knowledge-base/marketing/audits/soleur-ai/<today>-seo-audit.md. If the audit fails, write a stub report and continue.

Step 4: Content Plan
Based on the three audit reports, create a prioritized content plan. Save to knowledge-base/marketing/audits/soleur-ai/<today>-content-plan.md

Step 5: GitHub Issue
Create issue "[Scheduled] Growth Audit - <today>" with label "scheduled-growth-audit" summarizing top findings, AEO score/grade, SEO score/grade, and content plan priorities.

Step 5.5: Create tracking issues for each P0/P1/P2 finding (with dedup).

Step 5.6: Assign milestones and update roadmap.

MANDATORY FINAL STEP — persist via PR:
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add knowledge-base/marketing/audits/soleur-ai/ knowledge-base/product/roadmap.md
git diff --cached --quiet && echo "No changes to commit" && exit 0
BRANCH="ci/growth-audit-$(date -u +%Y-%m-%d-%H%M%S)"
git checkout -b "$BRANCH"
git commit -m "docs: weekly growth audit $(date -u +%Y-%m-%d)"
git push -u origin "$BRANCH"
gh pr create --title "docs: weekly growth audit $(date -u +%Y-%m-%d)" --body "Automated weekly growth audit commit." --base main --head "$BRANCH"
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

export async function cronGrowthAuditHandler({
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
      return setupEphemeralWorkspace({ installationToken, cronName: "cron-growth-audit" });
    });
    ephemeralRoot = workspace.ephemeralRoot;
    spawnCwd = workspace.spawnCwd;
  } catch (err) {
    const e = err as Error;
    const redactedMsg = redactToken(e.message ?? "", installationToken);
    const redacted = new Error(redactedMsg);
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: "cron-growth-audit",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-growth-audit" },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-growth-audit", logger });
    });
    return { ok: false };
  }

  try {
    // --- Step 3: claude-eval (70-min AbortController) ---
    const spawnResult = await step.run(
      "claude-eval",
      async (): Promise<SpawnResult> => {
        return spawnClaudeEval({
          spawnCwd: spawnCwd!,
          installationToken,
          flags: CLAUDE_CODE_FLAGS,
          prompt: GROWTH_AUDIT_PROMPT,
          maxTurnDurationMs: MAX_TURN_DURATION_MS,
          cronName: "cron-growth-audit",
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
          feature: "cron-growth-audit",
          op: "claude-eval-timeout",
          message: "claude-eval aborted by AbortController",
          extra: {
            fn: "cron-growth-audit",
            durationMs: spawnResult.durationMs,
            maxMs: MAX_TURN_DURATION_MS,
          },
        },
      );
    }

    // --- Step 4: output-aware heartbeat. This cron is an always-create
    //     producer — it files a `[Scheduled] Growth Audit - <today>` summary
    //     issue every run — so a clean exit that produced no
    //     `scheduled-growth-audit` issue in the run window turns the monitor RED
    //     (and emits `scheduled-output-missing`) instead of false-green on
    //     claude's exit code. Mirrors the 3 producers wired by PR #4714 (#4730).
    //     Infra faults still page via the early-return status=error heartbeats. ---
    const heartbeatOk = await step.run("verify-output", async () =>
      resolveOutputAwareOk({
        spawnOk: spawnResult.ok,
        label: SENTRY_MONITOR_SLUG,
        runStartedAt,
        cronName: "cron-growth-audit",
      }),
    );
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: heartbeatOk, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-growth-audit", logger });
    });

    return { ok: heartbeatOk };
  } finally {
    await teardownEphemeralWorkspace(ephemeralRoot, "cron-growth-audit").catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-growth-audit",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-growth-audit", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: scheduled cron (0 7 * * 1 UTC — weekly Monday 07:00, staggered
// from 09:00 per plan) + manual operator event
// `cron/growth-audit.manual-trigger`. account-scope concurrency
// "cron-platform" limits to 1 simultaneous cron-* invocation.

export const cronGrowthAudit = inngest.createFunction(
  {
    id: "cron-growth-audit",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 7 * * 1" },
    { event: "cron/growth-audit.manual-trigger" },
  ],
  cronGrowthAuditHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
