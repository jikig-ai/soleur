// TR9 PR-10 (closes #4448) — Migrated from the GHA scheduled-competitive-analysis
// workflow (deleted in the same PR per TR9 I-13 hygiene). Fifth handler
// ported via the claude-code-spawn pattern; structural template is PR-7's
// cron-roadmap-review.ts (closest sibling — same WebSearch+WebFetch+Task
// allowlist cohort and same dual-side-effect shape: filing an issue AND
// opening a follow-up PR, persisted handler-side via safeCommitAndPr
// since #5111).
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — claude binary spawned INSIDE step.run (Inngest replay memoization).
//   I2 — Operator ANTHROPIC_API_KEY only; never founder BYOK. Enforced at
//        build time by test/server/cron-no-byok-lease-sweep.test.ts.
//   I3 — AbortSignal aborts at MAX_TURN_DURATION_MS (50 min). Manual
//        SIGTERM→SIGKILL escalation via process-group kill (detached:true).
//   I4 — claude binary resolved at spawn time via filesystem checks; the
//        CLAUDE_BIN env var is the override hatch for fresh-host bootstraps.
//   I5 — Deterministic step.run return shape: {ok, exitCode, signal,
//        abortedByTimeout, durationMs}. stdout is NOT captured.
//   I6 — Event payloads emitted by cron-*.ts MUST carry actor: "platform".
//        (This handler emits none.)
//
// NAME NOTE: Sentry monitor slug "scheduled-competitive-analysis" is NEW —
// the GHA predecessor had NO Sentry check-in (it ran on GHA's runner pool).
// The new Terraform resource sentry_cron_monitor.scheduled_competitive_analysis
// is added in the same PR (apps/web-platform/infra/sentry/cron-monitors.tf).
//
// SHAPE DIFF vs PR-7 cron-roadmap-review.ts:
//   - --model claude-opus-4-8 — competitive-analysis
//     skill uses opus for cross-tier landscape reasoning.
//   - --max-turns 45 (was 40) — multi-tier fan-out (tiers 0,3) plus the
//     follow-up PR creation step needs slightly more headroom.
//   - --allowedTools adds Task to PR-7's set (Bash,Read,Write,Edit,Glob,Grep,
//     WebSearch,WebFetch + Task) — competitive-analysis skill delegates
//     per-tier scans via sub-agent invocations.
//   - Cron: monthly 1st @ 09:00 UTC (was weekly Monday).
//   - Side-effect class: issue-creator + pr-creator (persistence runs
//     handler-side via safeCommitAndPr after the eval — #5111; the prompt
//     forbids the spawned claude from running git/gh-pr verbs).
//
// PLUGIN-LOADING — Verbatim PR-5/PR-7 ephemeral-workspace pattern:
//   - repo/                          (in-handler `git clone --depth=1`)
//   - repo/plugins/soleur            (the clone's own tracked tree — #5091)
//   - repo/.claude/settings.json     (DEFAULT_SETTINGS overlay)
// Plugin resolution under headless `--print` requires the explicit
// `--plugin-dir plugins/soleur` flag in CLAUDE_CODE_FLAGS below — the
// plugins/soleur dir is NOT auto-discovered from spawn cwd in headless mode (the
// interactive marketplace/enabledPlugins trust flow does not run under --print).
// See #4993 / #4987.
//
// GH TOKEN — installation token minted via createProbeOctokit() →
// installation discovery → generateInstallationToken(installation.id), narrowed
// to DEFAULT_CRON_TOKEN_PERMISSIONS scoped to [REPO_NAME] (#5199).
// Injected as GH_TOKEN so the spawned claude can run the allowlisted
// `gh issue create` + `gh label` verbs (persistence runs handler-side via
// safeCommitAndPr — #5111; the prompt forbids git/gh-pr verbs and the
// containment hook denies `gh api`).

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
import { AUDIT_MODEL } from "@/server/inngest/model-tiers";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-competitive-analysis";

// Token-lifetime floor passed to generateInstallationToken: claude-eval's
// 50-min wall-clock budget + 10-min slack for setup + teardown + retry.
const TOKEN_MIN_LIFETIME_MS = 50 * 60 * 1000 + 10 * 60 * 1000;

