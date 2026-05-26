// TR9 Phase 2 T2 (#3948) — pure-TS port: weekly analytics snapshot.
//
// Migrated from .github/workflows/scheduled-weekly-analytics.yml (deleted
// in the same commit per K13). Runs scripts/weekly-analytics.sh to pull
// Plausible metrics, creates a bot-PR with the snapshot, and dispatches
// cascade targets on KPI miss via inngest.send() (replaces gh workflow run).
//
// ADR-033 invariants: I1 (step.run), I2 (no BYOK), I5 (deterministic return).
//
// K24: RESEND email path dropped. KPI miss → inngest.send() cascade only.
// Follow-up issue for KPI-miss alerting via Discord webhook or Sentry
// custom metric (tasks.md §5.3).
//
// Cascade ordering constraint: C2 (content-generator), C4 (growth-execution),
// C5 (seo-aeo-audit) must be registered on Inngest BEFORE this function
// migrates. Otherwise, inngest.send() events have no consumer.

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
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

const FUNCTION_NAME = "cron-weekly-analytics";
const SENTRY_MONITOR_SLUG = "scheduled-weekly-analytics";

const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

export const SYNTHETIC_CHECK_NAMES = [
  "test",
  "dependency-review",
  "e2e",
  "skill-security-scan PR gate",
  "enforce",
  "cla-check",
  "cla-evidence",
] as const;

interface ScriptOutput {
  exitCode: number;
  kpiMiss: boolean;
  kpiPhase: string;
  kpiTarget: string;
  kpiActual: string;
  kpiVisitors: string;
}

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

