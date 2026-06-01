// TR9 Phase-2 — Migrated from the GHA scheduled-growth-execution
// workflow (deleted in the same PR per TR9 I-13 hygiene). Ported via the
// claude-code-spawn pattern; structural template is cron-roadmap-review.ts.
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
//
// NAME NOTE: Sentry monitor slug "scheduled-growth-execution" is NEW — the
// GHA predecessor had NO Sentry check-in (it ran on GHA's runner pool).
//
// SHAPE DIFF vs cron-roadmap-review.ts:
//   - --model claude-sonnet-4-6 (same).
//   - --max-turns 40 (same).
//   - --allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch (adds
//     WebSearch for SEO keyword research; no WebFetch needed).
//   - MAX_TURN_DURATION_MS 30 min (lower than 50 min cohort — biweekly
//     growth execution is a lighter workload).
//   - Cron: biweekly 1st and 15th @ 10:00 UTC.
//   - Side-effect class: issue-creator + pr-creator (MANDATORY FINAL STEP
//     block creates branch → commit → gh pr create → gh pr merge --squash
//     --auto).
//
// PLUGIN-LOADING — Verbatim ephemeral-workspace pattern:
//   - repo/                          (in-handler `git clone --depth=1`)
//   - repo/plugins/soleur            (symlink to getPluginPath())
//   - repo/.claude/settings.json     (DEFAULT_SETTINGS overlay)
// Plugin resolution is cwd-relative — the soleur plugin manifest at
// plugins/soleur/.claude-plugin/plugin.json is discovered from spawn cwd.
//
// GH TOKEN — installation token minted via createProbeOctokit() →
// installation discovery → generateInstallationToken(installation.id).
// Injected as GH_TOKEN so the spawned claude can run `gh api ...`,
// `gh issue create`, `gh pr create`, `gh pr merge`, `git push`.

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

const SENTRY_MONITOR_SLUG = "scheduled-growth-execution";

// Token-lifetime floor passed to generateInstallationToken: claude-eval's
// 30-min wall-clock budget + 10-min slack for setup + teardown + retry.
const TOKEN_MIN_LIFETIME_MS = 30 * 60 * 1000 + 10 * 60 * 1000;

// 30 min wall-clock budget. Math: 30min / 40turns = 0.75 min/turn,
// at the floor. Exported for test parity (cron-growth-execution.test.ts
// imports to avoid hard-coded timing drift across SUT tuning).
export const MAX_TURN_DURATION_MS = 30 * 60 * 1000;
export { KILL_ESCALATION_MS } from "./_cron-claude-eval-substrate";

// claude-code spawn argv. `--` is load-bearing per #4017 bug 8/8 (variadic
// --allowedTools consumes the prompt as a tool name without the end-of-
// options marker). The prompt is the SOLE positional argument after `--`.
//
// Mirrors .github/workflows/scheduled-growth-execution.yml `claude_args`:
//   --model claude-sonnet-4-6
//   --max-turns 40
//   --allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  "claude-sonnet-4-6",
  "--max-turns",
  "40",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep,WebSearch",
  "--",
];

// Verbatim prompt extracted from
// .github/workflows/scheduled-growth-execution.yml (the `prompt: |` block
// body, YAML indentation stripped).
// Verbatim-extraction discipline: anchor strings ("seo-refresh-queue",
// "Priority 1", "growth fix", "validate-seo", "MANDATORY FINAL STEP")
// asserted by the test suite to catch silent paraphrasing across
// plan→work cycles.
const GROWTH_EXECUTION_PROMPT = `IMPORTANT: This is an automated CI workflow. Do NOT push directly to main. Use the PR-based commit pattern in the MANDATORY FINAL STEP.

MILESTONE RULE: Every gh issue create command must include --milestone "Post-MVP / Later".

Read knowledge-base/marketing/seo-refresh-queue.md and identify Priority 1 ("Update immediately") stale pages that need keyword optimization.

For each stale page found, run /soleur:growth fix <page-path> to apply keyword injection, meta description rewrites, and FAQ section additions.

After fixing all stale pages, validate the changes:
npx @11ty/eleventy
bash plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh _site

Then create a GitHub issue titled "[Scheduled] Growth Execution - <today>" with the label "scheduled-growth-execution" summarizing which pages were optimized, what changes were made, and build validation results.

If no stale pages are found, create the issue noting "No stale pages found — all Priority 1 items are up to date."

MANDATORY FINAL STEP — persist via PR:
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add -A
git diff --cached --quiet && echo "No changes to commit" && exit 0
BRANCH="ci/growth-execution-$(date -u +%Y-%m-%d-%H%M%S)"
git checkout -b "$BRANCH"
git commit -m "fix(growth): biweekly keyword optimization"
git push -u origin "$BRANCH"
gh pr create --title "fix(growth): biweekly keyword optimization $(date -u +%Y-%m-%d)" --body "Automated commit from growth execution workflow." --base main --head "$BRANCH"
gh pr merge "$BRANCH" --squash --auto
`;

