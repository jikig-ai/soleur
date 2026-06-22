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

import {
  redactToken,
  mintInstallationToken,
  deferIfTier2Cron,
  postSentryHeartbeat,
  resolveOutputAwareOk,
  ensureScheduledAuditIssue,
  warnIfCronWorkspaceLowOnDisk,
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
import { AUDIT_MODEL } from "@/server/inngest/model-tiers";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-architecture-diagram-sync";

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
After all diagrams are reviewed, create a single GitHub issue titled: "[Scheduled] Architecture Diagram Sync - <today>"
Labels: scheduled-architecture-diagram-sync
Milestone: Post-MVP / Later
Body: List each diagram file, whether it was up-to-date, and any changes made. If no drift was found, note that explicitly.
`;

// Paths the safeCommitAndPr helper is permitted to stage. Restricted to the
// diagrams directory to prevent accidental commits outside the audit scope.
const ARCH_DIAGRAM_ALLOWED_PATHS = [
  "knowledge-base/engineering/architecture/diagrams/",
];

// =============================================================================
// Handler
// =============================================================================

export async function cronArchitectureDiagramSyncHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean }> {
  const runStartedAt = new Date().toISOString();
  let ephemeralRoot: string | undefined;
  let installationToken: string | undefined;

  try {
    // --- Step 0: defer on Tier-2 firewall --------------------------------
    await deferIfTier2Cron(step, "cron-architecture-diagram-sync");

    // --- Step 1: mint a scoped GitHub App installation token -------------
    installationToken = await step.run(
      "mint-installation-token",
      async () => {
        const token = await mintInstallationToken({
          permissions: DEFAULT_CRON_TOKEN_PERMISSIONS,
          minLifetimeMs: TOKEN_MIN_LIFETIME_MS,
          cronName: "cron-architecture-diagram-sync",
        });
        logger.info("cron-architecture-diagram-sync: token minted", {
          tokenRedacted: redactToken(token),
        });
        return token;
      },
    );

    // --- Step 2: clone repo into ephemeral workspace ---------------------
    let spawnCwd: string | undefined;
    ({ ephemeralRoot, spawnCwd } = await step.run(
      "setup-ephemeral-workspace",
      async () =>
        setupEphemeralWorkspace({
          installationToken,
          cronName: "cron-architecture-diagram-sync",
        }),
    ));

    // --- Step 3: run claude eval -----------------------------------------
    let spawnResult: SpawnResult;
    spawnResult = await step.run("claude-eval", async () => {
      await warnIfCronWorkspaceLowOnDisk(
        "cron-architecture-diagram-sync",
        logger,
      );
      return spawnClaudeEval({
        cwd: spawnCwd\!,
        flags: CLAUDE_CODE_FLAGS,
        prompt: ARCHITECTURE_DIAGRAM_SYNC_PROMPT,
        maxTurnDurationMs: MAX_TURN_DURATION_MS,
        cronName: "cron-architecture-diagram-sync",
        logger,
      });
    });

    logger.info("cron-architecture-diagram-sync: claude-eval complete", {
      exitCode: spawnResult.exitCode,
      durationMs: spawnResult.durationMs,
      abortedByTimeout: spawnResult.abortedByTimeout,
    });

    // --- Step 4: output-aware heartbeat verification ---------------------
    if (spawnResult.abortedByTimeout) {
      reportSilentFallback(
        new Error("cron-architecture-diagram-sync aborted by timeout"),
        {
          feature: "cron-architecture-diagram-sync",
          op: "claude-eval-timeout",
          message:
            "Architecture diagram sync aborted by MAX_TURN_DURATION_MS timeout",
          extra: {
            fn: "cron-architecture-diagram-sync",
            exitCode: spawnResult.exitCode,
            stdoutTail: spawnResult.stdoutTail,
          },
        },
      );
    }

    const heartbeatOk = await step.run("verify-output", async () =>
      resolveOutputAwareOk({
        spawnResult,
        label: SENTRY_MONITOR_SLUG,
        runStartedAt,
        installationToken: installationToken\!,
        cronName: "cron-architecture-diagram-sync",
        logger,
      }),
    );

    // --- Step 4.5: persist diagram edits as a PR -------------------------
    if (heartbeatOk && \!spawnResult.abortedByTimeout) {
      await step.run("safe-commit-pr", async () =>
        safeCommitAndPr({
          spawnCwd: spawnCwd\!,
          installationToken: installationToken\!,
          cronName: "cron-architecture-diagram-sync",
          commitMessage: "docs(arch): weekly architecture diagram sync",
          allowedPaths: ARCH_DIAGRAM_ALLOWED_PATHS,
          runStartedAt,
          scheduledIssueLabel: SENTRY_MONITOR_SLUG,
          logger,
        }),
      );
    }

    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({
        ok: heartbeatOk,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-architecture-diagram-sync",
        logger,
      });
    });

    // --- Step 5: silence-hole fallback -----------------------------------
    if (\!heartbeatOk) {
      await step.run("ensure-audit-issue", async () => {
        try {
          await ensureScheduledAuditIssue({
            label: SENTRY_MONITOR_SLUG,
            titlePrefix: "[Scheduled] Architecture Diagram Sync -",
            cronName: "cron-architecture-diagram-sync",
            runStartedAt,
            spawnResult,
            installationToken: installationToken\!,
          });
        } catch (err) {
          reportSilentFallback(err, {
            feature: "cron-architecture-diagram-sync",
            op: "ensure-audit-issue-failed",
            message:
              "Handler-level fallback audit-issue create failed; run remains silent until watchdog threshold",
            extra: { fn: "cron-architecture-diagram-sync", runStartedAt },
          });
        }
      });
    }

    return { ok: heartbeatOk };
  } finally {
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
