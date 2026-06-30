// TR9 PR-7 (closes #4425) — Migrated from the GHA scheduled-roadmap-review
// workflow (deleted in the same PR per TR9 I-13 hygiene). Second handler
// ported via the claude-code-spawn pattern; structural template is PR-5's
// cron-bug-fixer.ts (PR-6 used the alternate pure-TS pattern).
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
// NAME NOTE: Sentry monitor slug "scheduled-roadmap-review" is NEW — the
// GHA predecessor had NO Sentry check-in (it ran on GHA's runner pool).
// The new Terraform resource sentry_cron_monitor.scheduled_roadmap_review
// is added in the same PR (apps/web-platform/infra/sentry/cron-monitors.tf).
//
// SHAPE DIFF vs PR-5 cron-bug-fixer.ts:
//   - NO auto-merge gate (this handler does roadmap hygiene, not bug-fix
//     PR auto-merge).
//   - NO ops-email notification (no Resend POST).
//   - NO priority cascade / issue-selection (prompt operates over live
//     issue set; no per-issue TS-side filter).
//   - NO manual-trigger payload parsing (workflow_dispatch carried no
//     inputs; manual trigger event is fire-and-forget).
//   - --max-turns 40 (was 55); --allowedTools adds WebSearch,WebFetch
//     (mirrors the YAML's claude_args).
//
// PLUGIN-LOADING — Verbatim PR-5 ephemeral-workspace pattern:
//   - repo/                          (in-handler `git clone --depth=1`)
//   - repo/plugins/soleur            (the clone's own tracked tree — #5091)
//   - repo/.claude/settings.json     (DEFAULT_SETTINGS overlay)
// Plugin resolution under headless `--print` requires the explicit
// `--plugin-dir plugins/soleur` flag — the plugins/soleur dir is NOT
// auto-discovered from spawn cwd in headless mode (the interactive
// marketplace/enabledPlugins trust flow does not run under --print). This
// producer's prompt invokes no /soleur:* skill, so it needs no flag change; the
// comment is corrected so the disproven spawn-cwd auto-discovery theory cannot
// mislead future edits. See #4993 / #4987.
//
// GH TOKEN — installation token minted via createProbeOctokit() →
// installation discovery → generateInstallationToken(installation.id).
// Injected as GH_TOKEN so the spawned claude can run `gh api ...`,
// `gh issue create`, `gh pr create`, `gh label create`, `git push`.

import {
  redactToken,
  mintInstallationToken,
  digestIssueExistsForDate,
  postSentryHeartbeat,
  resolveOutputAwareOk,
  ensureScheduledAuditIssue,
  finalizeOutputAwareHeartbeat,
  DeployInProgressError,
  type HandlerArgs,
} from "./_cron-shared";
import {
  setupEphemeralWorkspace,
  teardownEphemeralWorkspace,
  spawnClaudeEval,
  makeThrewSpawnResult,
  type SpawnResult,
} from "./_cron-claude-eval-substrate";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import { EXECUTION_MODEL } from "@/server/inngest/model-tiers";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-roadmap-review";

// Token-lifetime floor passed to generateInstallationToken: claude-eval's
// 50-min wall-clock budget + 10-min slack for setup + teardown + retry.
const TOKEN_MIN_LIFETIME_MS = 50 * 60 * 1000 + 10 * 60 * 1000;

// 50 min wall-clock budget. Math: 50min / 40turns = 1.25 min/turn,
// comfortably above the 0.75 min/turn floor. Exported for test parity
// (cron-roadmap-review.test.ts imports to avoid hard-coded timing drift
// across SUT tuning).
export const MAX_TURN_DURATION_MS = 50 * 60 * 1000;
export { KILL_ESCALATION_MS } from "./_cron-claude-eval-substrate";

