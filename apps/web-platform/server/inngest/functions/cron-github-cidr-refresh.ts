// cron-github-cidr-refresh (#5284) — self-refreshing GitHub /meta egress CIDR.
//
// Replaces the hand-snapshotted apps/web-platform/infra/cron-egress-allowlist-cidr.txt
// with a scheduled regenerate-from-external-source → PR-to-main cron, modeled on
// cron-content-vendor-drift.ts. GitHub rotates the api.github.com Azure 20.x/4.x
// /32 LB pool; when the committed list goes stale a cron fire lands on an
// uncovered IP, the container egress firewall default-drops it, and the GitHub
// call (hence the Sentry heartbeat) never happens — a silent missed check-in
// (the failure mode behind Sentry incident 5516336, #5281/#5285).
//
// Mechanism: clone the repo, fetch /meta via Octokit, run the COMMITTED generator
// apps/web-platform/infra/scripts/gen-github-egress-cidr.sh (the single source of
// truth — also exercised offline in CI by gen-github-egress-cidr.test.sh), and if
// the CIDR body drifted, persist via safeCommitAndPr({ mergeMode: "direct" }). The
// direct merge to main fires apply-web-platform-infra.yml, whose
// terraform_data.cron_egress_firewall config_hash keys on the CIDR file, so the
// firewall self-heals with ZERO new apply-path logic. safeCommitAndPr (ADR-054)
// handles the CLA synthetic checks + merge-to-main a raw `gh pr merge --auto`
// cannot do on a protected main branch.
//
// ADR-033 invariants:
//   I1 — Octokit + fs reads/writes called INSIDE step.run (replay memoization).
//   I2 — Operator-owned repo only; no founder BYOK.
//   I5 — Deterministic step.run return shapes.
//   I6 — No event payloads emitted.

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { Octokit } from "@octokit/core";
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
  DEFAULT_CRON_TOKEN_PERMISSIONS,
  type HandlerArgs,
} from "./_cron-shared";
import { SYNTHETIC_CHECK_NAMES, safeCommitAndPr } from "./_cron-safe-commit";

// =============================================================================
// Constants
// =============================================================================

export const CRON_NAME = "cron-github-cidr-refresh";
// Slug lockstep: this slug MUST be byte-identical to the function id, the
// cron-monitors.tf resource's monitor-slug, and the GHA workflow heartbeat
// slug (asserted by sentry-monitor-iac-parity.test.ts). The
// apply-sentry-infra.yml `-target=` line used to be a lockstep member too;
// #6589 made the apply full-root, so declaring the resource now applies it and
// there is no target line left to keep in step.
export const SENTRY_MONITOR_SLUG = "cron-github-cidr-refresh";

// Repo-root-relative paths. CIDR_FILE_REL is the single file this cron is allowed
// to persist; GEN_SCRIPT_REL is the committed generator (the source of truth).
export const CIDR_FILE_REL = "apps/web-platform/infra/cron-egress-allowlist-cidr.txt";
export const GEN_SCRIPT_REL = "apps/web-platform/infra/scripts/gen-github-egress-cidr.sh";

const TOKEN_MIN_LIFETIME_MS = 20 * 60 * 1000;

// =============================================================================
// Types
// =============================================================================

interface HandlerResult {
  ok: boolean;
  status: string;
  prNumber?: number;
}

// =============================================================================
// Helpers
// =============================================================================

/** Spawn a command and capture exit code + stdout + stderr. */
function runProc(
  cmd: string,
  args: string[],
  opts: { cwd?: string; env?: NodeJS.ProcessEnv } = {},
): Promise<{ exitCode: number | null; stdout: string; stderr: string }> {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"], ...opts });
    let stdout = "";
    let stderr = "";
    child.stdout?.on("data", (d: Buffer) => {
      stdout += d.toString();
    });
    child.stderr?.on("data", (d: Buffer) => {
      stderr += d.toString();
    });
    child.on("exit", (exitCode) => resolve({ exitCode, stdout, stderr }));
    child.on("error", (err) =>
      resolve({ exitCode: -1, stdout, stderr: stderr || String(err) }),
    );
  });
}