// Spawn-env allowlist (NOT a denylist). The keys below are the COMPLETE
// set the spawned claude is allowed to see; anything not listed (notably
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

export async function cronGrowthExecutionHandler({
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
  // The raw token string is the return value (NEVER log this value).
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS });
    },
  );

  // --- Step 2: setup ephemeral workspace (clone + symlink + sentinel) ---
  // Track ephemeralRoot in handler-scope so teardown runs regardless of
  // downstream success/failure.
  let ephemeralRoot: string | null = null;
  let spawnCwd: string | null = null;
  try {
    const workspace = await step.run("setup-workspace", async () => {
      return setupEphemeralWorkspace({ installationToken, cronName: "cron-growth-execution" });
    });
    ephemeralRoot = workspace.ephemeralRoot;
    spawnCwd = workspace.spawnCwd;
  } catch (err) {
    // Redact token if it sneaks into the error message (defense-in-depth).
    const e = err as Error;
    const redactedMsg = redactToken(e.message ?? "", installationToken);
    const redacted = new Error(redactedMsg);
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: "cron-growth-execution",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-growth-execution" },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-growth-execution", logger });
    });
    return { ok: false };
  }

  // Wrap the entire post-setup pipeline in try/finally so the ephemeral
  // workspace is torn down even if claude-eval throws at the Inngest step
  // boundary. The teardown side-effect outside step.run is acceptable
  // because rm {recursive:true, force:true} is idempotent — a replay
  // re-creates a fresh ephemeralRoot from setup-workspace's memoization
  // (or the existsSync guard at the top of spawnClaudeEval rebuilds it).
  try {
    // --- Step 3: claude-eval (30-min AbortController) ---
    const spawnResult = await step.run(
      "claude-eval",
      async (): Promise<SpawnResult> => {
        return spawnClaudeEval({
          spawnCwd: spawnCwd!,
          installationToken,
          flags: CLAUDE_CODE_FLAGS,
          prompt: GROWTH_EXECUTION_PROMPT,
          maxTurnDurationMs: MAX_TURN_DURATION_MS,
          cronName: "cron-growth-execution",
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
          feature: "cron-growth-execution",
          op: "claude-eval-timeout",
          message: "claude-eval aborted by AbortController",
          extra: {
            fn: "cron-growth-execution",
            durationMs: spawnResult.durationMs,
            maxMs: MAX_TURN_DURATION_MS,
          },
        },
      );
    }

    // --- Step 4: output-aware heartbeat. This cron is an always-create
    //     producer — it files a `[Scheduled] Growth Execution` issue every run
    //     (explicitly "No stale pages found" when there is nothing to do) — so a
    //     clean exit that produced no `scheduled-growth-execution` issue in the
    //     run window turns the monitor RED (and emits `scheduled-output-missing`)
    //     instead of false-green on claude's exit code. Mirrors the 3 producers
    //     wired by PR #4714 (#4730). Infra faults still page via the early-returns. ---
    const heartbeatOk = await step.run("verify-output", async () =>
      resolveOutputAwareOk({
        spawnOk: spawnResult.ok,
        label: SENTRY_MONITOR_SLUG,
        runStartedAt,
        cronName: "cron-growth-execution",
      }),
    );
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: heartbeatOk, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-growth-execution", logger });
    });

    return { ok: heartbeatOk };
  } finally {
    // Best-effort teardown (idempotent rm -rf with force:true). The
    // teardown helper already mirrors any failure to Sentry — wrapping
    // in .catch() here is a paranoid double-net to ensure a teardown
    // throw can never escape the finally and mask a real upstream error.
    await teardownEphemeralWorkspace(ephemeralRoot, "cron-growth-execution").catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-growth-execution",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-growth-execution", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: scheduled cron (0 10 1,15 * * UTC — biweekly, 1st and 15th of
// each month at 10:00) + manual operator event
// `cron/growth-execution.manual-trigger`. account-scope concurrency
// "cron-platform" limits to 1 simultaneous cron-* invocation across the
// Hetzner node.

export const cronGrowthExecution = inngest.createFunction(
  {
    id: "cron-growth-execution",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 10 1,15 * *" },
    { event: "cron/growth-execution.manual-trigger" },
  ],
  cronGrowthExecutionHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
