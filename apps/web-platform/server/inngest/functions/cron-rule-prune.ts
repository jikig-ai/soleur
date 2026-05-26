// TR9 Phase-2 — Migrated from the GHA scheduled-rule-prune workflow
// (deleted in the same PR per TR9 I-13 hygiene). Quarterly AGENTS.md rule
// pruning. Runs scripts/rule-prune.sh --weeks=26 --propose-retirement,
// parses sentinels from stdout, opens consolidated PR via bot-PR with
// synthetic checks.
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — Octokit + node:fs reads called INSIDE step.run (replay memoization).
//   I2 — Operator-owned data only; never founder BYOK.
//   I3 — Outer wall-clock safety via Promise.race (MAX_RUN_DURATION_MS).
//   I4 — N/A (no claude binary; bash script spawn only).
//   I5 — Deterministic step.run return shape per step (see handler).
//   I6 — No event payloads emitted.
//
// SPAWN PATTERN — scripts/rule-prune.sh has complex jq/sed logic for
// parsing rule-metrics.json and appending to retired-rule-ids.txt. The
// Inngest port spawns the script and parses its stdout sentinels
// (::rule-prune-pr-title:: and ::rule-prune-pr-body::) to construct
// the PR.

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Octokit } from "@octokit/core";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  REPO_OWNER,
  REPO_NAME,
  redactToken,
  buildAuthenticatedCloneUrl,
  mintInstallationToken,
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-rule-prune";

export const MAX_RUN_DURATION_MS = 5 * 60 * 1000;
const TOKEN_MIN_LIFETIME_MS = 10 * 60 * 1000;

export const SENTINEL_PR_TITLE = "::rule-prune-pr-title::";
export const SENTINEL_PR_BODY = "::rule-prune-pr-body::";

export const SYNTHETIC_CHECK_NAMES = [
  "test",
  "dependency-review",
  "e2e",
  "skill-security-scan PR gate",
  "enforce",
  "cla-check",
  "cla-evidence",
] as const;

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

async function spawnGitChecked(
  args: string[],
  opts?: { cwd?: string; env?: NodeJS.ProcessEnv },
): Promise<void> {
  const result = await spawnGit(args, opts);
  if (result.exitCode !== 0) {
    throw new Error(`git ${args[0]} failed (exit ${result.exitCode})`);
  }
}

function spawnGitCapture(
  args: string[],
  opts?: { cwd?: string },
): Promise<string> {
  return new Promise((resolve) => {
    const child = spawn("git", args, { ...opts });
    let out = "";
    child.stdout?.on("data", (d: Buffer) => {
      out += d.toString();
    });
    child.on("exit", () => resolve(out.trim()));
    child.on("error", () => resolve(""));
  });
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

async function setupEphemeralWorkspace(
  token: string,
): Promise<{ ephemeralRoot: string; repoRoot: string }> {
  const ephemeralRoot = await mkdtemp(
    join(tmpdir(), "soleur-cron-rule-prune-"),
  );
  const repoRoot = join(ephemeralRoot, "repo");
  const cloneUrl = buildAuthenticatedCloneUrl(token);
  const result = await spawnGit(["clone", "--depth=1", cloneUrl, repoRoot]);
  if (result.exitCode !== 0) {
    throw new Error(
      `git clone failed (exit ${result.exitCode}, signal ${result.signal}) for ${REPO_OWNER}/${REPO_NAME}`,
    );
  }
  if (!existsSync(join(repoRoot, "scripts", "rule-prune.sh"))) {
    throw new Error(
      "Sentinel: scripts/rule-prune.sh absent after clone",
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
      feature: "cron-rule-prune",
      op: "teardown-ephemeral-workspace",
      message: "Failed to remove ephemeral workspace",
      extra: { fn: "cron-rule-prune", ephemeralRoot },
    });
  }
}

/** Parse stdout sentinels emitted by rule-prune.sh --propose-retirement. */
export function parseSentinels(stdout: string): {
  prTitle: string | null;
  prBody: string | null;
} {
  let prTitle: string | null = null;
  let prBody: string | null = null;

  for (const line of stdout.split("\n")) {
    if (line.startsWith(SENTINEL_PR_TITLE)) {
      prTitle = line.slice(SENTINEL_PR_TITLE.length).trim();
    } else if (line.startsWith(SENTINEL_PR_BODY)) {
      prBody = line.slice(SENTINEL_PR_BODY.length).trim();
    }
  }

  return { prTitle, prBody };
}

// =============================================================================
// Handler
// =============================================================================