// claude-code spawn argv. `--` is load-bearing per #4017 bug 8/8 (variadic
// --allowedTools consumes the prompt as a tool name without the end-of-
// options marker). The prompt is the SOLE positional argument after `--`.
//
// Mirrors .github/workflows/scheduled-roadmap-review.yml `claude_args`:
//   --model claude-sonnet-4-6
//   --max-turns 40
//   --allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  EXECUTION_MODEL,
  "--max-turns",
  "40",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch",
  "--",
];

// Verbatim prompt extracted from
// .github/workflows/scheduled-roadmap-review.yml lines 61-108 (the
// `prompt: |` block body, 12-space YAML indentation stripped).
// Verbatim-extraction discipline: anchor strings ("Part 1: Issue-to-
// Milestone Alignment", "Part 2: Bidirectional Integrity Gate",
// "MILESTONE RULE:", "BIDIRECTIONAL RULE:") asserted by the test suite
// to catch silent paraphrasing across plan→work cycles.
const ROADMAP_REVIEW_PROMPT = `You are the CPO performing a weekly roadmap consistency review.

## Part 1: Issue-to-Milestone Alignment

1. Read knowledge-base/product/roadmap.md
2. Fetch all GitHub milestones (open and closed): gh api 'repos/jikig-ai/soleur/milestones?state=all&per_page=100' --jq '.[] | {number, title, state, open_issues, closed_issues}'
3. Fetch all open issues with milestones: gh api 'repos/jikig-ai/soleur/issues?state=open&per_page=100' --paginate --jq '.[] | {number, title, milestone: .milestone.title}'
4. For each open issue, check:
   - Is it assigned to the correct milestone per the roadmap?
   - Is it stale (superseded by roadmap decisions, no activity in 30+ days, references deprecated features)?
   - Does it have a priority label that matches its phase placement?

## Part 2: Bidirectional Integrity Gate (milestones <-> issues)

5. For each roadmap phase table, check:
   - Does EVERY feature row have a linked GitHub issue in the Issue column?
   - Does that issue actually exist and is it in the correct milestone?
   - If an issue is missing, flag it as MISSING_ISSUE
6. For each open milestone, check:
   - Does it have at least one open issue? An open milestone with 0 open issues is either stale (should be closed) or incomplete (features defined but no issues created)
   - Flag empty milestones as EMPTY_MILESTONE
7. For each roadmap feature status, check:
   - Does the status column match the actual issue state? (e.g., "Not started" but issue is closed = stale status)
   - Flag mismatches as STALE_STATUS

## Rules

MILESTONE RULE: Every gh issue create command must include --milestone.
Use --milestone "Post-MVP / Later" for operational/maintenance issues.
For feature issues, read knowledge-base/product/roadmap.md for available milestones and assign the one matching the relevant phase.

BIDIRECTIONAL RULE: Every feature in a roadmap phase table MUST have a linked GitHub issue. Every milestone MUST have at least one issue. These are both enforced -- violations are flagged as high severity.

CLONE DEPTH RULE: This workspace was cloned with --depth=1. Do NOT use \`git log\` for staleness analysis (every file appears "just touched"). Use GitHub Issue/PR \`updatedAt\` timestamps via \`gh api\` instead.

ISSUE CLOSURE SAFETY: BEFORE closing or reassigning ANY issue:
  (a) record the original state (milestone, labels, last activity) in your PR description so it is auditable;
  (b) only close issues with NO activity (no comments, no commits referencing the issue) in the last 14 days;
  (c) NEVER close issues with the labels \`in-progress\`, \`wip\`, \`auto-merge\`, or any priority label \`priority/p0-critical\`, \`priority/p1-high\`. Skip and flag for human review instead.

ROADMAP.MD CONFLICT GUARD: BEFORE editing knowledge-base/product/roadmap.md, run:
  gh pr list --state open --search 'roadmap.md in:files' --json number,title,headRefName
If any open PR touches roadmap.md, do NOT make conflicting edits. Instead, post a comment on that PR with your suggested updates and skip the roadmap.md edit in your own PR.

## Output

After your analysis, create a GitHub issue summarizing your findings.

DEDUP RULE (BEFORE creating the review issue): run
  gh issue list --label scheduled-roadmap-review --state all --json number,title,createdAt
If any results from within the last 6 days exist, do NOT create a new issue. Instead, post your findings as a comment on the most recent existing issue and exit. This prevents duplicate issues when a manual trigger fires the same week as the natural Monday 09:00 UTC cron.

If no recent duplicate exists, create a new issue with:
- Title format: [Scheduled] Weekly Roadmap Review - YYYY-MM-DD
- Label: scheduled-roadmap-review
- --milestone "Post-MVP / Later"

The issue body should contain:
- Health summary: X consistent, Y inconsistent, Z stale, W missing
- Bidirectional gate results: empty milestones, missing issues, stale statuses
- Recommended actions table (close, move, create, relabel)
- Any roadmap.md updates needed
- Audit log: list of issues you closed/reassigned with original state captured (per ISSUE CLOSURE SAFETY (a))

If inconsistencies are found that can be fixed automatically (milestone reassignment, stale issue closure, roadmap status updates),
create a branch, apply the fixes, and open a PR. If only the review issue is needed, skip the PR.

STAGING RULE (#5091): when committing fixes, stage only the specific files you edited (git add <path> [<path>...]). Blanket staging flags (-A, -u, --all) and bare \`.\` pathspecs are denied by the containment hook — the workspace carries expected-dirty scaffolding that must never enter a commit.
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

export async function cronRoadmapReviewHandler({
  step,
  logger,
  attempt,
  maxAttempts,
}: HandlerArgs): Promise<{ ok: boolean }> {
  // Run-window start — the lower bound for the post-run output check. Captured
  // before the mint step (memoized across Inngest replays) so a replay reuses
  // the original window rather than re-stamping a later "now".
  const runStartedAt = await step.run(
    "run-started-at",
    async () => new Date().toISOString(),
  );

  // #5786 — producer-side date-dedup (extends the #5751 community-monitor fix).
  // If a real `[Scheduled] Weekly Roadmap Review - <date>` digest already exists
  // for today, skip the eval and post a healthy OK heartbeat — do NOT fall
  // through to verify-output, whose run-window (updated_at >= THIS runStartedAt)
  // would exclude the earlier issue and false-RED the skip.
  // concurrency:{scope:"fn",limit:1} (registration below) serializes the two
  // invocations, so the second's FRESH LIST read sees the first's create. Date
  // anchor is runStartedAt.slice(0,10) (replay-stable across the retries:1
  // memoization). Fail-OPEN: a read error → spawn (a duplicate paper-cut beats a
  // missed digest).
  const digestAlreadyExists = await step.run("dedup-digest-check", async () =>
    digestIssueExistsForDate({
      label: SENTRY_MONITOR_SLUG,
      titlePrefix: "[Scheduled] Weekly Roadmap Review -",
      date: runStartedAt.slice(0, 10),
      cronName: "cron-roadmap-review",
    }),
  );
  if (digestAlreadyExists) {
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({
        ok: true,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-roadmap-review",
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
      return mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS });
    },
  );

  // --- Step 2: setup ephemeral workspace (clone + settings + sentinel) ---
  // Track ephemeralRoot in handler-scope so teardown runs regardless of
  // downstream success/failure.
  let ephemeralRoot: string | null = null;
  let spawnCwd: string | null = null;
  try {
    const workspace = await step.run("setup-workspace", async () => {
      return setupEphemeralWorkspace({ installationToken, cronName: "cron-roadmap-review" });
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
      feature: "cron-roadmap-review",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-roadmap-review" },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-roadmap-review", logger });
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
    // #5728 — flag pattern. The body (claude-eval → verify-output) runs in an
    // inner try whose throw sets `threw`; the single terminal heartbeat is
    // posted (or skipped-for-retry) by finalizeOutputAwareHeartbeat below — NOT
    // from a second catch-site (which, under retries:1 memoization, would replay
    // a stale `ok` while posting a conflicting `error`). A throw before the
    // heartbeat previously propagated out → the heartbeat step never ran →
    // silent `missed`. spawnResult is hoisted so the silence-hole audit issue can
    // read it even when a later step threw.
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
            prompt: ROADMAP_REVIEW_PROMPT,
            maxTurnDurationMs: MAX_TURN_DURATION_MS,
            cronName: "cron-roadmap-review",
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
            feature: "cron-roadmap-review",
            op: "claude-eval-timeout",
            message: "claude-eval aborted by AbortController",
            extra: {
              fn: "cron-roadmap-review",
              durationMs: spawnResult.durationMs,
              maxMs: MAX_TURN_DURATION_MS,
            },
          },
        );
      }

      // --- Step 4: output-aware heartbeat. A clean exit that produced no
      //     `scheduled-roadmap-review` issue in the run window turns the monitor
      //     RED (and emits `scheduled-output-missing`) instead of false-green. ---
      heartbeatOk = await step.run("verify-output", async () =>
        resolveOutputAwareOk({
          spawnOk: spawnResult!.ok,
          label: SENTRY_MONITOR_SLUG,
          runStartedAt,
          cronName: "cron-roadmap-review",
          stderrTail: spawnResult!.stderrTail,
          exitCode: spawnResult!.exitCode,
          stdoutTail: spawnResult!.stdoutTail,
        }),
      );
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
        feature: "cron-roadmap-review",
        op: "handler-body-threw",
        message:
          "cron-roadmap-review body threw before the terminal heartbeat",
        extra: {
          fn: "cron-roadmap-review",
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
      cronName: "cron-roadmap-review",
      logger,
      onBeforeHeartbeat: heartbeatOk
        ? undefined
        : async () => {
            await step.run("ensure-audit-issue", async () => {
              try {
                await ensureScheduledAuditIssue({
                  label: SENTRY_MONITOR_SLUG,
                  titlePrefix: "[Scheduled] Weekly Roadmap Review -",
                  cronName: "cron-roadmap-review",
                  runStartedAt,
                  spawnResult: spawnResult ?? makeThrewSpawnResult("cron-roadmap-review"),
                  installationToken,
                });
              } catch (err) {
                reportSilentFallback(err, {
                  feature: "cron-roadmap-review",
                  op: "ensure-audit-issue-failed",
                  message:
                    "Handler-level fallback audit-issue create failed; run remains silent until watchdog threshold",
                  extra: { fn: "cron-roadmap-review", runStartedAt },
                });
              }
            });
          },
    });
    if (retry) {
      throw new Error(
        "cron-roadmap-review failed on a non-final attempt; retrying",
      );
    }

    return { ok: heartbeatOk };
  } finally {
    // Best-effort teardown (idempotent rm -rf with force:true). The
    // teardown helper already mirrors any failure to Sentry — wrapping
    // in .catch() here is a paranoid double-net to ensure a teardown
    // throw can never escape the finally and mask a real upstream error.
    await teardownEphemeralWorkspace(ephemeralRoot, "cron-roadmap-review").catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-roadmap-review",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-roadmap-review", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: scheduled cron (0 9 * * 1 UTC — weekly Monday 09:00) + manual
// operator event `cron/roadmap-review.manual-trigger`. account-scope
// concurrency "cron-platform" limits to 1 simultaneous cron-* invocation
// across the Hetzner node (PR-1 / PR-4 / PR-5 precedent).

export const cronRoadmapReview = inngest.createFunction(
  {
    id: "cron-roadmap-review",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 9 * * 1" },
    { event: "cron/roadmap-review.manual-trigger" },
  ],
  cronRoadmapReviewHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
