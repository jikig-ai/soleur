// TR9 PR-9 (closes #4442) — Migrated from the GHA scheduled-agent-native-audit
// workflow (deleted in the same PR per TR9 I-13 hygiene). Fourth handler
// ported via the claude-code-spawn pattern; structural template is PR-7's
// cron-roadmap-review.ts (global-state prompt, no per-entity factory).
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
// NAME NOTE: Sentry monitor slug "scheduled-agent-native-audit" is NEW —
// the GHA predecessor had NO Sentry check-in (it ran on GHA's runner pool).
// The new Terraform resource sentry_cron_monitor.scheduled_agent_native_audit
// is added in the same PR (apps/web-platform/infra/sentry/cron-monitors.tf).
//
// SHAPE DIFF vs PR-7 cron-roadmap-review.ts:
//   - --max-turns 50 (was 40) — agent-native-audit launches 8 principle
//     sub-agents via the Task tool, each with their own turn budget; 50
//     outer turns is the per-skill envelope.
//   - --allowedTools adds Task (for sub-agent dispatch); drops WebSearch
//     and WebFetch (audit is purely codebase-introspection).
//   - --model claude-opus-4-8 (was sonnet-4-6) — the principle scoring is
//     opus-class reasoning, mirroring scheduled-bug-fixer's escalation.
//   - Cadence: monthly 15th 09:00 UTC (was weekly Monday).
//   - Skip-window: 30 days (was 6) — monthly cadence + stable findings
//     warrant a 30-day reopen-loop guard.
//   - Prompt body: agent-native-audit skill invocation with 8-sub-agent
//     dispatch + CAP_OPEN_ISSUES=20 / CAP_PER_RUN=5 cap-enforcement.
//
// PLUGIN-LOADING — Verbatim PR-5 ephemeral-workspace pattern:
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
// installation discovery → generateInstallationToken(installation.id).
// Injected as GH_TOKEN so the spawned claude can run its allowlisted
// issue-creator surface (`gh issue list/create`, `gh label list/create` —
// the ONLY Bash verbs the containment hook permits this cron; #5046 PR-2).

import {
  redactToken,
  mintInstallationToken,
  deferIfTier2Cron,
  postSentryHeartbeat,
  resolveBestEffortEvalOk,
  ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS,
  REPO_NAME,
  type HandlerArgs,
} from "./_cron-shared";
import {
  setupEphemeralWorkspace,
  teardownEphemeralWorkspace,
  spawnClaudeEval,
  type SpawnResult,
} from "./_cron-claude-eval-substrate";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback, warnSilentFallback } from "@/server/observability";
import { AUDIT_MODEL } from "@/server/inngest/model-tiers";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-agent-native-audit";

// Token-lifetime floor passed to generateInstallationToken: claude-eval's
// 50-min wall-clock budget + 10-min slack for setup + teardown + retry.
const TOKEN_MIN_LIFETIME_MS = 50 * 60 * 1000 + 10 * 60 * 1000;

// 50 min wall-clock budget. Math: 50min / 50turns = 1.0 min/turn,
// comfortably above the 0.75 min/turn floor. Exported for test parity
// (cron-agent-native-audit.test.ts imports to avoid hard-coded timing drift
// across SUT tuning).
export const MAX_TURN_DURATION_MS = 50 * 60 * 1000;
export { KILL_ESCALATION_MS } from "./_cron-claude-eval-substrate";

// claude-code spawn argv. `--` is load-bearing per #4017 bug 8/8 (variadic
// --allowedTools consumes the prompt as a tool name without the end-of-
// options marker). The prompt is the SOLE positional argument after `--`.
//
// Mirrors .github/workflows/scheduled-agent-native-audit.yml `claude_args`:
//   --model claude-opus-4-8
//   --max-turns 50
//   --allowedTools Bash,Read,Write,Edit,Glob,Grep,Task
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  AUDIT_MODEL,
  "--max-turns",
  "50",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep,Task,Skill",
  "--plugin-dir",
  "plugins/soleur",
  "--",
];

