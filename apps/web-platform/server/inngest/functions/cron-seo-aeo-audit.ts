// TR9 Phase-2 — Migrated from the GHA scheduled-seo-aeo-audit
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
// NAME NOTE: Sentry monitor slug "scheduled-seo-aeo-audit" is NEW — the
// GHA predecessor had NO Sentry check-in (it ran on GHA's runner pool).
//
// SHAPE DIFF vs cron-roadmap-review.ts:
//   - --model claude-sonnet-4-6 (same).
//   - --max-turns 40 (same).
//   - --allowedTools Bash,Read,Write,Edit,Glob,Grep (no WebSearch/WebFetch
//     needed — SEO/AEO audit operates on local source files).
//   - MAX_TURN_DURATION_MS 30 min (lower than 50 min cohort — weekly
//     SEO/AEO audit is a lighter workload).
//   - Cron: weekly Monday 11:00 UTC (staggered from 10:00 per plan to
//     avoid collision with growth-execution on 1st/15th).
//   - Side-effect class: issue-creator + pr-creator (persistence runs
//     handler-side via safeCommitAndPr after the eval — #5091; the prompt
//     forbids the spawned claude from running git/gh-pr verbs).
//
// PLUGIN-LOADING — Verbatim ephemeral-workspace pattern:
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
  type SpawnResult,
} from "./_cron-claude-eval-substrate";
import { safeCommitAndPr } from "./_cron-safe-commit";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import { EXECUTION_MODEL } from "@/server/inngest/model-tiers";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-seo-aeo-audit";

// Token-lifetime floor passed to generateInstallationToken: claude-eval's
// 30-min wall-clock budget + 10-min slack for setup + teardown + retry.
const TOKEN_MIN_LIFETIME_MS = 30 * 60 * 1000 + 10 * 60 * 1000;

// 30 min wall-clock budget. Math: 30min / 40turns = 0.75 min/turn,
// at the floor. Exported for test parity (cron-seo-aeo-audit.test.ts
// imports to avoid hard-coded timing drift across SUT tuning).
export const MAX_TURN_DURATION_MS = 30 * 60 * 1000;
export { KILL_ESCALATION_MS } from "./_cron-claude-eval-substrate";

// claude-code spawn argv. `--` is load-bearing per #4017 bug 8/8 (variadic
// --allowedTools consumes the prompt as a tool name without the end-of-
// options marker). The prompt is the SOLE positional argument after `--`.
//
// Mirrors .github/workflows/scheduled-seo-aeo-audit.yml `claude_args`:
//   --model claude-sonnet-4-6
//   --max-turns 40
//   --allowedTools Bash,Read,Write,Edit,Glob,Grep
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

// Ported from .github/workflows/scheduled-seo-aeo-audit.yml; #5091 removed
// the prompt-level commit block (the platform persists handler-side via
// safeCommitAndPr — a blanket add here staged 654 structural deletions in
// destructive PR #5026).
// Verbatim-extraction discipline: anchor strings ("seo-aeo", "SEO/AEO
// Audit", "scheduled-seo-aeo-audit", "Do NOT run git add") asserted by
// the test suite to catch silent paraphrasing across plan→work cycles.
const SEO_AEO_AUDIT_PROMPT = `IMPORTANT: This is an automated CI workflow. Do NOT push directly to main.

MILESTONE RULE: Every gh issue create command must include --milestone "Post-MVP / Later".

Run /soleur:seo-aeo fix on this repository.

VALIDATION runs in CI (do NOT build locally): this ephemeral workspace is a shallow clone with no node_modules, so a local "npx @11ty/eleventy" build and the validate-seo.sh / validate-csp.sh scripts cannot run here. Validation happens on the PR the platform opens from your changes after the run: CI runs the eleventy build and SEO/CSP validation, and the PR only auto-merges once those required checks pass. Do NOT attempt a local build or run the validation scripts yourself.

After the audit and fix is complete, create a GitHub issue titled "[Scheduled] SEO/AEO Audit - <today>" with the label "scheduled-seo-aeo-audit" summarizing what issues were found and what fixes were applied.

PERSISTENCE: Do NOT run git add, git commit, git push, or gh pr create/merge.
The platform commits and opens a PR for your changes automatically after the run.
Only changes under plugins/soleur/docs/ are persisted — keep all edits inside that path.
Creating the audit issue above is REQUIRED: the platform only persists your changes after it verifies the issue exists.
`;

