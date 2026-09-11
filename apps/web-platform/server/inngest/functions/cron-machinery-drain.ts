/**
 * cron-machinery-drain — weekly net-negative drain + issue-flow measurement.
 *
 * WHY A DISPATCHER AND NOT THE WORK ITSELF. ADR-033 makes Inngest the single
 * scheduling substrate, so the schedule lives here; but the work is an agent
 * pipeline that cannot run inside the Inngest runtime, so this function only
 * dispatches `scheduled-machinery-drain.yml` (which carries `workflow_dispatch:
 * {}` and no cron block, keeping `new-scheduled-cron-prefer-inngest.sh`
 * allowing the write without reaching for its override hatch). Nine sibling
 * crons use exactly this shape.
 *
 * WHY WEEKLY AND WHY IT MATTERS. `net-issue-flow.sh` is per-PR net-ZERO:
 * perfectly enforced, it holds the backlog at its current size forever.
 * Measured 2026-09-10, the repo ran ~2 filed per 1 closed every week without
 * exception. A cadence with a closing floor is the only lever here that
 * REDUCES rather than holds.
 */
import { inngest } from "@/server/inngest/client";
import {
  type HandlerArgs,
  mintInstallationToken,
  redactToken,
  REPO_NAME,
  REPO_OWNER,
} from "./_cron-shared";
import { reportSilentFallback } from "@/server/observability";

const FUNCTION_NAME = "cron-machinery-drain";
// The dispatches endpoint accepts the workflow FILE BASENAME as {workflow_id}.
const WORKFLOW_FILE = "scheduled-machinery-drain.yml";
const TOKEN_MIN_LIFETIME_MS = 5 * 60 * 1000;

export async function cronMachineryDrainHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean }> {
  const installationToken = await step.run(
    "mint-installation-token",
    async () =>
      mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS }),
  );

  try {
    await step.run("dispatch-workflow", async () => {
      const { Octokit } = await import("@octokit/core");
      const octokit = new Octokit({ auth: installationToken });
      await octokit.request(
        "POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches",
        {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          workflow_id: WORKFLOW_FILE,
          ref: "main",
        },
      );
    });

    logger.info(
      { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
      "Dispatched machinery-drain workflow",
    );
    return { ok: true };
  } catch (err) {
    const e = err as Error;
    // Redact the minted token before it reaches Sentry, preserving Error.name.
    const redacted = new Error(redactToken(e.message, installationToken));
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: FUNCTION_NAME,
      op: "dispatch-workflow",
      message: "machinery-drain workflow_dispatch failed",
      extra: { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
    });
    return { ok: false };
  }
}

export const cronMachineryDrain = inngest.createFunction(
  {
    id: "cron-machinery-drain",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    // Mondays 09:00 UTC — the measurement lands before the operator's week.
    { cron: "0 9 * * 1" },
    { event: "cron/machinery-drain.manual-trigger" },
  ],
  cronMachineryDrainHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
