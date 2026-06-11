// TR9 Phase-2 — Migrated from the GHA scheduled-content-publisher
// workflow (deleted in the same PR per TR9 I-13 hygiene). Spawns the
// existing scripts/content-publisher.sh and creates a bot-PR with
// synthetic checks for any status updates committed by the script.
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — Octokit + node:fs reads called INSIDE step.run (replay memoization).
//   I2 — Operator-owned data only; never founder BYOK.
//   I3 — Outer wall-clock safety via Promise.race (MAX_RUN_DURATION_MS).
//   I4 — N/A (no claude binary; bash script spawn only).
//   I5 — Deterministic step.run return shape per step (see handler).
//   I6 — No event payloads emitted.
//
// SPAWN PATTERN — the content-publisher.sh script has complex platform-
// specific API logic (OAuth, multipart uploads, etc.). Cleanest port is
// to keep the existing bash script and spawn it from Inngest, capturing
// its exit code. Same pattern as cron-compound-promote.ts which spawns
// git commands.

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { join } from "node:path";
import matter from "gray-matter";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  REPO_OWNER,
  REPO_NAME,
  redactToken,
  buildAuthenticatedCloneUrl,
  resolveCronWorkspaceRoot,
  warnIfCronWorkspaceLowOnDisk,
  mintInstallationToken,
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";
import { SYNTHETIC_CHECK_NAMES, safeCommitAndPr } from "./_cron-safe-commit";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-content-publisher";

export const MAX_RUN_DURATION_MS = 10 * 60 * 1000;
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

const CONTENT_DIR_REL = "knowledge-base/marketing/distribution-content";

/** Environment variable names forwarded to the content-publisher.sh spawn. */
export const PUBLISHER_ENV_KEYS = [
  "DISCORD_BLOG_WEBHOOK_URL",
  "DISCORD_WEBHOOK_URL",
  "X_API_KEY",
  "X_API_SECRET",
  "X_ACCESS_TOKEN",
  "X_ACCESS_TOKEN_SECRET",
  "LINKEDIN_ACCESS_TOKEN",
  "LINKEDIN_PERSON_URN",
  "LINKEDIN_ORG_ID",
  "LINKEDIN_ORG_ACCESS_TOKEN",
  "BSKY_HANDLE",
  "BSKY_APP_PASSWORD",
] as const;

// =============================================================================
// Types
// =============================================================================

interface HandlerResult {
  ok: boolean;
  status: string;
  published?: number;
  staleDetected?: number;
}

// =============================================================================
// Helpers
// =============================================================================

function spawnGit(
  args: string[],
  opts?: { cwd?: string; env?: NodeJS.ProcessEnv },
): Promise<{ exitCode: number | null; signal: NodeJS.Signals | null }> {
  return new Promise((resolve) => {
    const child = spawn("git", args, { stdio: "ignore", ...opts });
    child.on("exit", (exitCode, signal) => resolve({ exitCode, signal }));
    child.on("error", () => resolve({ exitCode: -1, signal: null }));
  });
}

async function setupEphemeralWorkspace(
  token: string,
): Promise<{ ephemeralRoot: string; repoRoot: string }> {
  const ephemeralRoot = await mkdtemp(
    join(resolveCronWorkspaceRoot(), "soleur-cron-content-publisher-"),
  );
  const repoRoot = join(ephemeralRoot, "repo");
  await warnIfCronWorkspaceLowOnDisk(ephemeralRoot, "cron-content-publisher");
  const cloneUrl = buildAuthenticatedCloneUrl(token);
  const result = await spawnGit(["clone", "--depth=1", cloneUrl, repoRoot]);
  if (result.exitCode !== 0) {
    throw new Error(
      `git clone failed (exit ${result.exitCode}, signal ${result.signal}) for ${REPO_OWNER}/${REPO_NAME}`,
    );
  }
  if (!existsSync(join(repoRoot, CONTENT_DIR_REL))) {
    throw new Error(
      `Sentinel: ${CONTENT_DIR_REL}/ absent after clone`,
    );
  }
  return { ephemeralRoot, repoRoot };
}