/**
 * Pure drift decision: `git status --porcelain` is empty when the generator
 * made no change (body unchanged → no-op, date NOT advanced) and non-empty when
 * the CIDR body drifted (a /meta rotation). Exported for unit testing.
 */
export function isCidrFileDirty(porcelain: string): boolean {
  return porcelain.trim().length > 0;
}

async function setupEphemeralWorkspace(
  token: string,
): Promise<{ ephemeralRoot: string; repoRoot: string }> {
  const ephemeralRoot = await mkdtemp(
    join(resolveCronWorkspaceRoot(), `soleur-${CRON_NAME}-`),
  );
  const repoRoot = join(ephemeralRoot, "repo");
  await warnIfCronWorkspaceLowOnDisk(ephemeralRoot, CRON_NAME);
  const clone = await runProc("git", [
    "clone",
    "--depth=1",
    buildAuthenticatedCloneUrl(token),
    repoRoot,
  ]);
  if (clone.exitCode !== 0) {
    throw new Error(
      `git clone failed (exit ${clone.exitCode}) for ${REPO_OWNER}/${REPO_NAME}`,
    );
  }
  if (!existsSync(join(repoRoot, CIDR_FILE_REL))) {
    throw new Error(`Sentinel: ${CIDR_FILE_REL} absent after clone`);
  }
  if (!existsSync(join(repoRoot, GEN_SCRIPT_REL))) {
    throw new Error(`Sentinel: ${GEN_SCRIPT_REL} absent after clone`);
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
      feature: CRON_NAME,
      op: "teardown-ephemeral-workspace",
      message: "Failed to remove ephemeral workspace",
      extra: { fn: CRON_NAME, ephemeralRoot },
    });
  }
}

/**
 * Fetch /meta, regenerate the committed CIDR file via the shell generator (one
 * source of truth), and on drift open a direct-merge PR. The /meta JSON is
 * written OUTSIDE the repo tree so it can never appear as a dirty path the
 * allowlist filter would drop.
 */
