// TR9 Phase 2 — Migrated from the GHA scheduled-content-generator workflow
// (deleted in the same PR per TR9 I-13 hygiene). claude-code-spawn pattern;
// structural template is cron-roadmap-review.ts.
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — claude binary spawned INSIDE step.run (Inngest replay memoization).
//   I2 — Operator ANTHROPIC_API_KEY only; never founder BYOK. Enforced at
//        build time by test/server/cron-no-byok-lease-sweep.test.ts.
//   I3 — AbortSignal aborts at MAX_TURN_DURATION_MS (55 min). Manual
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

const SENTRY_MONITOR_SLUG = "scheduled-content-generator";

// Token-lifetime floor passed to generateInstallationToken: claude-eval's
// 55-min wall-clock budget + 10-min slack for setup + teardown + retry.
const TOKEN_MIN_LIFETIME_MS = 55 * 60 * 1000 + 10 * 60 * 1000;

// 55 min wall-clock budget (from 60 min GHA timeout minus headroom).
// Exported for test parity.
export const MAX_TURN_DURATION_MS = 55 * 60 * 1000;
export { KILL_ESCALATION_MS } from "./_cron-claude-eval-substrate";

// claude-code spawn argv. `--` is load-bearing per #4017 bug 8/8 (variadic
// --allowedTools consumes the prompt as a tool name without the end-of-
// options marker). The prompt is the SOLE positional argument after `--`.
//
// #4987 — content-generator's prompt invokes plugin skills
// (/soleur:content-writer, social-distribute, growth). This is the FIRST
// producer fixed for headless plugin-skill resolution; sibling producers that
// invoke /soleur:* skills in their prompts (cron-competitive-analysis,
// cron-legal-audit, cron-growth-audit, …) almost certainly share the same
// latent gap and are tracked for a fleet audit in #4993. Two flags make skill
// invocation work in a headless `claude --print` run:
//   - `--allowedTools` is an explicit allowlist, so `Skill` (invoke a plugin
//     skill) and `Task` (content-writer's fact-checker subagent; the `Task`
//     precedent is cron-competitive-analysis / cron-legal-audit, which already
//     allow it) must be listed or the skill cannot run at all. --max-turns
//     stays 50.
//   - `--plugin-dir plugins/soleur` REGISTERS the plugin. Per
//     `claude --plugin-dir <path>` ("Load a plugin from a directory or .zip"),
//     loading a directory-based plugin in a headless `--print` run requires the
//     flag explicitly — a bare plugins/ dir is NOT auto-discovered
//     (the interactive marketplace/enabledPlugins trust flow does not run under
//     --print). The path is the clone's own tracked tree at
//     <spawnCwd>/plugins/soleur (#5091) and MUST precede the `--` marker.
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  EXECUTION_MODEL,
  "--max-turns",
  "50",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,Skill,Task",
  "--plugin-dir",
  "plugins/soleur",
  "--",
];

// Verbatim prompt extracted from
// .github/workflows/scheduled-content-generator.yml.
const CONTENT_GENERATOR_PROMPT = `IMPORTANT: This is an automated CI workflow. Do NOT push directly to main.

MILESTONE RULE: Every gh issue create command must include --milestone "Post-MVP / Later".

STEP 1 — Select topic from queue:
Read knowledge-base/marketing/seo-refresh-queue.md and identify the highest-priority item without a "generated_date" annotation. Priority order: Priority 1 first, then Priority 2 pillar, then Priority 2 comparison.

If ALL items have a generated_date:
  STEP 1b — Run /soleur:growth plan "Company-as-a-Service content for solo founders building with AI"
  Extract the single highest-priority P1 content suggestion.
  If no usable topic, create issue "[Scheduled] Content Generator - {{RUN_DATE}}" with label "scheduled-content-generator" and stop.

STEP 2 — Generate article:
Run /soleur:content-writer <topic> --headless
If content-writer aborts due to FAIL citations, create issue and stop.

STEP 3 — Generate distribution content:
Run /soleur:social-distribute <article-path> --headless
Ensure frontmatter has: publish_date: <today>, status: scheduled, channels: discord, x, bluesky, linkedin-company
(NOTE: use your self-computed <today> for publish_date here — only the issue TITLE date is pre-filled by the platform.)

STEP 4 — Validation runs in CI (do NOT build locally):
This ephemeral workspace is a shallow clone with no node_modules, so a local "npx @11ty/eleventy" build cannot run here. Validation happens on the PR the platform opens from your changes after the run: CI runs "npx @11ty/eleventy" and "scripts/validate-blog-links.sh", and the PR only auto-merges once those required checks pass. Your job is to make CI green — ensure the article's Eleventy frontmatter is valid and every internal link resolves. Do NOT attempt a local build or run the validation scripts yourself.

STEP 5 — Record topic in queue:
Update seo-refresh-queue.md with generated_date annotation.

STEP 6 — Create audit issue:
"[Scheduled] Content Generator - {{RUN_DATE}}" with label "scheduled-content-generator"

PERSISTENCE: Do NOT run git add, git commit, git push, or gh pr create/merge.
The platform commits and opens a PR for your changes automatically after the run.
Only changes under knowledge-base/marketing/ and plugins/soleur/docs/blog/ are persisted — keep all edits inside those paths.
Creating the audit issue in STEP 6 is REQUIRED: the platform only persists your changes after it verifies the issue exists.
`;