// 50 min wall-clock budget. Math: 50min / 45turns = ~1.1 min/turn,
// above the 0.75 min/turn floor. Exported for test parity
// (cron-competitive-analysis.test.ts imports to avoid hard-coded timing
// drift across SUT tuning).
export const MAX_TURN_DURATION_MS = 50 * 60 * 1000;
export { KILL_ESCALATION_MS } from "./_cron-claude-eval-substrate";

// claude-code spawn argv. `--` is load-bearing per #4017 bug 8/8 (variadic
// --allowedTools consumes the prompt as a tool name without the end-of-
// options marker). The prompt is the SOLE positional argument after `--`.
//
// Mirrors .github/workflows/scheduled-competitive-analysis.yml `claude_args`:
//   --model claude-opus-4-8
//   --max-turns 45
//   --allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Task
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  AUDIT_MODEL,
  "--max-turns",
  "45",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Task,Skill",
  "--plugin-dir",
  "plugins/soleur",
  "--",
];

// Verbatim prompt extracted from
// .github/workflows/scheduled-competitive-analysis.yml lines 67-95 (the
// `prompt: |` block body, 12-space YAML indentation stripped). #5111
// removed the prompt-level commit block (the platform persists
// handler-side via safeCommitAndPr — the #5091 consolidation pattern).
// Verbatim-extraction discipline: anchor strings ("MILESTONE RULE:",
// "Run /soleur:competitive-analysis --tiers 0,3", the PERSISTENCE
// directive's opening line (quoted only inside the prompt so the test's
// whole-file anchor cannot be satisfied by this comment),
// "[Scheduled] Competitive Analysis", "scheduled-competitive-analysis",
// "competitive-intelligence.md") asserted by the test suite to catch
// silent paraphrasing across plan→work cycles.
const COMPETITIVE_ANALYSIS_PROMPT = `IMPORTANT: This is an automated CI workflow. The AGENTS.md rule
Do NOT push directly to main.

MILESTONE RULE: Every gh issue create command must include --milestone "Post-MVP / Later".

Run /soleur:competitive-analysis --tiers 0,3 on this repository.
After your analysis is complete, create a GitHub issue titled
"[Scheduled] Competitive Analysis - <today's date in YYYY-MM-DD format>"
with the label "scheduled-competitive-analysis" summarizing your findings.

PERSISTENCE: Do NOT run git add, git commit, git push, or gh pr create/merge.
The platform commits and opens a PR for your changes automatically after the run.
Only changes under knowledge-base/product/competitive-intelligence.md, knowledge-base/marketing/content-strategy.md, knowledge-base/product/pricing-strategy.md, knowledge-base/sales/battlecards/, and knowledge-base/marketing/seo-refresh-queue.md are persisted — keep all edits inside those paths.
Creating the analysis issue above is REQUIRED: the platform only persists your changes after it verifies the issue exists.
`;

// Persistence allowlist (#5111): the full cascade write-set, NOT just the
// report file — the Cascade Delegation Table in
// plugins/soleur/agents/product/competitive-intelligence.md routes findings
// to content-strategist (content-strategy.md), product-pricing-strategist
// (pricing-strategy.md), sales-battlecards (battlecards/), and seo-refresher
// (seo-refresh-queue.md). This is a deliberate widening: the old prompt
// committed ONLY competitive-intelligence.md and silently discarded the
// cascade outputs. The agent file's CASCADE LIMIT-4 comment caps the
// specialist fan-out at 4 — widening the cascade there requires widening
// this list in lockstep.
export const COMPETITIVE_ANALYSIS_ALLOWED_PATHS = [
  "knowledge-base/product/competitive-intelligence.md",
  "knowledge-base/marketing/content-strategy.md",
  "knowledge-base/product/pricing-strategy.md",
  "knowledge-base/sales/battlecards/",
  "knowledge-base/marketing/seo-refresh-queue.md",
] as const;

