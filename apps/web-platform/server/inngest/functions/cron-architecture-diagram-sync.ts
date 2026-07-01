// Weekly architecture diagram sync — inspects the C4 diagrams in
// knowledge-base/engineering/architecture/diagrams/ and updates any that
// have drifted from the current codebase structure.
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — claude binary spawned INSIDE step.run (Inngest replay memoization).
//   I2 — Operator ANTHROPIC_API_KEY only; never founder BYOK. Enforced at
//        build time by test/server/cron-no-byok-lease-sweep.test.ts.
//   I3 — AbortSignal aborts at MAX_TURN_DURATION_MS (60 min). Manual
//        SIGTERM→SIGKILL escalation via process-group kill (detached:true).
//   I4 — claude binary resolved at spawn time via filesystem checks; the
//        CLAUDE_BIN env var is the override hatch for fresh-host bootstraps.
//   I5 — Deterministic step.run return shape: {ok, exitCode, signal,
//        abortedByTimeout, durationMs}. stdout is NOT captured.
//   I6 — Event payloads emitted by cron-*.ts MUST carry actor: "platform".
//        (This handler emits none.)
//
// Side-effect class: issue-creator + pr-creator. Persistence runs handler-side
// via safeCommitAndPr after the eval (#5091/#5111); the prompt forbids the
// spawned claude from running git/gh-pr verbs. Structural template:
// cron-seo-aeo-audit.ts.

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

const SENTRY_MONITOR_SLUG = "scheduled-architecture-diagram-sync";

const SCHEDULED_ISSUE_TITLE_PREFIX = "[Scheduled] Architecture Diagram Sync -";

// Token-lifetime floor: 60-min wall-clock budget + 10-min headroom for
// setup / teardown / retry.
const TOKEN_MIN_LIFETIME_MS = 70 * 60 * 1000;

// 60-min wall-clock budget — architecture review is moderately deep but
// bounded (diagrams/ directory is small). Exported for test parity.
export const MAX_TURN_DURATION_MS = 60 * 60 * 1000;
export { KILL_ESCALATION_MS } from "./_cron-claude-eval-substrate";

// claude-code spawn argv. `--` is load-bearing per #4017 bug 8/8.
// Uses AUDIT_MODEL (opus) for strong cross-layer reasoning over the
// codebase architecture (routes, server functions, Inngest functions, DB
// schema, infra Terraform, Soleur plugin skills) vs diagram DSL.
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  AUDIT_MODEL,
  "--max-turns",
  "60",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep,Skill,Task",
  "--plugin-dir",
  "plugins/soleur",
  "--",
];

const ARCHITECTURE_DIAGRAM_SYNC_PROMPT = `IMPORTANT: This is an automated CI workflow. Do NOT push directly to main.

MILESTONE RULE: Every gh issue create command must include --milestone. Use --milestone "Post-MVP / Later" for operational issues.

Compute today's date yourself in YYYY-MM-DD format and use that literal value as <today> throughout. Do NOT use a shell command substitution to obtain the date — the containment hook denies command substitution.

Your job is to audit the C4 architecture diagrams stored in knowledge-base/engineering/architecture/diagrams/ and update any that have drifted from the current state of the codebase.

Step 1: Inventory diagrams
List every .c4 file under knowledge-base/engineering/architecture/diagrams/ using Glob. For each one, read the full source and note: (a) which system/container/component it describes, (b) the boundaries and relationships it asserts.

Step 2: Audit against the codebase
For each diagram, probe the codebase to verify accuracy:
- Use Grep and Glob to check that every named service, route, or component still exists in its described form.
- Check apps/web-platform/app/ for Next.js routes and API routes.
- Check apps/web-platform/server/inngest/functions/ for Inngest event/cron boundaries.
- Check infra/ or terraform/ for infrastructure components.
- Check plugins/soleur/ for skill/agent layer boundaries.
- Compare the diagram's stated relationships (HTTP, DB, message queue, etc.) against the actual code.

Step 3: Update stale diagrams
For each diagram that is out of date, edit the .c4 source file directly to bring it in sync with the current codebase. Preserve the existing style and DSL conventions. Do NOT invent speculative components — only add or remove what the code clearly confirms. After each edit, leave a short comment in the diagram noting the date it was last verified: // last-verified: <today>

Step 4: Record a summary issue
After all diagrams are reviewed, create a single GitHub issue titled: "${SCHEDULED_ISSUE_TITLE_PREFIX} <today>"
Labels: scheduled-architecture-diagram-sync
Milestone: Post-MVP / Later
Body: List each diagram file, whether it was up-to-date, and any changes made. If no drift was found, note that explicitly.

PERSISTENCE: Do NOT run git add, git commit, git push, or gh pr create/merge.
The platform commits and opens a PR for your changes automatically after the run.
Only changes under knowledge-base/engineering/architecture/diagrams/ are persisted — keep all edits inside that path.
Creating the summary issue above is REQUIRED: the platform only persists your changes after it verifies the issue exists.
`;