// Persistence allowlist (#5091): the article + distribution content + queue
// annotation land under knowledge-base/marketing/; content-writer's default
// article path is plugins/soleur/docs/blog/ (committable from the clone now
// that the substrate no longer symlink-shadows plugins/soleur).
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
const COMMIT_MESSAGE = "feat(content): auto-generate article";
const COMMIT_MESSAGE_ANCHOR = new RegExp(
  "^" + COMMIT_MESSAGE.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
);

export const CONTENT_GENERATOR_ALLOWED_PATHS = [
  "knowledge-base/marketing/",
  "plugins/soleur/docs/blog/",
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
// Silence-hole fallback guard (#4960)
// =============================================================================
//
// The prompt's STEP 1b/2/6 "create issue and stop" guards are the ONLY
// producers of the `scheduled-content-generator` audit issue. Any termination
// that bypasses the prompt — a mid-eval crash, an upstream Anthropic API 500
// that kills `claude --print` (the #4960 case, confirmed via Sentry event
// 141195ed…: exitCode 1, ~6.1 min, "API Error: 500"), or a max-turns kill —
// produces NO issue, so the run is silent and the cron-cloud-task-heartbeat
// watchdog only notices ~9 days later (maxGapDays threshold).
//
// This handler-level guard fires AFTER the output-aware check determines no
// `scheduled-content-generator` issue exists in the run window, and self-reports
// a FAILED audit issue so the run is never silent. It lives above the prompt so
// it survives an eval kill that bypasses every prompt step. ~8 sibling crons
// already create issues from the handler (cron-skill-freshness, cron-oauth-probe,
// cron-strategy-review, …); this is the first always-create producer to use the
// primitive as a *fallback* gated on the output-aware result.
//
// `octokit` is injectable purely so unit tests can drive the read/create shape
// without the App-JWT mint path; production callers pass the already-minted
// installation token (issues:write — the same token the spawn's `gh issue
// create` uses; `hr-github-app-auth-not-pat`).

// =============================================================================
// Handler
// =============================================================================

export async function cronContentGeneratorHandler({
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
      cronName: "cron-content-generator",
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
  // If a real `[Scheduled] Content Generator - <date>` digest already exists for
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
      titlePrefix: "[Scheduled] Content Generator -",
      date: runStartedAt.slice(0, 10),
      cronName: "cron-content-generator",
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
          anchorRegex: COMMIT_MESSAGE_ANCHOR,
          sinceIso: `${runStartedAt.slice(0, 10)}T00:00:00.000Z`,
          cronName: "cron-content-generator",
        }),
      )
    : false;
  if (digestAlreadyExists) {
    // Emitted on BOTH outcomes — the healthy dedup-and-return case AND the
    // issue-without-artifact recovery case. An emit on only one arm could not
    // distinguish them. Placement is load-bearing: OUTSIDE step.run and BEFORE
    // the gate below.
    emitCronDedupSkip({
      cron: "cron-content-generator",
      date: runStartedAt.slice(0, 10),
      digest_committed: artifactCommitted ? 1 : 0,
    });
  }
  if (digestAlreadyExists && artifactCommitted) {
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({
        ok: true,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-content-generator",
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
      return setupEphemeralWorkspace({ installationToken, cronName: "cron-content-generator" });
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
      feature: "cron-content-generator",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-content-generator" },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-content-generator", logger });
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
    // out → the heartbeat step never ran → silent `missed`. spawnResult is
    // hoisted so the silence-hole audit issue can read it even when a later step
    // threw.
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
      // --- Step 3: claude-eval (55-min AbortController) ---
      spawnResult = await step.run(
        "claude-eval",
        async (): Promise<SpawnResult> => {
          return spawnClaudeEval({
            spawnCwd: spawnCwd!,
            installationToken,
            flags: CLAUDE_CODE_FLAGS,
            prompt: injectRunDate(CONTENT_GENERATOR_PROMPT, runStartedAt),
            maxTurnDurationMs: MAX_TURN_DURATION_MS,
            cronName: "cron-content-generator",
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
            feature: "cron-content-generator",
            op: "claude-eval-timeout",
            message: "claude-eval aborted by AbortController",
            extra: {
              fn: "cron-content-generator",
              durationMs: spawnResult.durationMs,
              maxMs: MAX_TURN_DURATION_MS,
            },
          },
        );
      }

      // --- Step 4: output-aware heartbeat. The prompt's STEP 6 always
      //     creates a `scheduled-content-generator` audit issue (even on the
      //     no-topic / FAIL-citation early exits); a clean run that produced none
      //     turns the monitor RED instead of false-green. ---
      heartbeatOk = await step.run("verify-output", async () =>
        resolveOutputAwareOk({
          spawnOk: spawnResult!.ok,
          label: SENTRY_MONITOR_SLUG,
          runStartedAt,
          cronName: "cron-content-generator",
          stderrTail: spawnResult!.stderrTail,
          exitCode: spawnResult!.exitCode,
          stdoutTail: spawnResult!.stdoutTail,
        }),
      );
      // --- Step 4.5: deterministic persistence (#5091). Gated on the
      //     issue-verified output (NOT the spawn exit code) and on
      //     !abortedByTimeout — see cron-seo-aeo-audit.ts for the full
      //     rationale. Guard aborts / persistence failures self-report inside
      //     the helper (Sentry + issue comment).
      if (heartbeatOk && !spawnResult.abortedByTimeout) {
        const commitResult = await step.run("safe-commit-pr", async () =>
          safeCommitAndPr({
            spawnCwd: spawnCwd!,
            installationToken,
            cronName: "cron-content-generator",
            commitMessage: COMMIT_MESSAGE,
            allowedPaths: CONTENT_GENERATOR_ALLOWED_PATHS,
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
            // Non-vacuous regardless: `paths === undefined` occurs only on the
            // replay-resume branch (handled above), so without this test the only
            // reachable RED cell would be `failed` — one bit, asserting nothing.
            commitResult.paths.length > 0 &&
            commitResult.paths.some((p) => CONTENT_GENERATOR_ALLOWED_PATHS.some((a) => p.startsWith(a)))
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
          cron: "cron-content-generator",
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
          cron: "cron-content-generator",
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
          cron: "cron-content-generator",
          run_id: runId ?? "unknown",
          attempt: attempt ?? 0,
          ok: 0,
          reason: "persistence-skipped",
        });
      }
    } catch (err) {
      // #5728 G1 — benign deploy-in-progress defer (ADR-078): rethrow bare, no
      // heartbeat. Any OTHER throw is a real failure — flag it;
      // finalizeOutputAwareHeartbeat decides error-vs-retry below.
      if (err instanceof DeployInProgressError) throw err;
      threw = true;
      const e = err as Error;
      const redactedMsg = redactToken(e.message ?? "", installationToken);
      const redacted = new Error(redactedMsg);
      redacted.name = e.name;
      reportSilentFallback(redacted, {
        feature: "cron-content-generator",
        op: "handler-body-threw",
        message:
          "cron-content-generator body threw before the terminal heartbeat",
        extra: {
          fn: "cron-content-generator",
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
      cronName: "cron-content-generator",
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
                  titlePrefix: "[Scheduled] Content Generator -",
                  cronName: "cron-content-generator",
                  runStartedAt,
                  spawnResult: spawnResult ?? makeThrewSpawnResult("cron-content-generator"),
                  installationToken,
                });
              } catch (err) {
                reportSilentFallback(err, {
                  feature: "cron-content-generator",
                  op: "ensure-audit-issue-failed",
                  message:
                    "Handler-level fallback audit-issue create failed; run remains silent until watchdog threshold",
                  extra: { fn: "cron-content-generator", runStartedAt },
                });
              }
            });
          },
    });
    if (retry) {
      throw new Error(
        "cron-content-generator failed on a non-final attempt; retrying",
      );
    }

    return { ok: heartbeatOk };
  } finally {
    await teardownEphemeralWorkspace(ephemeralRoot, "cron-content-generator").catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-content-generator",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-content-generator", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: scheduled cron (0 10 * * 2,4 UTC — Tuesday/Thursday 10:00) +
// manual operator event `cron/content-generator.manual-trigger`. account-scope
// concurrency "cron-platform" limits to 1 simultaneous cron-* invocation.

export const cronContentGenerator = inngest.createFunction(
  {
    id: "cron-content-generator",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 10 * * 2,4" },
    { event: "cron/content-generator.manual-trigger" },
  ],
  cronContentGeneratorHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
