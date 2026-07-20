// TR9 Phase 2 E3 (#3948) — event-triggered Inngest function: ship-merge.
//
// Migrated from .github/workflows/scheduled-ship-merge.yml (deleted in
// the same commit per K13). Selects the oldest qualifying open PR, checks
// out the branch, and spawns claude-eval to run /soleur:ship --headless.
//
// Trigger: inngest.send('{"name":"ship-merge.manual-trigger","data":{}}')
// or with optional override: '{"data":{"pr_number":1234}}'
//
// ADR-033 invariants:
//   I1 — claude binary spawned INSIDE step.run (Inngest replay memoization).
//   I2 — Operator ANTHROPIC_API_KEY only; never founder BYOK.
//   I3 — AbortSignal aborts at MAX_TURN_DURATION_MS (30 min, matching GHA).
//   I4 — claude binary resolved at spawn time via filesystem checks.
//   I5 — Deterministic step.run return shapes.
//
// No Sentry cron monitor — event-triggered functions have no recurring
// schedule. Errors reported via reportSilentFallback only.

import {
  redactToken,
  mintInstallationToken,
  REPO_OWNER,
  REPO_NAME,
  type HandlerArgs,
} from "./_cron-shared";
import {
  setupEphemeralWorkspace,
  teardownEphemeralWorkspace,
  spawnClaudeEval,
  spawnSimple,
  type SpawnResult,
} from "./_cron-claude-eval-substrate";
import { inngest } from "@/server/inngest/client";
import { EXECUTION_MODEL } from "@/server/inngest/model-tiers";
import { reportSilentFallback } from "@/server/observability";

const FUNCTION_NAME = "event-ship-merge";

const TOKEN_MIN_LIFETIME_MS = 30 * 60 * 1000 + 10 * 60 * 1000;

export const MAX_TURN_DURATION_MS = 30 * 60 * 1000;

// #4993 — headless /soleur:* skill resolution (fleet fix mirroring #4987 /
// PR #4989): `--plugin-dir plugins/soleur` registers the plugin (clone's tracked tree — #5091) under
// `--print` (a bare plugins/ dir is NOT auto-discovered in headless mode), and
// `Skill`+`Task` (/soleur:ship fans out review/QA subagents) in --allowedTools
// gate skill invocation + subagent fan-out.
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

const SHIP_PROMPT = "Run /soleur:ship --headless";

const EXCLUDE_LABELS = ["ship/failed", "no-auto-ship"];
const AGE_THRESHOLD_MS = 24 * 60 * 60 * 1000;

interface EventData {
  pr_number?: number;
}

interface PrShape {
  number: number;
  created_at: string;
  draft: boolean;
  base: { ref: string };
  labels: { name: string }[];
}

type HandlerResult =
  | { ok: false; reason: string }
  | { ok: true; pr_number: number };

function buildSpawnEnv(installationToken: string): NodeJS.ProcessEnv {
  return {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    NODE_ENV: process.env.NODE_ENV,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
    GH_TOKEN: installationToken,
  };
}

export function selectQualifyingPr(
  prs: PrShape[],
  nowIso: string,
): number | null {
  const cutoff = new Date(new Date(nowIso).getTime() - AGE_THRESHOLD_MS).toISOString();

  const qualifying = prs
    .filter((pr) => {
      if (pr.draft) return false;
      if (pr.base.ref !== "main") return false;
      if (pr.created_at > cutoff) return false;
      const labelNames = pr.labels.map((l) => l.name);
      if (EXCLUDE_LABELS.some((ex) => labelNames.includes(ex))) return false;
      return true;
    })
    .sort((a, b) => a.created_at.localeCompare(b.created_at));

  return qualifying.length > 0 ? qualifying[0].number : null;
}

