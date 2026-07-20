// TR9 Phase 2 E2 (#3948) — oneshot Inngest function: re-check #4217
// template auth calibration at T+30d.
//
// Migrated from .github/workflows/scheduled-recheck-4217-calibration.yml
// (deleted in the same commit per K13). Fires once when event is sent,
// fetches the task spec from the referenced GitHub issue comment, and
// spawns claude-eval to execute the calibration check.
//
// ADR-033 invariants: I1-I6 (same as oneshot-f2-defer-gate-review.ts).
//
// No Sentry cron monitor — oneshots have no recurring schedule. Errors
// reported via reportSilentFallback only.

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
  type SpawnResult,
} from "./_cron-claude-eval-substrate";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";

const FUNCTION_NAME = "oneshot-recheck-4217-calibration";

const TOKEN_MIN_LIFETIME_MS = 20 * 60 * 1000 + 10 * 60 * 1000;

export const MAX_TURN_DURATION_MS = 20 * 60 * 1000;

const CLAUDE_CODE_FLAGS = [
  "--print",
  "--max-turns",
  "25",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep",
  "--",
];

interface EventData {
  issue: number;
  comment_id: number;
  expected_date: string;
  expectedAuthor: string;
  expectedCreatedAt: string;
  date_override?: string;
  actor?: "platform";
}

type HandlerResult =
  | { ok: false; reason: string }
  | { ok: true };

function buildSpawnEnv(installationToken: string): NodeJS.ProcessEnv {
  return {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    NODE_ENV: process.env.NODE_ENV,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
    GH_TOKEN: installationToken,
  };
}

export async function oneshotRecheck4217CalibrationHandler({
  event,
  step,
  logger,
  runId,
  attempt,
}: HandlerArgs & { event: { data: EventData } }): Promise<HandlerResult> {
  const { data } = event;

  // --- D3 date guard ---------------------------------------------------------
  if (data.date_override !== undefined && !/^\d{4}-\d{2}-\d{2}$/.test(data.date_override)) {
    reportSilentFallback(
      new Error(`Invalid date_override format: ${JSON.stringify(data.date_override)}`),
      {
        feature: FUNCTION_NAME,
        op: "date-override-validation",
        message: "date_override must be YYYY-MM-DD",
        extra: { fn: FUNCTION_NAME, raw: String(data.date_override).slice(0, 20) },
      },
    );
    return { ok: false, reason: "invalid-date-override" };
  }
  const today = data.date_override ?? new Date().toISOString().slice(0, 10);
  if (today !== data.expected_date) {
    reportSilentFallback(
      new Error(`D3 date guard: today=${today} !== expected=${data.expected_date}`),
      {
        feature: FUNCTION_NAME,
        op: "date-guard",
        message: "D3 date guard rejected — wrong execution date",
        extra: { fn: FUNCTION_NAME, today, expected: data.expected_date },
      },
    );
    return { ok: false, reason: "date-guard" };
  }

  // --- Step 1: mint installation token ---------------------------------------
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS });
    },
  );

  // --- Step 2: preflight checks (D5 author + immutability pins) --------------
  const preflight = await step.run("preflight-checks", async () => {
    const { Octokit: OctokitCtor } = await import("@octokit/core");
    const octokit = new OctokitCtor({ auth: installationToken });

    const commentRes = await octokit.request(
      "GET /repos/{owner}/{repo}/issues/comments/{comment_id}",
      {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        comment_id: data.comment_id,
      },
    );
    const comment = commentRes.data as any;

    const actualAuthor = comment.user?.login;
    if (actualAuthor !== data.expectedAuthor) {
      return { ok: false as const, reason: "author-mismatch", actualAuthor };
    }

    const createdAt = comment.created_at;
    const updatedAt = comment.updated_at;
    if (createdAt !== data.expectedCreatedAt) {
      return { ok: false as const, reason: "created-at-mismatch", createdAt };
    }
    if (createdAt !== updatedAt) {
      return { ok: false as const, reason: "comment-mutated", createdAt, updatedAt };
    }

    const body: string = comment.body ?? "";
    if (!body.trim()) {
      return { ok: false as const, reason: "empty-comment-body" };
    }

    return { ok: true as const, body };
  });

  if (!preflight.ok) {
    reportSilentFallback(
      new Error(`Preflight failed: ${preflight.reason}`),
      {
        feature: FUNCTION_NAME,
        op: "preflight-checks",
        message: `Preflight check failed: ${preflight.reason}`,
        extra: { fn: FUNCTION_NAME, ...preflight },
      },
    );
    return { ok: false, reason: preflight.reason };
  }

  // --- Step 3: setup ephemeral workspace + claude-eval -----------------------
  let ephemeralRoot: string | null = null;
  try {
    const workspace = await step.run("setup-workspace", async () => {
      return setupEphemeralWorkspace({ installationToken, cronName: FUNCTION_NAME });
    });
    ephemeralRoot = workspace.ephemeralRoot;

    const spawnResult = await step.run(
      "claude-eval",
      async (): Promise<SpawnResult> => {
        return spawnClaudeEval({
          spawnCwd: workspace.spawnCwd,
          installationToken,
          flags: CLAUDE_CODE_FLAGS,
          prompt: preflight.body,
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
          extra: { fn: FUNCTION_NAME, durationMs: spawnResult.durationMs },
        },
      );
    }

    if (!spawnResult.ok) {
      reportSilentFallback(
        new Error(`claude-eval exited with code ${spawnResult.exitCode}`),
        {
          feature: FUNCTION_NAME,
          op: "claude-eval-failure",
          message: "claude-eval exited non-zero",
          extra: { fn: FUNCTION_NAME, ...spawnResult },
        },
      );
    }

    return spawnResult.ok ? { ok: true } : { ok: false, reason: "claude-eval-failed" };
  } catch (err) {
    const e = err as Error;
    const redactedMsg = redactToken(e.message ?? "", installationToken);
    const redacted = new Error(redactedMsg);
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: FUNCTION_NAME,
      op: "claude-eval-pipeline",
      message: "Oneshot pipeline failed",
      extra: { fn: FUNCTION_NAME },
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

export const oneshotRecheck4217Calibration = inngest.createFunction(
  {
    id: "oneshot-recheck-4217-calibration",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  { event: "oneshot/recheck-4217-calibration.fire" },
  oneshotRecheck4217CalibrationHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
