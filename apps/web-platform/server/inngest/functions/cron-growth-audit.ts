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
  deferIfTier2Cron,
  digestCommittedOnDefaultBranch,
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
import { AUDIT_MODEL } from "@/server/inngest/model-tiers";

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
// NOTE: claude-opus-5 model for deep multi-step growth audit.
//
// #4993 — headless /soleur:* skill resolution (fleet fix mirroring #4987 /
// PR #4989): `--plugin-dir plugins/soleur` registers the plugin (clone's tracked tree — #5091) under
// `--print` (a bare plugins/ dir is NOT auto-discovered in headless mode), and
// `Skill` (+`Task` for subagent fan-out) in --allowedTools gates skill invocation.
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  AUDIT_MODEL,
  "--max-turns",
  "70",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Skill,Task",
  "--plugin-dir",
  "plugins/soleur",
  "--",
];

// Verbatim prompt extracted from
// .github/workflows/scheduled-growth-audit.yml. #5111 removed the
// prompt-level commit block (the platform persists handler-side via
// safeCommitAndPr — the #5091 consolidation pattern).
const GROWTH_AUDIT_PROMPT = `IMPORTANT: This is an automated CI workflow. Do NOT push directly to main.

MILESTONE RULE: Every gh issue create command must include --milestone. Use --milestone "Post-MVP / Later" for operational issues. For feature issues, read knowledge-base/product/roadmap.md.

Run a full growth audit of https://soleur.ai.

Step 1: Content Audit
Run /soleur:growth auditing on this repository. Save the report to knowledge-base/marketing/audits/soleur-ai/{{RUN_DATE}}-content-audit.md

Step 2: AEO Audit
Run /soleur:growth auditing --aeo on this repository. Save the report to knowledge-base/marketing/audits/soleur-ai/{{RUN_DATE}}-aeo-audit.md

Step 3: Technical SEO Audit
Run /soleur:seo-aeo on this repository. Save the report to knowledge-base/marketing/audits/soleur-ai/{{RUN_DATE}}-seo-audit.md. If the audit fails, write a stub report and continue.

Step 4: Content Plan
Based on the three audit reports, create a prioritized content plan. Save to knowledge-base/marketing/audits/soleur-ai/{{RUN_DATE}}-content-plan.md

Step 5: GitHub Issue
Create issue "[Scheduled] Growth Audit - {{RUN_DATE}}" with label "scheduled-growth-audit" summarizing top findings, AEO score/grade, SEO score/grade, and content plan priorities.

Step 5.5: Create tracking issues for each P0/P1/P2 finding (with dedup).

Step 5.6: Assign milestones and update roadmap.

PERSISTENCE: Do NOT run git add, git commit, git push, or gh pr create/merge.
The platform commits and opens a PR for your changes automatically after the run.
Only changes under knowledge-base/marketing/audits/soleur-ai/ and knowledge-base/product/roadmap.md are persisted — keep all edits inside those paths.
Creating the audit issue above is REQUIRED: the platform only persists your changes after it verifies the issue exists.
`;

// Persistence allowlist (#5111): verbatim from the prompt's former scoped
// staging list (audit reports directory + the roadmap milestone updates).
// #6750 (ADR-126 amendment) — this producer's class, single-sourced against
// scripts/cron-artifact-age.sh's `class` column by a parity test so the shell
// detector and the handler's liveness table cannot drift apart silently.
//
// Read by cron-safe-commit-parity.test.ts as SOURCE TEXT rather than imported:
// importing a handler pulls its whole static graph (server/inngest/client.ts)
// into the test, which throws `INNGEST_SIGNING_KEY missing at startup` at module
// eval under CI's env. Exported so the declaration is an explicit part of the
// module contract rather than an unread local.
export const PRODUCER_CLASS = "A";

// Single-sourced so the freshness probe below cannot drift from the message
// safeCommitAndPr actually writes — and so both agree with the detector's
// anchor_regex column.
const COMMIT_MESSAGE = "docs: weekly growth audit";

// The dated-report directory. Named so the liveness predicate and the dedup
// existence probe share one source with the persistence allowlist below.
export const GROWTH_AUDIT_REPORT_DIR =
  "knowledge-base/marketing/audits/soleur-ai/";