export async function eventShipMergeHandler({
  event,
  step,
  logger,
  runId,
  attempt,
}: HandlerArgs & { event: { data: EventData } }): Promise<HandlerResult> {
  const { data } = event;

  // --- Step 1: mint installation token ---------------------------------------
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS });
    },
  );

  // --- Step 2: select PR -----------------------------------------------------
  const prNumber = await step.run("select-pr", async () => {
    if (data.pr_number) {
      logger.info({ fn: FUNCTION_NAME }, `Override: shipping PR #${data.pr_number}`);
      return data.pr_number;
    }

    const { Octokit: OctokitCtor } = await import("@octokit/core");
    const octokit = new OctokitCtor({ auth: installationToken });

    const res = await octokit.request("GET /repos/{owner}/{repo}/pulls", {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      state: "open",
      per_page: 100,
    });

    const prs: PrShape[] = (res.data as any[]).map((pr: any) => ({
      number: pr.number,
      created_at: pr.created_at,
      draft: pr.draft,
      base: { ref: pr.base.ref },
      labels: (pr.labels || []).map((l: any) => ({ name: l.name || "" })),
    }));

    return selectQualifyingPr(prs, new Date().toISOString());
  });

  if (!prNumber) {
    logger.info({ fn: FUNCTION_NAME }, "No qualifying PRs found");
    return { ok: false, reason: "no-qualifying-prs" };
  }

  // --- Step 3: setup workspace, checkout PR branch, spawn claude-eval --------
  let ephemeralRoot: string | null = null;
  try {
    const workspace = await step.run("setup-workspace", async () => {
      return setupEphemeralWorkspace({ installationToken, cronName: FUNCTION_NAME });
    });
    ephemeralRoot = workspace.ephemeralRoot;

    await step.run("checkout-pr", async () => {
      const checkoutResult = await spawnSimple(
        "gh",
        ["pr", "checkout", String(prNumber)],
        {
          cwd: workspace.spawnCwd,
          env: {
            PATH: process.env.PATH,
            HOME: process.env.HOME,
            NODE_ENV: process.env.NODE_ENV,
            GH_TOKEN: installationToken,
          },
        },
      );
      if (checkoutResult.exitCode !== 0) {
        throw new Error(
          `gh pr checkout ${prNumber} failed (exit ${checkoutResult.exitCode})`,
        );
      }
    });

    const spawnResult = await step.run(
      "claude-eval",
      async (): Promise<SpawnResult> => {
        return spawnClaudeEval({
          spawnCwd: workspace.spawnCwd,
          installationToken,
          flags: CLAUDE_CODE_FLAGS,
          prompt: SHIP_PROMPT,
          maxTurnDurationMs: MAX_TURN_DURATION_MS,
          cronName: FUNCTION_NAME,
          buildSpawnEnv,
          logger,
          runId,
          attempt,
        });
      },
    );

    if (spawnResult.abortedByTimeout) {
      reportSilentFallback(
        new Error(`claude-eval aborted by timeout (${MAX_TURN_DURATION_MS}ms budget exceeded)`),
        {
          feature: FUNCTION_NAME,
          op: "claude-eval-timeout",
          message: "claude-eval aborted by AbortController",
          extra: { fn: FUNCTION_NAME, prNumber, durationMs: spawnResult.durationMs },
        },
      );
    }

    // --- Step 4: post-run cleanup (label ship/failed if not merged) -----------
    if (!spawnResult.ok) {
      await step.run("label-ship-failed", async () => {
        const { Octokit: OctokitCtor } = await import("@octokit/core");
        const octokit = new OctokitCtor({ auth: installationToken });

        const prRes = await octokit.request(
          "GET /repos/{owner}/{repo}/pulls/{pull_number}",
          { owner: REPO_OWNER, repo: REPO_NAME, pull_number: prNumber },
        );
        const prState = (prRes.data as any).state;

        if (prState === "open") {
          try {
            await octokit.request(
              "POST /repos/{owner}/{repo}/issues/{issue_number}/labels",
              {
                owner: REPO_OWNER,
                repo: REPO_NAME,
                issue_number: prNumber,
                labels: ["ship/failed"],
              },
            );
          } catch (err) {
            reportSilentFallback(err, {
              feature: FUNCTION_NAME,
              op: "add-ship-failed-label",
              message: "Failed to add ship/failed label",
              extra: { fn: FUNCTION_NAME, prNumber },
            });
          }

          try {
            await octokit.request(
              "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
              {
                owner: REPO_OWNER,
                repo: REPO_NAME,
                issue_number: prNumber,
                body: [
                  "**Scheduled Ship Failed**",
                  "",
                  "The automated ship-merge function failed for this PR.",
                  "",
                  "To re-queue this PR for auto-ship, remove the `ship/failed` label.",
                ].join("\n"),
              },
            );
          } catch (err) {
            reportSilentFallback(err, {
              feature: FUNCTION_NAME,
              op: "post-failure-comment",
              message: "Failed to post ship failure comment",
              extra: { fn: FUNCTION_NAME, prNumber },
            });
          }
        }
      });

      reportSilentFallback(
        new Error(`Ship-merge failed for PR #${prNumber}`),
        {
          feature: FUNCTION_NAME,
          op: "ship-merge-failure",
          message: "claude-eval exited non-zero during ship-merge",
          extra: { fn: FUNCTION_NAME, prNumber, ...spawnResult },
        },
      );
    }

    return spawnResult.ok
      ? { ok: true as const, pr_number: prNumber }
      : { ok: false as const, reason: "claude-eval-failed" };
  } catch (err) {
    const e = err as Error;
    const redactedMsg = redactToken(e.message ?? "", installationToken);
    const redacted = new Error(redactedMsg);
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: FUNCTION_NAME,
      op: "ship-merge-pipeline",
      message: "Ship-merge pipeline failed",
      extra: { fn: FUNCTION_NAME, prNumber },
    });
    return { ok: false, reason: "pipeline-error" };
  } finally {
    await teardownEphemeralWorkspace(ephemeralRoot, FUNCTION_NAME).catch((err) => {
      reportSilentFallback(err, {
        feature: FUNCTION_NAME,
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: FUNCTION_NAME, ephemeralRoot },
      });
    });
  }
}

export const eventShipMerge = inngest.createFunction(
  {
    id: "event-ship-merge",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  { event: "ship-merge.manual-trigger" },
  eventShipMergeHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