async function teardownEphemeralWorkspace(
  ephemeralRoot: string | null,
): Promise<void> {
  if (!ephemeralRoot) return;
  try {
    await rm(ephemeralRoot, { recursive: true, force: true });
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cron-content-publisher",
      op: "teardown-ephemeral-workspace",
      message: "Failed to remove ephemeral workspace",
      extra: { fn: "cron-content-publisher", ephemeralRoot },
    });
  }
}

/**
 * Build the env map for the content-publisher.sh spawn. Explicit allowlist
 * of the 12 social API secrets + PATH/HOME/GH_TOKEN. No `...process.env`
 * spread — that would leak Doppler secrets into the child.
 */
export function buildPublisherEnv(ghToken: string): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    NODE_ENV: process.env.NODE_ENV,
    GH_TOKEN: ghToken,
    X_ALLOW_POST: "true",
    LINKEDIN_ALLOW_POST: "true",
    BSKY_ALLOW_POST: "true",
  };
  for (const key of PUBLISHER_ENV_KEYS) {
    env[key] = process.env[key];
  }
  return env;
}

/** Spawn a bash script and capture stdout + stderr + exit code. */
async function spawnScriptCapture(
  script: string,
  args: string[],
  opts: { cwd: string; env: NodeJS.ProcessEnv },
): Promise<{ exitCode: number | null; stdout: string; stderr: string }> {
  return new Promise((resolve) => {
    const child = spawn("bash", [script, ...args], {
      stdio: ["ignore", "pipe", "pipe"],
      cwd: opts.cwd,
      env: opts.env,
    });
    let stdout = "";
    let stderr = "";
    child.stdout?.on("data", (d: Buffer) => {
      stdout += d.toString();
    });
    child.stderr?.on("data", (d: Buffer) => {
      stderr += d.toString();
    });
    child.on("exit", (exitCode) => resolve({ exitCode, stdout, stderr }));
    child.on("error", () => resolve({ exitCode: -1, stdout, stderr }));
  });
}

// gray-matter parses YAML 1.1, which coerces unquoted ISO dates into
// JavaScript Date objects. Coerce both shapes to YYYY-MM-DD.
function coerceFrontmatterDate(raw: unknown): string | undefined {
  if (raw === undefined || raw === null) return undefined;
  if (raw instanceof Date) {
    if (Number.isNaN(raw.getTime())) return undefined;
    return raw.toISOString().slice(0, 10);
  }
  return String(raw);
}

// =============================================================================
// Handler
// =============================================================================

