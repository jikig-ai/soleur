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
  If no usable topic, create issue "[Scheduled] Content Generator - <today>" with label "scheduled-content-generator" and stop.

STEP 2 — Generate article:
Run /soleur:content-writer <topic> --headless
If content-writer aborts due to FAIL citations, create issue and stop.

STEP 3 — Generate distribution content:
Run /soleur:social-distribute <article-path> --headless
Ensure frontmatter has: publish_date: <today>, status: scheduled, channels: discord, x, bluesky, linkedin-company

STEP 4 — Validation runs in CI (do NOT build locally):
This ephemeral workspace is a shallow clone with no node_modules, so a local "npx @11ty/eleventy" build cannot run here. Validation happens on the PR the platform opens from your changes after the run: CI runs "npx @11ty/eleventy" and "scripts/validate-blog-links.sh", and the PR only auto-merges once those required checks pass. Your job is to make CI green — ensure the article's Eleventy frontmatter is valid and every internal link resolves. Do NOT attempt a local build or run the validation scripts yourself.

STEP 5 — Record topic in queue:
Update seo-refresh-queue.md with generated_date annotation.

STEP 6 — Create audit issue:
"[Scheduled] Content Generator - <today>" with label "scheduled-content-generator"

PERSISTENCE: Do NOT run git add, git commit, git push, or gh pr create/merge.
The platform commits and opens a PR for your changes automatically after the run.
Only changes under knowledge-base/marketing/ and plugins/soleur/docs/blog/ are persisted — keep all edits inside those paths.
Creating the audit issue in STEP 6 is REQUIRED: the platform only persists your changes after it verifies the issue exists.
`;

// Persistence allowlist (#5091): the article + distribution content + queue
// annotation land under knowledge-base/marketing/; content-writer's default
// article path is plugins/soleur/docs/blog/ (committable from the clone now
// that the substrate no longer symlink-shadows plugins/soleur).
const CONTENT_GENERATOR_ALLOWED_PATHS = [
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
  if (digestAlreadyExists) {
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
    // #5728 G1 — benign deploy-in-progress defer (ADR-068): rethrow bare, no heartbeat.
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
            prompt: CONTENT_GENERATOR_PROMPT,
            maxTurnDurationMs: MAX_TURN_DURATION_MS,
            cronName: "cron-content-generator",
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
        await step.run("safe-commit-pr", async () =>
          safeCommitAndPr({
            spawnCwd: spawnCwd!,
            installationToken,
            cronName: "cron-content-generator",
            commitMessage: "feat(content): auto-generate article",
            allowedPaths: CONTENT_GENERATOR_ALLOWED_PATHS,
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
