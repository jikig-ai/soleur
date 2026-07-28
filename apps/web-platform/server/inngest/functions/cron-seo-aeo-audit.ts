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
//   - --model claude-sonnet-5 (same).
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
  artifactCommittedSince,
  digestIssueExistsForDate,
  injectRunDate,
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
import {
  emitCronDedupSkip,
  emitCronDigestLiveness,
  emitCronPersistSkipped,
  type CronDigestLivenessMarker,
} from "@/server/cron-liveness-marker";
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
//   --model claude-sonnet-5
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

After the audit and fix is complete, create a GitHub issue titled "[Scheduled] SEO/AEO Audit - {{RUN_DATE}}" with the label "scheduled-seo-aeo-audit" summarizing what issues were found and what fixes were applied.

PERSISTENCE: Do NOT run git add, git commit, git push, or gh pr create/merge.
The platform commits and opens a PR for your changes automatically after the run.
Only changes under plugins/soleur/docs/ are persisted — keep all edits inside that path.
Creating the audit issue above is REQUIRED: the platform only persists your changes after it verifies the issue exists.
`;

// Persistence allowlist (#5091): the audit edits the Eleventy docs site under
// the plugin tree — committable from the clone now that the substrate no
// longer symlink-shadows plugins/soleur.
// #6750 (ADR-126 amendment) — this producer's class, single-sourced against
// scripts/cron-artifact-age.sh's `class` column by a parity test so the shell
// detector and the handler's liveness table cannot drift apart silently.
//
// Read by cron-safe-commit-parity.test.ts as SOURCE TEXT rather than imported:
// importing a handler pulls its whole static graph (server/inngest/client.ts)
// into the test, which throws `INNGEST_SIGNING_KEY missing at startup` at module
// eval under CI's env. Exported so the declaration is an explicit part of the
// module contract rather than an unread local.
export const PRODUCER_CLASS = "B";

// Single-sourced so the freshness probe below cannot drift from the message
// safeCommitAndPr actually writes — and so both agree with the detector's
// anchor_regex column.
const COMMIT_MESSAGE = "fix(seo): weekly SEO/AEO audit fixes";

export const SEO_AEO_ALLOWED_PATHS = ["plugins/soleur/docs/"] as const;

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
  runId,
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

  // #5786 — producer-side date-dedup (extends the #5751 community-monitor fix).
  // If a real `[Scheduled] SEO/AEO Audit - <date>` digest already exists for
  // today, skip the eval and post a healthy OK heartbeat — do NOT fall through
  // to verify-output, whose run-window (updated_at >= THIS runStartedAt) would
  // exclude the earlier issue and false-RED the skip.
  // concurrency:{scope:"fn",limit:1} (registration below) serializes the two
  // invocations, so the second's FRESH LIST read sees the first's create. Date
  // anchor is runStartedAt.slice(0,10) (replay-stable). Fail-OPEN: a read error
  // → spawn (a duplicate paper-cut beats a missed digest).
  const digestAlreadyExists = await step.run("dedup-digest-check", async () =>
    digestIssueExistsForDate({
      label: SENTRY_MONITOR_SLUG,
      titlePrefix: "[Scheduled] SEO/AEO Audit -",
      date: runStartedAt.slice(0, 10),
      cronName: "cron-seo-aeo-audit",
    }),
  );
  // #6750 (ADR-126 amendment), P0 — the dedup early-return used to post GREEN and
  // return on ISSUE-PRESENCE ALONE, which is a GREEN-with-no-artifact path by
  // construction. Observed shape: run 1 files a genuine issue but fails to commit;
  // run 2 dedups on that issue and posts GREEN with nothing landed — the exact
  // 2026-07-14 -> 07-19 state. It SURVIVES the captured-return and livenessOk
  // fixes below unless closed HERE, because this branch returns BEFORE
  // finalizeOutputAwareHeartbeat ever runs. So the short-circuit now requires BOTH
  // the issue AND the artifact on the default branch.
  const artifactCommitted = digestAlreadyExists
    ? await step.run("dedup-digest-committed-check", async () =>
        // FRESHNESS probe, not existence: this producer overwrites a permanent
        // file/directory, so a contents read would return 200 forever and the
        // "hardened" guard could never fail — reproducing the always-green defect
        // inside its own fix. Asks instead whether THIS cron's commit landed on
        // main today, the same signal scripts/cron-artifact-age.sh measures.
        artifactCommittedSince({
          // Date-bound: this is the PR TITLE safeCommitAndPr builds, which the
          // squash merge carries into the commit subject. Anchoring on the
          // message alone would match a PREVIOUS day's artifact that merged
          // after midnight, and dedup GREEN on it.
          anchorPrefix: `${COMMIT_MESSAGE} ${runStartedAt.slice(0, 10)}`,
          sinceIso: `${runStartedAt.slice(0, 10)}T00:00:00.000Z`,
          cronName: "cron-seo-aeo-audit",
        }),
      )
    : false;
  if (digestAlreadyExists) {
    // Emitted on BOTH outcomes — the healthy dedup-and-return case AND the
    // issue-without-artifact recovery case. An emit on only one arm could not
    // distinguish them. Placement is load-bearing: OUTSIDE step.run and BEFORE
    // the gate below.
    emitCronDedupSkip({
      cron: "cron-seo-aeo-audit",
      date: runStartedAt.slice(0, 10),
      digest_committed: artifactCommitted ? 1 : 0,
    });
  }
  if (digestAlreadyExists && artifactCommitted) {
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({
        ok: true,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-seo-aeo-audit",
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
      return setupEphemeralWorkspace({ installationToken, cronName: "cron-seo-aeo-audit" });
    });
    ephemeralRoot = workspace.ephemeralRoot;
    spawnCwd = workspace.spawnCwd;
  } catch (err) {
    // #5728 G1 — benign deploy-in-progress defer (ADR-078): rethrow bare, no heartbeat.
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
  // because rm {recursive:true, force:true} is idempotent.
  //
  // #6750 — the previous version of this comment claimed a replay "re-creates a
  // fresh ephemeralRoot from setup-workspace's memoization (or the existsSync
  // guard at the top of spawnClaudeEval rebuilds it)". BOTH halves were false:
  // memoization is precisely why setup-workspace does NOT re-run, and the
  // existsSync guard (_cron-claude-eval-substrate.ts, anchor `no longer exists`)
  // THROWS rather than rebuilding. A replay after teardown cannot recover, which
  // is why every finalizeOutputAwareHeartbeat caller now passes
  // `retryEligible: false`.
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
    // #6750 — the LIVENESS signal, split from heartbeatOk by ADDITION.
    // heartbeatOk is asserted as LITERAL SOURCE TEXT by
    // cron-safe-commit-parity.test.ts across all 8 cohort files, so it keeps
    // both its name and its role as the persistence gate; renaming it would
    // break a cohort invariant to fix a colour bug.
    //
    // heartbeatOk answers "did a labelled issue land". livenessOk answers "did
    // the artifact the operator actually consumes get COMMITTED".
    //
    // Initialised FALSE and set true ONLY by an observed positive. A signal that
    // votes GREEN on an UNOBSERVED artifact is precisely the defect ADR-126
    // exists to close, so fail-closed is the only defensible default. The retry
    // consequence is handled by `retryEligible: false` at the finalize call
    // rather than by weakening the signal.
    let livenessOk = false;
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
            prompt: injectRunDate(SEO_AEO_AUDIT_PROMPT, runStartedAt),
            maxTurnDurationMs: MAX_TURN_DURATION_MS,
            cronName: "cron-seo-aeo-audit",
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
        const commitResult = await step.run("safe-commit-pr", async () =>
          safeCommitAndPr({
            spawnCwd: spawnCwd!,
            installationToken,
            cronName: "cron-seo-aeo-audit",
            commitMessage: COMMIT_MESSAGE,
            allowedPaths: SEO_AEO_ALLOWED_PATHS,
            runStartedAt,
            scheduledIssueLabel: SENTRY_MONITOR_SLUG,
            logger,
          }),
        );

        // The liveness table (Class B — change-conditional producer). A run that
        // legitimately produces no diff is HEALTHY for this producer, so
        // "no-changes" is GREEN here where it is RED for Class A. The prompt's own
        // no-artifact stop paths are why: false-REDing them would page the operator
        // for a correct run.
        let livenessReason: CronDigestLivenessMarker["reason"] =
          "persistence-not-committed";
        if (commitResult.status === "committed") {
          if (commitResult.paths === undefined) {
            // NOT DETERMINED, never "nothing committed" — see the Class A note.
            livenessOk = commitResult.resumed === true;
            livenessReason = commitResult.resumed
              ? "undetermined-replay-resume"
              : "undetermined-contract-drift";
          } else if (
            // Scope, stated honestly. safeCommitAndPr ALREADY filters staged entries
            // through `allowedPaths.some((p) => e.path.startsWith(p))`
            // (_cron-safe-commit.ts, anchor `allowedPaths.some`), so in production
            // every member of `paths` is under the allowlist and this predicate
            // reduces to `paths.length > 0`. It is kept in full deliberately, as a
            // CONSUMER-SIDE restatement of that contract: if safeCommitAndPr ever
            // returns a path outside the allowlist, this votes RED instead of GREEN.
            //
            // What it is NOT is independent evidence that the consumed artifact
            // landed. A change-conditional producer cannot supply that evidence by
            // construction — which is precisely why Class B's ceiling is the
            // independent-vantage detector (scripts/cron-artifact-age.sh) and why its
            // silent window is written down as a named residual in the ADR-126
            // amendment rather than papered over here.
            //
            // Stronger than first documented, and stated plainly: this predicate
            // is UNREACHABLE-FALSE in production, not merely reducible. On top of
            // the allowlist pre-filter, safeCommitAndPr returns `no-changes` when
            // `matched.length === 0` (anchor `no committable changes inside
            // allowedPaths`), so a defined `paths` is also always non-empty. Both
            // conjuncts are therefore constant-true against the real producer.
            // It is retained as a consumer-side contract restatement — if
            // safeCommitAndPr ever returns an empty or out-of-allowlist `paths`,
            // this votes RED rather than GREEN — and it is falsifiable only
            // against the unit tests, which inject shapes the real producer
            // cannot emit. Class B's genuine liveness ceiling is the detector.
            commitResult.paths.length > 0 &&
            commitResult.paths.some((p) => SEO_AEO_ALLOWED_PATHS.some((a) => p.startsWith(a)))
          ) {
            livenessOk = true;
            livenessReason = "allowlisted-commit-no-artifact";
          } else {
            // Committed, but nothing under the allowlist (or nothing at all).
            livenessReason = "digest-absent-from-commit";
          }
        } else if (commitResult.status === "no-changes") {
          // Class B ONLY. Healthy, but deliberately NOT reported as
          // "digest-committed": "this producer had nothing to do" is not evidence
          // of liveness, and conflating the two would rebuild the blind spot.
          // Staleness for this arm is caught by the independent-vantage detector
          // (scripts/cron-artifact-age.sh), whose window for this cron is recorded
          // as a named residual in the ADR-126 amendment.
          livenessOk = true;
          livenessReason = "no-changes-change-conditional";
        }
        // The VERDICT plus the arm that decided it. Without this the RED arms are
        // indistinguishable in Better Stack.
        emitCronDigestLiveness({
          cron: "cron-seo-aeo-audit",
          run_id: runId ?? "unknown",
          attempt: attempt ?? 0,
          ok: livenessOk ? 1 : 0,
          reason: livenessReason,
        });
      } else {
        // This gate had NO else, so a RED or timed-out run skipped persistence
        // leaving no trace on any operator-reachable surface. abortedByTimeout is
        // checked first because a timed-out run is usually also red, and the
        // timeout is the more specific cause.
        emitCronPersistSkipped({
          cron: "cron-seo-aeo-audit",
          reason: spawnResult.abortedByTimeout ? "timeout" : "red",
        });
        // Nothing was persisted. The case that matters is a timed-out run whose
        // ISSUE landed, which was GREEN-with-no-artifact before #6750.
        //
        // This assignment is PROVABLY REDUNDANT and is kept only as an explicit
        // statement of intent: livenessOk is initialised false and is set true
        // ONLY inside the `if (heartbeatOk && !abortedByTimeout)` branch, which
        // is mutually exclusive with this else. A mutation battery confirms it —
        // deleting this line does not turn any test red. It is NOT a guard, and
        // it must not be read as one; the falsification that actually carries
        // this arm is the initialiser.
        livenessOk = false;
        emitCronDigestLiveness({
          cron: "cron-seo-aeo-audit",
          run_id: runId ?? "unknown",
          attempt: attempt ?? 0,
          ok: 0,
          reason: "persistence-skipped",
        });
      }
    } catch (err) {
      // #5728 G1 — a deploy-in-progress defer is benign (ADR-078/#5686): rethrow
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

    // #6750 — the liveness signal APPLIED. Placed HERE, after the inner
    // try/catch closes, for two reasons:
    // (1) AFTER persistence: heartbeatOk also gates safeCommitAndPr, so
    //     lowering it any earlier would discard the very artifact whose
    //     absence is being reported.
    // (2) OUTSIDE the try: as the try's last statement it would be skipped
    //     whenever a trailing step threw — exactly the compound-failure run.
    //
    // Reachability note for the `threw && !heartbeatOk → retry` hazard: it IS
    // reachable. A throw out of safe-commit-pr skips the liveness table
    // entirely, so livenessOk keeps its `false` initialiser and this line
    // lowers heartbeatOk on a run that also threw. (Scenario 10 exercises
    // exactly that and asserts {ok:false}.) What makes it safe is NOT
    // unreachability — it is `retryEligible: false` at the finalize call, which
    // turns that combination into one honest terminal RED instead of a replay.
    if (!livenessOk) heartbeatOk = false;

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
      // #6750 (ADR-126 amendment) — a replay CANNOT recover a failure inside the
      // guarded body: `setup-workspace` is memoized inside step.run, so an Inngest
      // replay reads back an ephemeralRoot the `finally` below already deleted, and
      // the re-spawned agent burns real Anthropic spend against a path that no
      // longer exists. One honest terminal RED beats a retry that cannot succeed.
      // Scoped precisely: throws BEFORE the try (token mint, setup-workspace
      // itself) are unaffected and still retry into a fresh workspace, and
      // DeployInProgressError still rethrows bare.
      //
      // This is a PREREQUISITE for consuming safeCommitAndPr's return value, not a
      // peer of it: that consumption lowers heartbeatOk, which on a run that also
      // threw would otherwise flip `failed` true and buy exactly the useless replay
      // above — one that additionally comments a misleading "PR withheld: safe-commit
      // failed at stage `workspace-lost`" onto the operator's own issue.
      retryEligible: false,
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
                  spawnResult: spawnResult ?? makeThrewSpawnResult("cron-seo-aeo-audit"),
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