// Verbatim prompt extracted from
// .github/workflows/scheduled-agent-native-audit.yml lines 80-112 (the
// `prompt: |` block body, 12-space YAML indentation stripped).
// Verbatim-extraction discipline: anchor strings ("Run /soleur:agent-native-audit",
// "CAP_OPEN_ISSUES = 20", "CAP_PER_RUN     = 5", "[Scheduled] Agent-Native Audit",
// "8 principle sub-agents") asserted by the test suite to catch silent
// paraphrasing across plan→work cycles.
const AGENT_NATIVE_AUDIT_PROMPT = `IMPORTANT: This is an automated CI workflow. Do NOT push directly
to main. Do NOT create commits.

MILESTONE RULE: Every gh issue create command MUST include
--milestone "Post-MVP / Later".

Run /soleur:agent-native-audit on this repository. Each of the 8
principle sub-agents produces a scored finding; collect findings
into a structured list before filing.

Cap enforcement is mandatory:
  CAP_OPEN_ISSUES = 20   (refuse to file when reached; run
                          \`gh issue list --label scheduled-agent-native-audit
                           --state open --limit 30\` and count the listed
                          issues yourself — shell pipes such as | wc -l are
                          denied by the containment hook)
  CAP_PER_RUN     = 5    (severity-ranked top-N filed per run)

For each filed issue:
  - Title prefix: "[Scheduled] Agent-Native Audit — <principle>: <gap>"
  - Labels: scheduled-agent-native-audit
  - Milestone: "Post-MVP / Later"
  - Body: principle name, score, specific gap, recommendation,
    referenced files

Idempotency: before filing, check
  gh issue list --label scheduled-agent-native-audit \\
                --search "<gap-summary> in:title" --state all --limit 5
and skip if any existing issue (open or closed within 30 days)
matches. Prevents reopen-loops on stable findings.

Injection safety: write each finding's body to a file (the Write
tool) and pass it via \`--body-file <path>\` BEFORE \`gh issue
create\` — never interpolate agent output into bash commands
directly (env-var assignment prefixes are denied by the
containment hook).
`;

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