// Paths the safeCommitAndPr helper is permitted to stage. Restricted to the
// diagrams directory to prevent accidental commits outside the audit scope.
const ARCH_DIAGRAM_ALLOWED_PATHS = [
  "knowledge-base/engineering/architecture/diagrams/",
] as const;

// Spawn-env allowlist (NOT a denylist). The keys below are the COMPLETE
// set the spawned claude is allowed to see; anything not listed is excluded.
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

export async function cronArchitectureDiagramSyncHandler({
  step,
  logger,
  attempt,
  maxAttempts,
  runId,
}: HandlerArgs): Promise<{ ok: boolean }> {
  // Tier-2 firewall: posts an honest on-schedule check-in and skips the spawn
  // if this cron is still deferred (no fail-closed FAILED-issue storm).
  if (
    await deferIfTier2Cron({
      cronName: "cron-architecture-diagram-sync",
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      step,
      logger,
    })
  ) {
    return { ok: true };
  }

  // Run-window start — lower bound for the post-run output check. Captured
  // before the mint step (memoized across replays) so a replay reuses the
  // original window rather than re-stamping a later "now".
  const runStartedAt = await step.run(
    "run-started-at",
    async () => new Date().toISOString(),
  );

  // #5786 — producer-side date-dedup. If a real summary issue already exists
  // for today, skip the eval and post a healthy OK heartbeat — do NOT fall
  // through to verify-output (whose run-window would exclude the earlier issue
  // and false-RED the skip). Fail-OPEN: a read error → spawn.
  const digestAlreadyExists = await step.run("dedup-digest-check", async () =>
    digestIssueExistsForDate({
      label: SENTRY_MONITOR_SLUG,
      titlePrefix: SCHEDULED_ISSUE_TITLE_PREFIX,
      date: runStartedAt.slice(0, 10),
      cronName: "cron-architecture-diagram-sync",
    }),
  );
  if (digestAlreadyExists) {
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({
        ok: true,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-architecture-diagram-sync",
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
      return setupEphemeralWorkspace({
        installationToken,
        cronName: "cron-architecture-diagram-sync",
      });
    });
    ephemeralRoot = workspace.ephemeralRoot;
    spawnCwd = workspace.spawnCwd;
  } catch (err) {
    // #5728 G1 — benign deploy-in-progress defer (ADR-076): rethrow bare.
    if (err instanceof DeployInProgressError) throw err;
    const e = err as Error;
    const redacted = new Error(redactToken(e.message ?? "", installationToken));
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: "cron-architecture-diagram-sync",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-architecture-diagram-sync" },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({
        ok: false,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-architecture-diagram-sync",
        logger,
      });
    });
    return { ok: false };
  }

  try {
    // #5728 — flag pattern. The body runs in an inner try whose throw sets
    // `threw`; the single terminal heartbeat is posted by
    // finalizeOutputAwareHeartbeat below.
    let heartbeatOk = false;
    let threw = false;
    let spawnResult: SpawnResult | null = null;
    try {
      // --- Step 3: claude-eval (60-min AbortController) ---
      spawnResult = await step.run(
        "claude-eval",
        async (): Promise<SpawnResult> => {
          return spawnClaudeEval({
            spawnCwd: spawnCwd!,
            installationToken,
            flags: CLAUDE_CODE_FLAGS,
            prompt: ARCHITECTURE_DIAGRAM_SYNC_PROMPT,
            maxTurnDurationMs: MAX_TURN_DURATION_MS,
            cronName: "cron-architecture-diagram-sync",
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
            feature: "cron-architecture-diagram-sync",
            op: "claude-eval-timeout",
            message: "claude-eval aborted by AbortController",
            extra: {
              fn: "cron-architecture-diagram-sync",
              durationMs: spawnResult.durationMs,
              maxMs: MAX_TURN_DURATION_MS,
            },
          },
        );
      }

      // --- Step 4: output-aware heartbeat. This cron is an always-create
      //     producer (files a summary issue every run), so a clean exit that
      //     produced no scheduled-architecture-diagram-sync issue in the run
      //     window turns the monitor RED instead of false-green on exit code. ---
      heartbeatOk = await step.run("verify-output", async () =>
        resolveOutputAwareOk({
          spawnOk: spawnResult!.ok,
          label: SENTRY_MONITOR_SLUG,
          runStartedAt,
          cronName: "cron-architecture-diagram-sync",
          stderrTail: spawnResult!.stderrTail,
          exitCode: spawnResult!.exitCode,
          stdoutTail: spawnResult!.stdoutTail,
        }),
      );

      // --- Step 4.5: deterministic persistence (#5091). Gated on the
      //     issue-verified output rather than the spawn exit code; abortedByTimeout
      //     also skips (a hard kill can land mid-edit). ---
      if (heartbeatOk && !spawnResult.abortedByTimeout) {
        await step.run("safe-commit-pr", async () =>
          safeCommitAndPr({
            spawnCwd: spawnCwd!,
            installationToken,
            cronName: "cron-architecture-diagram-sync",
            commitMessage: "docs(arch): weekly architecture diagram sync",
            allowedPaths: ARCH_DIAGRAM_ALLOWED_PATHS,
            runStartedAt,
            scheduledIssueLabel: SENTRY_MONITOR_SLUG,
            logger,
          }),
        );
      }
    } catch (err) {
      // #5728 G1 — a deploy-in-progress defer is benign: rethrow bare with NO
      // heartbeat. Any OTHER throw is a real failure — flag it;
      // finalizeOutputAwareHeartbeat decides error-vs-retry below.
      if (err instanceof DeployInProgressError) throw err;
      threw = true;
      const e = err as Error;
      const redacted = new Error(
        redactToken(e.message ?? "", installationToken),
      );
      redacted.name = e.name;
      reportSilentFallback(redacted, {
        feature: "cron-architecture-diagram-sync",
        op: "handler-body-threw",
        message:
          "cron-architecture-diagram-sync body threw before the terminal heartbeat",
        extra: {
          fn: "cron-architecture-diagram-sync",
          attempt: attempt ?? 0,
          producedOutput: heartbeatOk,
        },
      });
    }

    // --- Single authoritative terminal heartbeat (memoization-safe,
    //     final-attempt gated). On a non-final failure the helper skips the
    //     heartbeat and returns retry:true. On the post path, the silence-hole
    //     fallback files a FAILED audit issue when red, ordered BEFORE the
    //     heartbeat so the heartbeat stays the genuine last step. ---
    const { retry } = await finalizeOutputAwareHeartbeat({
      step,
      heartbeatOk,
      threw,
      attempt,
      maxAttempts,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-architecture-diagram-sync",
      logger,
      onBeforeHeartbeat: heartbeatOk
        ? undefined
        : async () => {
            await step.run("ensure-audit-issue", async () => {
              try {
                await ensureScheduledAuditIssue({
                  label: SENTRY_MONITOR_SLUG,
                  titlePrefix: SCHEDULED_ISSUE_TITLE_PREFIX,
                  cronName: "cron-architecture-diagram-sync",
                  runStartedAt,
                  spawnResult:
                    spawnResult ??
                    makeThrewSpawnResult("cron-architecture-diagram-sync"),
                  installationToken,
                });
              } catch (err) {
                reportSilentFallback(err, {
                  feature: "cron-architecture-diagram-sync",
                  op: "ensure-audit-issue-failed",
                  message:
                    "Handler-level fallback audit-issue create failed; run remains silent until watchdog threshold",
                  extra: {
                    fn: "cron-architecture-diagram-sync",
                    runStartedAt,
                  },
                });
              }
            });
          },
    });
    if (retry) {
      throw new Error(
        "cron-architecture-diagram-sync failed on a non-final attempt; retrying",
      );
    }

    return { ok: heartbeatOk };
  } finally {
    // Best-effort teardown (idempotent rm -rf with force:true).
    await teardownEphemeralWorkspace(
      ephemeralRoot,
      "cron-architecture-diagram-sync",
    ).catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-architecture-diagram-sync",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-architecture-diagram-sync", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: scheduled cron (0 2 * * 0 UTC — weekly Sunday 02:00, off-peak
// to avoid Monday morning slot collision) + manual operator event
// `cron/architecture-diagram-sync.manual-trigger`. account-scope concurrency
// "cron-platform" limits to 1 simultaneous cron-* invocation.

export const cronArchitectureDiagramSync = inngest.createFunction(
  {
    id: "cron-architecture-diagram-sync",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 2 * * 0" },
    { event: "cron/architecture-diagram-sync.manual-trigger" },
  ],
  cronArchitectureDiagramSyncHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