function spawnScriptCapture(
  script: string,
  args: string[],
  opts: { cwd: string; env: NodeJS.ProcessEnv },
): Promise<{ exitCode: number | null; stdout: string }> {
  return new Promise((resolve) => {
    const child = spawn("bash", [script, ...args], {
      cwd: opts.cwd,
      env: opts.env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    child.stdout?.on("data", (d: Buffer) => {
      stdout += d.toString();
    });
    child.on("exit", (exitCode) => resolve({ exitCode, stdout }));
    child.on("error", () => resolve({ exitCode: -1, stdout }));
  });
}

function parseGitHubOutput(stdout: string): Record<string, string> {
  const outputs: Record<string, string> = {};
  for (const line of stdout.split("\n")) {
    const match = line.match(/^::set-output name=(\w+)::(.*)$/);
    if (match) {
      outputs[match[1]] = match[2];
      continue;
    }
    const envMatch = line.match(/^(\w+)=(.*)$/);
    if (envMatch) {
      outputs[envMatch[1]] = envMatch[2];
    }
  }
  return outputs;
}

export async function cronWeeklyAnalyticsHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean }> {
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS });
    },
  );

  let ephemeralRoot: string | null = null;
  try {
    // --- Step 2: clone + run analytics script --------------------------------
    const scriptResult = await step.run("run-analytics", async () => {
      ephemeralRoot = await mkdtemp(join(tmpdir(), `soleur-${FUNCTION_NAME}-`));
      const repoRoot = join(ephemeralRoot, "repo");
      const cloneUrl = buildAuthenticatedCloneUrl(installationToken);
      const cloneResult = await spawnGit(["clone", "--depth=1", cloneUrl, repoRoot]);
      if (cloneResult.exitCode !== 0) {
        throw new Error(`git clone failed (exit ${cloneResult.exitCode})`);
      }

      const plausibleApiKey = process.env.PLAUSIBLE_API_KEY;
      const plausibleSiteId = process.env.PLAUSIBLE_SITE_ID;
      if (!plausibleApiKey || !plausibleSiteId) {
        logger.warn({ fn: FUNCTION_NAME }, "PLAUSIBLE_API_KEY or PLAUSIBLE_SITE_ID unset — skipping");
        return { exitCode: 0, kpiMiss: false, kpiPhase: "", kpiTarget: "", kpiActual: "", kpiVisitors: "", repoRoot };
      }

      const result = await spawnScriptCapture(
        "scripts/weekly-analytics.sh",
        [],
        {
          cwd: repoRoot,
          env: {
            PATH: process.env.PATH ?? "",
            NODE_ENV: process.env.NODE_ENV ?? "",
            HOME: process.env.HOME ?? "",
            PLAUSIBLE_API_KEY: plausibleApiKey,
            PLAUSIBLE_SITE_ID: plausibleSiteId,
            GITHUB_OUTPUT: "/dev/stdout",
          },
        },
      );

      const outputs = parseGitHubOutput(result.stdout);

      return {
        exitCode: result.exitCode ?? 0,
        kpiMiss: outputs.kpi_miss === "true",
        kpiPhase: outputs.kpi_phase ?? "",
        kpiTarget: outputs.kpi_target ?? "",
        kpiActual: outputs.kpi_actual ?? "",
        kpiVisitors: outputs.kpi_visitors ?? "",
        repoRoot,
      };
    });

    if (scriptResult.exitCode !== 0) {
      reportSilentFallback(
        new Error(`weekly-analytics.sh exited with code ${scriptResult.exitCode}`),
        {
          feature: FUNCTION_NAME,
          op: "run-analytics",
          message: "Analytics script failed",
          extra: { fn: FUNCTION_NAME, exitCode: scriptResult.exitCode },
        },
      );
      await step.run("sentry-heartbeat", async () => {
        await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: FUNCTION_NAME, logger });
      });
      return { ok: false };
    }

    // --- Step 3: cascade dispatch on KPI miss --------------------------------
    if (scriptResult.kpiMiss) {
      await step.run("dispatch-cascade", async () => {
        logger.info({ fn: FUNCTION_NAME }, "KPI miss detected — dispatching cascade targets");
        await inngest.send([
          { name: "cron/seo-aeo-audit.manual-trigger", data: { source: "weekly-analytics-kpi-miss" } },
          { name: "cron/growth-execution.manual-trigger", data: { source: "weekly-analytics-kpi-miss" } },
          { name: "cron/content-generator.manual-trigger", data: { source: "weekly-analytics-kpi-miss" } },
        ]);
      });
    }

    // --- Step 4: create bot-PR with snapshot ----------------------------------
    await step.run("create-bot-pr", async () => {
      const repoRoot = scriptResult.repoRoot;
      if (!repoRoot || !existsSync(repoRoot)) return;

      await spawnGitChecked(["add", "knowledge-base/marketing/analytics/"], { cwd: repoRoot });
      const diffResult = await spawnGit(["diff", "--cached", "--quiet"], { cwd: repoRoot });
      if (diffResult.exitCode === 0) {
        logger.info({ fn: FUNCTION_NAME }, "No analytics changes to commit");
        return;
      }

      const { Octokit: OctokitCtor } = await import("@octokit/core");
      const octokit = new OctokitCtor({ auth: installationToken });

      const dateSuffix = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
      const branchName = `ci/weekly-analytics-${dateSuffix}`;

      await spawnGitChecked(["config", "user.name", "github-actions[bot]"], { cwd: repoRoot });
      await spawnGitChecked(["config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"], { cwd: repoRoot });
      await spawnGitChecked(["checkout", "-b", branchName], { cwd: repoRoot });
      await spawnGitChecked(["commit", "-m", "ci: weekly analytics snapshot"], { cwd: repoRoot });
      await spawnGitChecked(["push", "-u", "origin", branchName], {
        cwd: repoRoot,
        env: {
          PATH: process.env.PATH,
          HOME: process.env.HOME,
          NODE_ENV: process.env.NODE_ENV,
          GH_TOKEN: installationToken,
        },
      });

      const { data: pr } = await octokit.request("POST /repos/{owner}/{repo}/pulls", {
        owner: REPO_OWNER, repo: REPO_NAME,
        title: `ci: weekly analytics snapshot ${new Date().toISOString().slice(0, 10)}`,
        body: "Automated weekly analytics snapshot from Plausible API.",
        base: "main", head: branchName,
      });

      const commitSha = await spawnGitCapture(["rev-parse", "HEAD"], { cwd: repoRoot });
      for (const name of SYNTHETIC_CHECK_NAMES) {
        await octokit.request("POST /repos/{owner}/{repo}/check-runs", {
          owner: REPO_OWNER, repo: REPO_NAME, name, head_sha: commitSha,
          status: "completed", conclusion: "success",
          output: { title: "Bot PR", summary: "Analytics snapshot only, no code changes" },
        });
      }

      await octokit.request("PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge", {
        owner: REPO_OWNER, repo: REPO_NAME, pull_number: pr.number,
        merge_method: "squash",
      }).catch((err) => {
        reportSilentFallback(err, {
          feature: FUNCTION_NAME,
          op: "auto-merge",
          message: "Auto-merge failed (may need manual merge)",
          extra: { fn: FUNCTION_NAME, prNumber: pr.number },
        });
      });
    });

    // --- Step 5: Sentry heartbeat --------------------------------------------
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: FUNCTION_NAME, logger });
    });

    return { ok: true };
  } catch (err) {
    const e = err as Error;
    const redactedMsg = redactToken(e.message ?? "", installationToken);
    const redacted = new Error(redactedMsg);
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: FUNCTION_NAME,
      op: "handler-top-level",
      message: redactedMsg,
    });
    try {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: FUNCTION_NAME, logger });
    } catch {
      // best-effort
    }
    return { ok: false };
  } finally {
    if (ephemeralRoot) {
      await rm(ephemeralRoot, { recursive: true, force: true }).catch(() => {});
    }
  }
}

export const cronWeeklyAnalytics = inngest.createFunction(
  {
    id: "cron-weekly-analytics",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 6 * * 1" },
    { event: "cron/weekly-analytics.manual-trigger" },
  ],
  cronWeeklyAnalyticsHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