export const GROWTH_AUDIT_ALLOWED_PATHS = [
  GROWTH_AUDIT_REPORT_DIR,
  "knowledge-base/product/roadmap.md",
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

export async function cronGrowthAuditHandler({
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
      cronName: "cron-growth-audit",
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
  // If a real `[Scheduled] Growth Audit - <date>` digest already exists for
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
      titlePrefix: "[Scheduled] Growth Audit -",
      date: runStartedAt.slice(0, 10),
      cronName: "cron-growth-audit",
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
        // EXISTENCE probe, sound ONLY because this path is DATE-NAMED: today's
        // report cannot exist unless today's run wrote it. Never point this at a
        // directory or a permanent file — a probe whose path always exists is a
        // guard that can never fail.
        digestCommittedOnDefaultBranch({
          path: `${GROWTH_AUDIT_REPORT_DIR}${runStartedAt.slice(0, 10)}-content-audit.md`,
          cronName: "cron-growth-audit",
        }),
      )
    : false;
  if (digestAlreadyExists) {
    // Emitted on BOTH outcomes — the healthy dedup-and-return case AND the
    // issue-without-artifact recovery case. An emit on only one arm could not
    // distinguish them. Placement is load-bearing: OUTSIDE step.run and BEFORE
    // the gate below.
    emitCronDedupSkip({
      cron: "cron-growth-audit",
      date: runStartedAt.slice(0, 10),
      digest_committed: artifactCommitted ? 1 : 0,
    });
  }
  if (digestAlreadyExists && artifactCommitted) {
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({
        ok: true,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-growth-audit",
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
      return setupEphemeralWorkspace({ installationToken, cronName: "cron-growth-audit" });
    });
    ephemeralRoot = workspace.ephemeralRoot;
    spawnCwd = workspace.spawnCwd;
  } catch (err) {
    // #5728 G1 — benign deploy-in-progress defer (ADR-078): rethrow bare, no heartbeat.
    if (err instanceof DeployInProgressError) throw err;
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
      // --- Step 3: claude-eval (70-min AbortController) ---
      spawnResult = await step.run(
        "claude-eval",
        async (): Promise<SpawnResult> => {
          return spawnClaudeEval({
            spawnCwd: spawnCwd!,
            installationToken,
            flags: CLAUDE_CODE_FLAGS,
            prompt: injectRunDate(GROWTH_AUDIT_PROMPT, runStartedAt),
            maxTurnDurationMs: MAX_TURN_DURATION_MS,
            cronName: "cron-growth-audit",
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
      heartbeatOk = await step.run("verify-output", async () =>
        resolveOutputAwareOk({
          spawnOk: spawnResult!.ok,
          label: SENTRY_MONITOR_SLUG,
          runStartedAt,
          cronName: "cron-growth-audit",
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
        const commitResult = await step.run("safe-commit-pr", async () =>
          safeCommitAndPr({
            spawnCwd: spawnCwd!,
            installationToken,
            cronName: "cron-growth-audit",
            commitMessage: COMMIT_MESSAGE,
            allowedPaths: GROWTH_AUDIT_ALLOWED_PATHS,
            runStartedAt,
            scheduledIssueLabel: SENTRY_MONITOR_SLUG,
            logger,
          }),
        );

        // The liveness table (Class A — deterministic producer). `livenessOk` is
        // FALSE until proven otherwise, so only the two arms below can turn the
        // run GREEN; "no-changes", "failed", committed-without-the-artifact, and
        // every throw that never reaches here all fall through still RED.
        let livenessReason: CronDigestLivenessMarker["reason"] =
          "persistence-not-committed";
        if (commitResult.status === "committed") {
          if (commitResult.paths?.some((p) => p.startsWith(`${GROWTH_AUDIT_REPORT_DIR}${runStartedAt.slice(0, 10)}-`))) {
            // THE POSITIVE: today's dated audit reports (Steps 1-4 write four of them unconditionally).
            // `.some` is MEMBERSHIP, not position — the agent may land other
            // allowlisted files beside the artifact, in any order.
            livenessOk = true;
            livenessReason = "digest-committed";
          } else if (commitResult.paths === undefined) {
            // NOT DETERMINED, never "nothing committed". Only the replay-resume
            // branch has a legitimate reason to leave it undetermined — it is the
            // one path that skips the allowlist scan. Any OTHER undetermined shape
            // means the result contract drifted, and voting GREEN on an unknown is
            // the failure this closes, so it stays RED.
            livenessOk = commitResult.resumed === true;
            livenessReason = commitResult.resumed
              ? "undetermined-replay-resume"
              : "undetermined-contract-drift";
          } else {
            // Committed something, but not the consumed artifact → stays RED.
            // This is the flagship new RED, and it is UNDIAGNOSABLE without the
            // marker below: safeCommitAndPr SUCCEEDED, so no "PR withheld" comment
            // fires and SOLEUR_CRON_PERSIST_RESULT already reported
            // status:"committed", which reads healthy.
            livenessReason = "digest-absent-from-commit";
          }
        }
        // The VERDICT plus the arm that decided it. Without this the RED arms are
        // indistinguishable in Better Stack.
        emitCronDigestLiveness({
          cron: "cron-growth-audit",
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
          cron: "cron-growth-audit",
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
          cron: "cron-growth-audit",
          run_id: runId ?? "unknown",
          attempt: attempt ?? 0,
          ok: 0,
          reason: "persistence-skipped",
        });
      }
    } catch (err) {
      if (err instanceof DeployInProgressError) throw err;
      threw = true;
      const e = err as Error;
      const redactedMsg = redactToken(e.message ?? "", installationToken);
      const redacted = new Error(redactedMsg);
      redacted.name = e.name;
      reportSilentFallback(redacted, {
        feature: "cron-growth-audit",
        op: "handler-body-threw",
        message: "cron-growth-audit body threw before the terminal heartbeat",
        extra: { fn: "cron-growth-audit", attempt: attempt ?? 0, producedOutput: heartbeatOk },
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
      cronName: "cron-growth-audit",
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
                  titlePrefix: "[Scheduled] Growth Audit -",
                  cronName: "cron-growth-audit",
                  runStartedAt,
                  spawnResult: spawnResult ?? makeThrewSpawnResult("cron-growth-audit"),
                  installationToken,
                });
              } catch (err) {
                reportSilentFallback(err, {
                  feature: "cron-growth-audit",
                  op: "ensure-audit-issue-failed",
                  message:
                    "Handler-level fallback audit-issue create failed; run remains silent until watchdog threshold",
                  extra: { fn: "cron-growth-audit", runStartedAt },
                });
              }
            });
          },
    });
    if (retry) {
      throw new Error(
        "cron-growth-audit failed on a non-final attempt; retrying",
      );
    }

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