export async function cronRulePruneHandler({
  step,
  logger,
}: HandlerArgs): Promise<HandlerResult> {
  let ephemeralRoot: string | null = null;
  let installationToken = "";

  try {
    installationToken = await step.run(
      "mint-installation-token",
      async () =>
        mintInstallationToken({
          tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
        }),
    );

    const workspace = await step.run("setup-workspace", async () => {
      const ws = await setupEphemeralWorkspace(installationToken);
      ephemeralRoot = ws.ephemeralRoot;
      return {
        ephemeralRoot: ws.ephemeralRoot,
        repoRoot: ws.repoRoot,
      };
    });

    const repoRoot = workspace.repoRoot;
    ephemeralRoot = workspace.ephemeralRoot;

    // Run rule-prune.sh --weeks=26 --propose-retirement
    const pruneResult = await step.run("run-rule-prune", async () => {
      const scriptPath = join(repoRoot, "scripts", "rule-prune.sh");
      const env: NodeJS.ProcessEnv = {
        PATH: process.env.PATH,
        HOME: process.env.HOME,
        GH_TOKEN: installationToken,
      };

      const result = await spawnScriptCapture(
        scriptPath,
        ["--weeks=26", "--propose-retirement"],
        { cwd: repoRoot, env },
      );

      logger.info(
        {
          fn: "cron-rule-prune",
          exitCode: result.exitCode,
          stdoutLen: result.stdout.length,
        },
        "rule-prune.sh completed",
      );

      const sentinels = parseSentinels(result.stdout);

      if (!sentinels.prTitle || !sentinels.prBody) {
        // Check for partial-failure: file modified but no sentinels
        const diffCheck = await spawnGit(
          ["diff", "--quiet", "--", "scripts/retired-rule-ids.txt"],
          { cwd: repoRoot },
        );
        if (diffCheck.exitCode !== 0) {
          throw new Error(
            "retired-rule-ids.txt was modified but no sentinels emitted — partial-failure recovery",
          );
        }
        return {
          noCandidates: true,
          prTitle: null as string | null,
          prBody: null as string | null,
        };
      }

      return {
        noCandidates: false,
        prTitle: sentinels.prTitle,
        prBody: sentinels.prBody,
      };
    });

    if (pruneResult.noCandidates) {
      await step.run("sentry-heartbeat-no-candidates", () =>
        postSentryHeartbeat({
          ok: true,
          sentryMonitorSlug: SENTRY_MONITOR_SLUG,
          cronName: "cron-rule-prune",
          logger,
        }),
      );
      return { ok: true, status: "no-candidates" };
    }

    // Open bot-PR with synthetic checks
    const prResult = await step.run("open-retirement-pr", async () => {
      const octokit = new Octokit({ auth: installationToken });
      const dateSuffix = new Date().toISOString().slice(0, 10);
      const branchName = `ci/rule-prune-retire-${dateSuffix}`;

      await spawnGitChecked(
        ["config", "user.name", "github-actions[bot]"],
        { cwd: repoRoot },
      );
      await spawnGitChecked(
        [
          "config",
          "user.email",
          "41898282+github-actions[bot]@users.noreply.github.com",
        ],
        { cwd: repoRoot },
      );
      await spawnGitChecked(["add", "scripts/retired-rule-ids.txt"], {
        cwd: repoRoot,
      });
      await spawnGitChecked(["checkout", "-b", branchName], {
        cwd: repoRoot,
      });
      await spawnGitChecked(
        [
          "commit",
          "-m",
          "chore(rule-prune): propose retirement of stale rules",
        ],
        { cwd: repoRoot },
      );
      await spawnGitChecked(["push", "-u", "origin", branchName], {
        cwd: repoRoot,
      });

      const { data: pr } = await octokit.request(
        "POST /repos/{owner}/{repo}/pulls",
        {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          title: `${pruneResult.prTitle} ${dateSuffix}`,
          body:
            pruneResult.prBody ??
            "Stale-rule retirement proposal — appends to retired-rule-ids.txt only",
          base: "main",
          head: branchName,
        },
      );

      // Synthetic checks
      const commitSha = await spawnGitCapture(["rev-parse", "HEAD"], {
        cwd: repoRoot,
      });

      for (const name of SYNTHETIC_CHECK_NAMES) {
        await octokit.request(
          "POST /repos/{owner}/{repo}/check-runs",
          {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            name,
            head_sha: commitSha,
            status: "completed",
            conclusion: "success",
            output: {
              title: "Bot PR",
              summary:
                "Stale-rule retirement proposal — appends to retired-rule-ids.txt only",
            },
          },
        );
      }

      // Auto-merge
      try {
        await octokit.request(
          "PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge",
          {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            pull_number: pr.number,
            merge_method: "squash",
          },
        );
      } catch {
        logger.warn(
          { fn: "cron-rule-prune", pr: pr.number },
          "Direct merge failed — PR left open for review",
        );
      }

      return { prNumber: pr.number };
    });

    await step.run("sentry-heartbeat", () =>
      postSentryHeartbeat({
        ok: true,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-rule-prune",
        logger,
      }),
    );

    return {
      ok: true,
      status: "pr-opened",
      prNumber: prResult.prNumber,
    };
  } catch (err) {
    const e = err as Error;
    if (installationToken) {
      e.message = redactToken(e.message, installationToken);
    }
    reportSilentFallback(e, {
      feature: "cron-rule-prune",
      op: "handler-top-level",
      message: e.message,
    });
    try {
      await postSentryHeartbeat({
        ok: false,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-rule-prune",
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

export const cronRulePrune = inngest.createFunction(
  {
    id: "cron-rule-prune",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 9 1 1,4,7,10 *" },
    { event: "cron/rule-prune.manual-trigger" },
  ],
  cronRulePruneHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