async function refreshCidr(args: {
  ephemeralRoot: string;
  repoRoot: string;
  octokit: Octokit;
  installationToken: string;
  runStartedAt: string;
  logger: HandlerArgs["logger"];
}): Promise<HandlerResult> {
  const { ephemeralRoot, repoRoot, octokit, installationToken, runStartedAt, logger } =
    args;

  // 1. Fetch /meta via the App-authenticated Octokit (unauthenticated endpoint,
  //    but routed through the same client for retry/observability parity).
  const { data: meta } = await octokit.request("GET /meta");
  const metaPath = join(ephemeralRoot, "github-meta.json");
  await writeFile(metaPath, JSON.stringify(meta));

  // 2. Run the COMMITTED generator against the fetched /meta (single source of
  //    truth). It validates + over-broad-rejects + writes atomically, and is a
  //    no-op when the body is unchanged (so no spurious daily PR / date churn).
  const gen = await runProc("bash", [join(repoRoot, GEN_SCRIPT_REL)], {
    cwd: repoRoot,
    env: {
      PATH: process.env.PATH,
      NODE_ENV: process.env.NODE_ENV,
      HOME: process.env.HOME,
      META_JSON_FILE: metaPath,
      OUT: join(repoRoot, CIDR_FILE_REL),
    },
  });
  // The temp /meta JSON has served its purpose — remove it regardless of outcome.
  await rm(metaPath, { force: true });
  if (gen.exitCode !== 0) {
    throw new Error(
      `generator exited ${gen.exitCode}: ${gen.stderr.slice(-2000)}`,
    );
  }

  // 3. Drift = the generator rewrote the committed file (body rotated).
  const status = await runProc(
    "git",
    ["status", "--porcelain=v1", "--", CIDR_FILE_REL],
    { cwd: repoRoot },
  );
  if (status.exitCode !== 0) {
    throw new Error(`git status failed: ${status.stderr.slice(-2000)}`);
  }
  if (!isCidrFileDirty(status.stdout)) {
    logger.info({ fn: CRON_NAME }, "no /meta drift — CIDR allowlist already current");
    return { ok: true, status: "no-drift" };
  }

  // 4. Drift → direct-merge PR. safeCommitAndPr scopes the commit to the single
  //    CIDR file (allowedPaths), posts the CLA synthetic checks, and merges to
  //    main so apply-web-platform-infra.yml re-provisions the firewall.
  logger.info({ fn: CRON_NAME }, "/meta drift detected — opening direct-merge refresh PR");
  const result = await safeCommitAndPr({
    spawnCwd: repoRoot,
    installationToken,
    cronName: CRON_NAME,
    commitMessage: "chore(infra): refresh GitHub /meta egress CIDR allowlist (#5284)",
    allowedPaths: [CIDR_FILE_REL],
    runStartedAt,
    scheduledIssueLabel: SENTRY_MONITOR_SLUG,
    prBody:
      "Automated refresh of the container egress CIDR allowlist on GitHub /meta rotation (#5284). " +
      "Regenerated by `apps/web-platform/infra/scripts/gen-github-egress-cidr.sh`; merges direct so " +
      "`apply-web-platform-infra.yml` re-provisions `terraform_data.cron_egress_firewall` and the " +
      "firewall self-heals.",
    syntheticChecks: {
      names: SYNTHETIC_CHECK_NAMES,
      summary: "Deterministic GitHub /meta CIDR refresh — see #5284",
    },
    mergeMode: "direct",
    octokit,
    logger,
  });

  return {
    ok: result.status !== "failed",
    status: result.status,
    prNumber: result.status === "committed" ? result.prNumber : undefined,
  };
}

// =============================================================================
// Handler
// =============================================================================

export async function cronGithubCidrRefreshHandler({
  step,
  logger,
}: HandlerArgs): Promise<HandlerResult> {
  let ephemeralRoot: string | null = null;
  let installationToken = "";

  try {
    const runStartedAt = await step.run(
      "run-started-at",
      async () => new Date().toISOString(),
    );

    installationToken = await step.run("mint-installation-token", async () =>
      mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
        // Least-privilege: push the refresh commit + open/merge the PR, nothing
        // more, scoped to soleur (#5046).
        permissions: DEFAULT_CRON_TOKEN_PERMISSIONS,
        repositories: [REPO_NAME],
      }),
    );

    const workspace = await step.run("setup-workspace", async () => {
      const ws = await setupEphemeralWorkspace(installationToken);
      ephemeralRoot = ws.ephemeralRoot;
      return { ephemeralRoot: ws.ephemeralRoot, repoRoot: ws.repoRoot };
    });
    ephemeralRoot = workspace.ephemeralRoot;

    const octokit = new Octokit({ auth: installationToken });

    const result = await step.run("refresh-cidr", async () =>
      refreshCidr({
        ephemeralRoot: workspace.ephemeralRoot,
        repoRoot: workspace.repoRoot,
        octokit,
        installationToken,
        runStartedAt,
        logger,
      }),
    );

    await step.run("sentry-heartbeat", () =>
      postSentryHeartbeat({
        ok: true,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: CRON_NAME,
        logger,
      }),
    );

    return result;
  } catch (err) {
    const e = err as Error;
    if (installationToken) {
      e.message = redactToken(e.message, installationToken);
    }
    reportSilentFallback(e, {
      feature: CRON_NAME,
      op: "handler-top-level",
      message: e.message,
    });
    try {
      await postSentryHeartbeat({
        ok: false,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: CRON_NAME,
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

export const cronGithubCidrRefresh = inngest.createFunction(
  {
    id: "cron-github-cidr-refresh",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "41 6 * * *" },
    { event: "cron/github-cidr-refresh.manual-trigger" },
  ],
  cronGithubCidrRefreshHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