export async function cronContentPublisherHandler({
  step,
  logger,
}: HandlerArgs): Promise<HandlerResult> {
  let ephemeralRoot: string | null = null;
  let installationToken = "";

  try {
    // Memoized run-start timestamp — safeCommitAndPr derives the ci/ branch
    // name and pins commit dates from it (replay-stable, #5111).
    const runStartedAt = await step.run(
      "run-started-at",
      async () => new Date().toISOString(),
    );

    installationToken = await step.run(
      "mint-installation-token",
      async () => mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS }),
    );

    const workspace = await step.run("setup-workspace", async () => {
      const ws = await setupEphemeralWorkspace(installationToken);
      ephemeralRoot = ws.ephemeralRoot;
      return { ephemeralRoot: ws.ephemeralRoot, repoRoot: ws.repoRoot };
    });

    const repoRoot = workspace.repoRoot;
    ephemeralRoot = workspace.ephemeralRoot;

    // Detect stale content before running publisher (status: scheduled +
    // publish_date in the past). Report via reportSilentFallback.
    const preCheck = await step.run("pre-check-stale-content", async () => {
      const contentDir = join(repoRoot, CONTENT_DIR_REL);
      let staleCount = 0;
      let scheduledToday = 0;
      const todayISO = new Date().toISOString().slice(0, 10);

      try {
        const files = await readdir(contentDir);
        for (const name of files) {
          if (!name.endsWith(".md")) continue;
          const filePath = join(contentDir, name);
          const raw = await readFile(filePath, "utf-8");
          let parsed: ReturnType<typeof matter>;
          try {
            parsed = matter(raw);
          } catch {
            continue;
          }
          const status = parsed.data.status as string | undefined;
          if (status !== "scheduled") continue;

          const publishDate = coerceFrontmatterDate(parsed.data.publish_date);
          if (!publishDate) continue;

          if (publishDate === todayISO) {
            scheduledToday++;
          } else if (publishDate < todayISO) {
            staleCount++;
            reportSilentFallback(
              new Error(`Stale scheduled content: ${name}`),
              {
                feature: "cron-content-publisher",
                op: "stale-content-detection",
                message: `File ${name} has status:scheduled but publish_date ${publishDate} is in the past`,
                extra: { fn: "cron-content-publisher", file: name, publishDate },
              },
            );
          }
        }
      } catch (err) {
        reportSilentFallback(err, {
          feature: "cron-content-publisher",
          op: "pre-check-stale-content",
          message: "Failed to scan content directory",
          extra: { fn: "cron-content-publisher" },
        });
      }
      return { staleCount, scheduledToday };
    });

    // Run the content-publisher script
    const publishResult = await step.run("run-publisher-script", async () => {
      const staleEventsFile = join(ephemeralRoot!, "stale-events.txt");
      const env = buildPublisherEnv(installationToken);
      env.STALE_EVENTS_FILE = staleEventsFile;

      const scriptPath = join(repoRoot, "scripts", "content-publisher.sh");
      if (!existsSync(scriptPath)) {
        throw new Error("scripts/content-publisher.sh not found in clone");
      }

      const result = await spawnScriptCapture(scriptPath, [], {
        cwd: repoRoot,
        env,
      });

      if (result.exitCode === 2) {
        logger.warn(
          { fn: "cron-content-publisher", exitCode: result.exitCode },
          "Partial failure — some platforms failed but fallback issues were created",
        );
      } else if (result.exitCode !== 0 && result.exitCode !== null) {
        throw new Error(
          `content-publisher.sh failed (exit ${result.exitCode})`,
        );
      }

      return { exitCode: result.exitCode };
    });

    // Persist status updates via safeCommitAndPr (#5111) — gains the
    // deletion guard, dirty-index precondition, dropped-path warn, and
    // replay idempotency. mergeMode "direct" + synthetic checks preserves
    // this pipeline's production-proven merge mechanics; the helper's
    // direct→arm-auto-merge→loud-failure ladder strictly improves on the
    // old log-only catch.
    const prResult = await step.run("safe-commit-pr", async () => {
      const result = await safeCommitAndPr({
        spawnCwd: repoRoot,
        installationToken,
        cronName: "cron-content-publisher",
        commitMessage: "ci: update content distribution status",
        // Trailing slash added vs CONTENT_DIR_REL: the helper's allowlist
        // matching is bare startsWith and directory entries must end "/".
        allowedPaths: [`${CONTENT_DIR_REL}/`],
        runStartedAt,
        scheduledIssueLabel: SENTRY_MONITOR_SLUG,
        prBody: "Automated status update from content publisher workflow.",
        syntheticChecks: {
          names: SYNTHETIC_CHECK_NAMES,
          summary: "Status metadata only, no code changes",
        },
        mergeMode: "direct",
        logger,
      });
      return result.status === "committed"
        ? { prCreated: true, prNumber: result.prNumber }
        : { prCreated: false };
    });

    await step.run("sentry-heartbeat", () =>
      postSentryHeartbeat({
        ok: true,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-content-publisher",
        logger,
      }),
    );

    return {
      ok: true,
      status:
        publishResult.exitCode === 2
          ? "partial-failure"
          : prResult.prCreated
            ? "published"
            : "no-changes",
      published: preCheck.scheduledToday,
      staleDetected: preCheck.staleCount,
    };
  } catch (err) {
    const e = err as Error;
    if (installationToken) {
      e.message = redactToken(e.message, installationToken);
    }
    reportSilentFallback(e, {
      feature: "cron-content-publisher",
      op: "handler-top-level",
      message: e.message,
    });
    try {
      await postSentryHeartbeat({
        ok: false,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-content-publisher",
        logger,
      });
    } catch {
      // best-effort
    }
    return { ok: false, status: "error" };
  } finally {
    await teardownEphemeralWorkspace(ephemeralRoot);
  }
}

// =============================================================================
// Registration
// =============================================================================

export const cronContentPublisher = inngest.createFunction(
  {
    id: "cron-content-publisher",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 14 * * *" },
    { event: "cron/content-publisher.manual-trigger" },
  ],
  cronContentPublisherHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