// Spawn-env allowlist (NOT a denylist). PR-5 shape verbatim — the keys
// below are the COMPLETE set the spawned claude is allowed to see;
// anything not listed (notably RESEND_API_KEY, SENTRY_*, DOPPLER_*,
// GITHUB_APP_PRIVATE_KEY) is excluded.
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

export async function cronCompetitiveAnalysisHandler({
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
      cronName: "cron-competitive-analysis",
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      step,
      logger,
    })
  ) {
    return { ok: true };
  }

  // Run-window start for the post-run output check (replay-stable).
  const runStartedAt = await step.run(
    "run-started-at",
    async () => new Date().toISOString(),
  );

  // #5786 — producer-side date-dedup (extends the #5751 community-monitor fix).
  // If a real `[Scheduled] Competitive Analysis - <date>` digest already exists
  // for today, skip the eval and post a healthy OK heartbeat — do NOT fall
  // through to verify-output, whose run-window (updated_at >= THIS runStartedAt)
  // would exclude the earlier issue and false-RED the skip.
  // concurrency:{scope:"fn",limit:1} (registration below) serializes the two
  // invocations, so the second's FRESH LIST read sees the first's create. Date
  // anchor is runStartedAt.slice(0,10) (replay-stable). Fail-OPEN: a read error
  // → spawn (a duplicate paper-cut beats a missed digest).
  const digestAlreadyExists = await step.run("dedup-digest-check", async () =>
    digestIssueExistsForDate({
      label: SENTRY_MONITOR_SLUG,
      titlePrefix: "[Scheduled] Competitive Analysis -",
      date: runStartedAt.slice(0, 10),
      cronName: "cron-competitive-analysis",
    }),
  );
  if (digestAlreadyExists) {
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({
        ok: true,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-competitive-analysis",
        logger,
      });
    });
    return { ok: true };
  }

  // --- Step 1: mint installation token (memoized across replays) ---
  // The raw token string is the return value (NEVER log this value).
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
  // Track ephemeralRoot in handler-scope so teardown runs regardless of
  // downstream success/failure.
  let ephemeralRoot: string | null = null;
  let spawnCwd: string | null = null;
  try {
    const workspace = await step.run("setup-workspace", async () => {
      return setupEphemeralWorkspace({ installationToken, cronName: "cron-competitive-analysis" });
    });
    ephemeralRoot = workspace.ephemeralRoot;
    spawnCwd = workspace.spawnCwd;
  } catch (err) {
    // #5728 G1 — benign deploy-in-progress defer (ADR-068): rethrow bare, no heartbeat.
    if (err instanceof DeployInProgressError) throw err;
    // Redact token if it sneaks into the error message (defense-in-depth).
    const e = err as Error;
    const redactedMsg = redactToken(e.message ?? "", installationToken);
    const redacted = new Error(redactedMsg);
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: "cron-competitive-analysis",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-competitive-analysis" },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-competitive-analysis", logger });
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
    // #5728 — flag pattern. The body (claude-eval → verify-output →
    // safe-commit-pr) runs in an inner try whose throw sets `threw`; the single
    // terminal heartbeat is posted (or skipped-for-retry) by
    // finalizeOutputAwareHeartbeat below — NOT from a second catch-site (which,
    // under retries:1 memoization, would replay a stale `ok` while posting a
    // conflicting `error`). A throw before the heartbeat previously propagated
    // out → the heartbeat step never ran → silent `missed`. spawnResult is
    // hoisted so the silence-hole audit issue can read it even when a later step
    // threw.
    let heartbeatOk = false;
    let threw = false;
    let spawnResult: SpawnResult | null = null;
    try {
      // --- Step 3: claude-eval (50-min AbortController) ---
      spawnResult = await step.run(
        "claude-eval",
        async (): Promise<SpawnResult> => {
          return spawnClaudeEval({
            spawnCwd: spawnCwd!,
            installationToken,
            flags: CLAUDE_CODE_FLAGS,
            prompt: COMPETITIVE_ANALYSIS_PROMPT,
            maxTurnDurationMs: MAX_TURN_DURATION_MS,
            cronName: "cron-competitive-analysis",
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
            feature: "cron-competitive-analysis",
            op: "claude-eval-timeout",
            message: "claude-eval aborted by AbortController",
            extra: {
              fn: "cron-competitive-analysis",
              durationMs: spawnResult.durationMs,
              maxMs: MAX_TURN_DURATION_MS,
            },
          },
        );
      }

      // --- Step 4: output-aware heartbeat. A clean exit that produced no
      //     `scheduled-competitive-analysis` issue in the run window turns the
      //     monitor RED (and emits `scheduled-output-missing`) instead of
      //     false-green. ---
      heartbeatOk = await step.run("verify-output", async () =>
        resolveOutputAwareOk({
          spawnOk: spawnResult!.ok,
          label: SENTRY_MONITOR_SLUG,
          runStartedAt,
          cronName: "cron-competitive-analysis",
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
            cronName: "cron-competitive-analysis",
            commitMessage: "docs: update competitive intelligence report",
            allowedPaths: COMPETITIVE_ANALYSIS_ALLOWED_PATHS,
            runStartedAt,
            scheduledIssueLabel: SENTRY_MONITOR_SLUG,
            logger,
          }),
        );
      }
    } catch (err) {
      // #5728 G1 — benign deploy-in-progress defer (ADR-068): rethrow bare, no
      // heartbeat. Any OTHER throw is a real failure — flag it;
      // finalizeOutputAwareHeartbeat decides error-vs-retry below.
      if (err instanceof DeployInProgressError) throw err;
      threw = true;
      const e = err as Error;
      const redactedMsg = redactToken(e.message ?? "", installationToken);
      const redacted = new Error(redactedMsg);
      redacted.name = e.name;
      reportSilentFallback(redacted, {
        feature: "cron-competitive-analysis",
        op: "handler-body-threw",
        message:
          "cron-competitive-analysis body threw before the terminal heartbeat",
        extra: {
          fn: "cron-competitive-analysis",
          attempt: attempt ?? 0,
          producedOutput: heartbeatOk,
        },
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
      cronName: "cron-competitive-analysis",
      logger,
      onBeforeHeartbeat: heartbeatOk
        ? undefined
        : async () => {
            await step.run("ensure-audit-issue", async () => {
              try {
                await ensureScheduledAuditIssue({
                  label: SENTRY_MONITOR_SLUG,
                  titlePrefix: "[Scheduled] Competitive Analysis -",
                  cronName: "cron-competitive-analysis",
                  runStartedAt,
                  spawnResult: spawnResult ?? makeThrewSpawnResult("cron-competitive-analysis"),
                  installationToken,
                });
              } catch (err) {
                reportSilentFallback(err, {
                  feature: "cron-competitive-analysis",
                  op: "ensure-audit-issue-failed",
                  message:
                    "Handler-level fallback audit-issue create failed; run remains silent until watchdog threshold",
                  extra: { fn: "cron-competitive-analysis", runStartedAt },
                });
              }
            });
          },
    });
    if (retry) {
      throw new Error(
        "cron-competitive-analysis failed on a non-final attempt; retrying",
      );
    }

    return { ok: heartbeatOk };
  } finally {
    // Best-effort teardown (idempotent rm -rf with force:true). The
    // teardown helper already mirrors any failure to Sentry — wrapping
    // in .catch() here is a paranoid double-net to ensure a teardown
    // throw can never escape the finally and mask a real upstream error.
    await teardownEphemeralWorkspace(ephemeralRoot, "cron-competitive-analysis").catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-competitive-analysis",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-competitive-analysis", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: scheduled cron (0 9 1 * * UTC — monthly, 1st of each month at
// 09:00) + manual operator event `cron/competitive-analysis.manual-trigger`.
// account-scope concurrency "cron-platform" limits to 1 simultaneous cron-*
// invocation across the Hetzner node (PR-1 / PR-4 / PR-5 / PR-7 / PR-8
// precedent).

export const cronCompetitiveAnalysis = inngest.createFunction(
  {
    id: "cron-competitive-analysis",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 9 1 * *" },
    { event: "cron/competitive-analysis.manual-trigger" },
  ],
  cronCompetitiveAnalysisHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
