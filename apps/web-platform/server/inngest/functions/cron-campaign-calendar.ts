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
  Title: "[Scheduled] Campaign Calendar - {{RUN_DATE}} (heartbeat)"
  Label: scheduled-campaign-calendar
  Milestone: "Post-MVP / Later"

STEP 3 — Touch content-strategy freshness date:
In knowledge-base/marketing/content-strategy.md, update the frontmatter last_updated field to today's date. Do NOT touch last_reviewed — an automated cron write is not a human review, and bumping last_reviewed would silently reset the review clock this doc is measured against (ADR-094).

PERSISTENCE: Do NOT run git add, git commit, git push, or gh pr create/merge.
The platform commits and opens a PR for your changes automatically after the run.
Only changes under knowledge-base/marketing/campaign-calendar.md and knowledge-base/marketing/content-strategy.md are persisted — keep all edits inside those paths.
Creating the calendar issues above (STEP 2 or the STEP 2.5 heartbeat) is REQUIRED: the platform only persists your changes after it verifies the issue exists.
`;

// Persistence allowlist (#5111): verbatim from the prompt's former scoped
// staging list (the two files the calendar refresh and review-date bump edit).
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
const COMMIT_MESSAGE = "ci: update campaign calendar and content-strategy review";

// The ONE file the prompt mandates on every run (STEP 3: bump content-strategy's
// `last_updated`). Named separately from the allowlist because the liveness
// predicate must anchor on the MANDATED artifact, not on allowlist membership —
// see the predicate below for why those are not the same test.
export const CAMPAIGN_CALENDAR_MANDATED_ARTIFACT =
  "knowledge-base/marketing/content-strategy.md";

export const CAMPAIGN_CALENDAR_ALLOWED_PATHS = [
  "knowledge-base/marketing/campaign-calendar.md",
  CAMPAIGN_CALENDAR_MANDATED_ARTIFACT,
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
          cronName: "cron-campaign-calendar",
        }),
      )
    : false;
  if (digestAlreadyExists) {
    // Emitted on BOTH outcomes — the healthy dedup-and-return case AND the
    // issue-without-artifact recovery case. An emit on only one arm could not
    // distinguish them. Placement is load-bearing: OUTSIDE step.run and BEFORE
    // the gate below.
    emitCronDedupSkip({
      cron: "cron-campaign-calendar",
      date: runStartedAt.slice(0, 10),
      digest_committed: artifactCommitted ? 1 : 0,
    });
  }
  if (digestAlreadyExists && artifactCommitted) {
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
    // #5728 G1 — benign deploy-in-progress defer (ADR-078): rethrow bare, no heartbeat.
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
            prompt: injectRunDate(CAMPAIGN_CALENDAR_PROMPT, runStartedAt),
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
        const commitResult = await step.run("safe-commit-pr", async () =>
          safeCommitAndPr({
            spawnCwd: spawnCwd!,
            installationToken,
            cronName: "cron-campaign-calendar",
            commitMessage: COMMIT_MESSAGE,
            allowedPaths: CAMPAIGN_CALENDAR_ALLOWED_PATHS,
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
          if (commitResult.paths?.includes(CAMPAIGN_CALENDAR_MANDATED_ARTIFACT)) {
            // THE POSITIVE: the file STEP 3 mandates on EVERY run.
            //
            // Anchored on that one file, NOT on allowlist membership. The
            // membership form is vacuous in production: safeCommitAndPr already
            // filters staged entries through
            // `allowedPaths.some((p) => e.path.startsWith(p))`
            // (_cron-safe-commit.ts, anchor `allowedPaths.some`), so every member
            // of `paths` is allowlisted by construction and the test would reduce
            // to `paths.length > 0` — the exact vacuity R12 identified for Class
            // B, but reported under Class A's `digest-committed`, which claims the
            // artifact was PROVED. A run that refreshes only campaign-calendar.md
            // and never touches content-strategy.md would have posted GREEN.
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
          cron: "cron-campaign-calendar",
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
          cron: "cron-campaign-calendar",
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
          cron: "cron-campaign-calendar",
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
        feature: "cron-campaign-calendar",
        op: "handler-body-threw",
        message: "cron-campaign-calendar body threw before the terminal heartbeat",
        extra: { fn: "cron-campaign-calendar", attempt: attempt ?? 0, producedOutput: heartbeatOk },
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
    // Reachability note for the `threw && !heartbeatOk → retry` hazard:
    // livenessOk is falsified only at the tail of the try with nothing
    // throwing after it, and a throw out of safe-commit-pr leaves it true by
    // construction — and `retryEligible: false` makes the point moot anyway.
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
      cronName: "cron-campaign-calendar",
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