// Persistence allowlist (#5091): the audit edits the Eleventy docs site under
// the plugin tree — committable from the clone now that the substrate no
// longer symlink-shadows plugins/soleur.
const SEO_AEO_ALLOWED_PATHS = ["plugins/soleur/docs/"] as const;

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

export async function cronSeoAeoAuditHandler({
  step,
  logger,
  attempt,
  maxAttempts,
}: HandlerArgs): Promise<{ ok: boolean }> {
  // D6 (#5018) / #5046 PR-2: still Tier-2-deferred — the firewall landed but
  // this cron needs per-construct Bash-allowlist refinement or non-GitHub
  // egress coverage before restore (see TIER2_DEFERRED_CRONS). Posts an
  // honest on-schedule check-in and skips the claude spawn (no fail-closed
  // FAILED-issue/RED-monitor storm); the scheduled output issue visibly stops.
  if (
    await deferIfTier2Cron({
      cronName: "cron-seo-aeo-audit",
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
      return setupEphemeralWorkspace({ installationToken, cronName: "cron-seo-aeo-audit" });
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
      feature: "cron-seo-aeo-audit",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-seo-aeo-audit" },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-seo-aeo-audit", logger });
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
    // hoisted so the silence-hole audit issue can read it even when a later
    // step threw.
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
            prompt: SEO_AEO_AUDIT_PROMPT,
            maxTurnDurationMs: MAX_TURN_DURATION_MS,
            cronName: "cron-seo-aeo-audit",
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
            feature: "cron-seo-aeo-audit",
            op: "claude-eval-timeout",
            message: "claude-eval aborted by AbortController",
            extra: {
              fn: "cron-seo-aeo-audit",
              durationMs: spawnResult.durationMs,
              maxMs: MAX_TURN_DURATION_MS,
            },
          },
        );
      }

      // --- Step 4: output-aware heartbeat. This cron is an always-create
      //     producer — it files a `[Scheduled] SEO/AEO Audit - <today>` summary
      //     issue every run — so a clean exit that produced no
      //     `scheduled-seo-aeo-audit` issue in the run window turns the monitor RED
      //     (and emits `scheduled-output-missing`) instead of false-green on
      //     claude's exit code. Mirrors the 3 producers wired by PR #4714 (#4730).
      //     Infra faults still page via the early-return status=error heartbeats. ---
      heartbeatOk = await step.run("verify-output", async () =>
        resolveOutputAwareOk({
          spawnOk: spawnResult!.ok,
          label: SENTRY_MONITOR_SLUG,
          runStartedAt,
          cronName: "cron-seo-aeo-audit",
          stderrTail: spawnResult!.stderrTail,
          exitCode: spawnResult!.exitCode,
          stdoutTail: spawnResult!.stdoutTail,
        }),
      );
      // --- Step 4.5: deterministic persistence (#5091). Gated on the
      //     issue-verified output rather than the spawn exit code:
      //     exit-0-with-no-issue is unverified (possibly mid-edit) work that
      //     must not auto-merge, while issue-created + non-zero exit is the
      //     documented healthy #4747 case whose diff must not be discarded.
      //     (Caveat: resolveOutputAwareOk falls back to the spawn exit code
      //     when its GitHub verify-read THROWS — a tri-state gate is tracked
      //     in #5139.) abortedByTimeout also skips —
      //     a 30-min hard kill can land mid-edit, and the timeout is already
      //     loud via the reportSilentFallback above. Guard aborts / persistence
      //     failures self-report inside the helper (Sentry + issue comment).
      if (heartbeatOk && !spawnResult.abortedByTimeout) {
        await step.run("safe-commit-pr", async () =>
          safeCommitAndPr({
            spawnCwd: spawnCwd!,
            installationToken,
            cronName: "cron-seo-aeo-audit",
            commitMessage: "fix(seo): weekly SEO/AEO audit fixes",
            allowedPaths: SEO_AEO_ALLOWED_PATHS,
            runStartedAt,
            scheduledIssueLabel: SENTRY_MONITOR_SLUG,
            logger,
          }),
        );
      }
    } catch (err) {
      // #5728 G1 — a deploy-in-progress defer is benign (ADR-068/#5686): rethrow
      // bare with NO heartbeat so Inngest retries after the swap. Any OTHER throw
      // is a real failure — flag it; finalizeOutputAwareHeartbeat decides
      // error-vs-retry below. An output-PRESENT run that threw in a TRAILING step
      // (safe-commit-pr) stays GREEN — heartbeatOk is already true and the
      // persistence failure self-reports here.
      if (err instanceof DeployInProgressError) throw err;
      threw = true;
      const e = err as Error;
      const redactedMsg = redactToken(e.message ?? "", installationToken);
      const redacted = new Error(redactedMsg);
      redacted.name = e.name;
      reportSilentFallback(redacted, {
        feature: "cron-seo-aeo-audit",
        op: "handler-body-threw",
        message:
          "cron-seo-aeo-audit body threw before the terminal heartbeat",
        extra: {
          fn: "cron-seo-aeo-audit",
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
      cronName: "cron-seo-aeo-audit",
      logger,
      onBeforeHeartbeat: heartbeatOk
        ? undefined
        : async () => {
            await step.run("ensure-audit-issue", async () => {
              try {
                await ensureScheduledAuditIssue({
                  label: SENTRY_MONITOR_SLUG,
                  titlePrefix: "[Scheduled] SEO/AEO Audit -",
                  cronName: "cron-seo-aeo-audit",
                  runStartedAt,
                  spawnResult: spawnResult ?? {
                    exitCode: -1,
                    signal: null,
                    abortedByTimeout: false,
                    durationMs: 0,
                    stdoutTail: "",
                    stderrTail: "cron-seo-aeo-audit threw before claude-eval completed",
                  },
                  installationToken,
                });
              } catch (err) {
                reportSilentFallback(err, {
                  feature: "cron-seo-aeo-audit",
                  op: "ensure-audit-issue-failed",
                  message:
                    "Handler-level fallback audit-issue create failed; run remains silent until watchdog threshold",
                  extra: { fn: "cron-seo-aeo-audit", runStartedAt },
                });
              }
            });
          },
    });
    if (retry) {
      throw new Error(
        "cron-seo-aeo-audit failed on a non-final attempt; retrying",
      );
    }

    return { ok: heartbeatOk };
  } finally {
    // Best-effort teardown (idempotent rm -rf with force:true). The
    // teardown helper already mirrors any failure to Sentry — wrapping
    // in .catch() here is a paranoid double-net to ensure a teardown
    // throw can never escape the finally and mask a real upstream error.
    await teardownEphemeralWorkspace(ephemeralRoot, "cron-seo-aeo-audit").catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-seo-aeo-audit",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-seo-aeo-audit", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: scheduled cron (0 11 * * 1 UTC — weekly Monday 11:00, staggered
// from 10:00 per plan) + manual operator event
// `cron/seo-aeo-audit.manual-trigger`. account-scope concurrency
// "cron-platform" limits to 1 simultaneous cron-* invocation across the
// Hetzner node.

export const cronSeoAeoAudit = inngest.createFunction(
  {
    id: "cron-seo-aeo-audit",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 11 * * 1" },
    { event: "cron/seo-aeo-audit.manual-trigger" },
  ],
  cronSeoAeoAuditHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