export async function cronAgentNativeAuditHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean; errorSummary?: string }> {
  // D6 (#5018) / #5046 PR-2: RESTORED — out of TIER2_DEFERRED_CRONS since the
  // relax-minimal hook allows Task (this cron's only denied construct). The
  // guard stays as a no-op shape-keeper: it returns false while the cron is
  // absent from the defer set, and re-pausing is a one-line set edit.
  if (
    await deferIfTier2Cron({
      cronName: "cron-agent-native-audit",
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      step,
      logger,
    })
  ) {
    return { ok: true };
  }

  // --- Step 1: mint installation token (memoized across replays) ---
  // The raw token string is the return value (NEVER log this value).
  // Least-privilege scope (#5046 PR-2): issue-creator preset — contents:read
  // (clone) + issues:write (issue/label filing). Push/PR stay denied at the
  // TOKEN layer, not solely by the hook. Repo-scoped to soleur → a leaked
  // GH_TOKEN is bounded to a single-user incident.
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
        permissions: ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS,
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
      return setupEphemeralWorkspace({ installationToken, cronName: "cron-agent-native-audit" });
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
      feature: "cron-agent-native-audit",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-agent-native-audit" },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-agent-native-audit", logger });
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
    // --- Step 3: claude-eval (50-min AbortController) ---
    const spawnResult = await step.run(
      "claude-eval",
      async (): Promise<SpawnResult> => {
        return spawnClaudeEval({
          spawnCwd: spawnCwd!,
          installationToken,
          flags: CLAUDE_CODE_FLAGS,
          prompt: AGENT_NATIVE_AUDIT_PROMPT,
          maxTurnDurationMs: MAX_TURN_DURATION_MS,
          cronName: "cron-agent-native-audit",
          buildSpawnEnv,
          logger,
        });
      },
    );

    // #5674 — classify-fatal heartbeat (NOT flip-all). resolveBestEffortEvalOk
    // inspects the captured tail: a non-zero exit matching a FATAL class (credit
    // exhausted, auth/401 revoked, spawn fault, AbortController timeout) flips the
    // monitor RED and records the scrubbed reason in routine_runs; a BENIGN
    // non-zero exit (a clean audit run legitimately files nothing per-gap) stays
    // GREEN (liveness) but still surfaces the reason via warnSilentFallback +
    // sentryExtra. This keeps the #4730/#4727 protection (benign max-turns must
    // not daily-false-page) while restoring a red signal for the genuinely-fatal
    // classes the old unconditional-green policy masked (the 2026-06-29 credit
    // incident). The abortedByTimeout infra-fault is folded into the fatal class —
    // single signal, no double-report. See ADR-033 (classify-fatal invariant) +
    // knowledge-base/.../2026-06-29-fix-claude-eval-cron-failure-observability-plan.md.
    const decision = resolveBestEffortEvalOk(spawnResult);
    if (!decision.ok) {
      reportSilentFallback(
        new Error(decision.errorSummary ?? "claude-eval fatal failure"),
        {
          feature: "cron-agent-native-audit",
          op: "claude-eval-fatal",
          message:
            "claude-eval failed for a FATAL class (credit/auth/spawn/timeout); cron monitor flips red",
          extra: { fn: "cron-agent-native-audit", ...decision.sentryExtra },
        },
      );
    } else if (!spawnResult.ok) {
      // BENIGN non-zero — queryable WARNING, NOT a page (the #4730 carve-out).
      // warnSilentFallback (not a bare logger.warn) is load-bearing: a pino
      // logger.warn only adds a Sentry breadcrumb (flushed solely on a later
      // captureException a clean ok:true run never produces) and lands in a
      // Docker json-file stream Vector does not tail — invisible without SSH
      // (cq-silent-fallback-must-mirror-to-sentry, hr-observability-layer-citation).
      warnSilentFallback(
        new Error("claude-eval exited non-zero — best-effort run, no artifact this cycle"),
        {
          feature: "cron-agent-native-audit",
          op: "claude-eval-nonzero-noop",
          message:
            "claude-eval exited non-zero (benign best-effort); cron monitor stays green (liveness, not success)",
          extra: { fn: "cron-agent-native-audit", ...decision.sentryExtra },
        },
      );
    }

    // --- Step 4: sentry-heartbeat (final POST) ---
    // classify-fatal: green on a clean/benign run, red on a fatal-class failure.
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: decision.ok, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-agent-native-audit", logger });
    });

    return { ok: decision.ok, errorSummary: decision.errorSummary };
  } finally {
    // Best-effort teardown (idempotent rm -rf with force:true). The
    // teardown helper already mirrors any failure to Sentry — wrapping
    // in .catch() here is a paranoid double-net to ensure a teardown
    // throw can never escape the finally and mask a real upstream error.
    await teardownEphemeralWorkspace(ephemeralRoot, "cron-agent-native-audit").catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-agent-native-audit",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-agent-native-audit", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: scheduled cron (0 9 15 * * UTC — monthly 15th 09:00) + manual
// operator event `cron/agent-native-audit.manual-trigger`. account-scope
// concurrency "cron-platform" limits to 1 simultaneous cron-* invocation
// across the Hetzner node (PR-1 / PR-4 / PR-5 precedent).

export const cronAgentNativeAudit = inngest.createFunction(
  {
    id: "cron-agent-native-audit",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 9 15 * *" },
    { event: "cron/agent-native-audit.manual-trigger" },
  ],
  cronAgentNativeAuditHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
