/**
 * cron-inngest-config-drift — Inngest-dispatched trigger for the config-refresh drift
 * comparator (ADR-134, #6780, HARD-8). The off-box comparator that alarms when the dedicated
 * Inngest host's APPLIED config digest diverges from the promoted INNGEST_CONFIG_DIGEST pointer.
 *
 * DISPATCH HYBRID (same shape as cron-terraform-drift): this function is the SCHEDULER only. It
 * triggers `.github/workflows/inngest-config-drift.yml`; the GHA workflow is the
 * EXECUTOR. Why dispatch-hybrid: the comparison reads the LATEST SOLEUR_INFRA_PULL_APPLIED marker
 * from Better Stack via scripts/betterstack-query.sh, whose ClickHouse credentials
 * (BETTERSTACK_QUERY_*) live in Doppler soleur/prd_terraform — deliberately NOT on the app/Inngest
 * server (parking query creds + the isolated soleur-inngest pointer-read token on the prod host is
 * a security regression, exactly the terraform-drift rationale). So execution belongs in the
 * ephemeral GHA runner; this function holds nothing but a short-lived, actions:write-scoped GitHub
 * App installation token.
 *
 * DORMANT UNTIL THE #6178 CUTOVER (HARD-11 — the channel is not live pre-cutover). This function
 * ships EVENT-ONLY (a manual-trigger event, NO `{ cron: }` schedule) because the marker it compares
 * against (SOLEUR_INFRA_PULL_APPLIED) only flows once the host-side consumer bake rides the #6178
 * cutover, and the promoted pointer's TF applies at that cutover too. Auto-firing a comparator
 * against a channel that is not yet live would manufacture the #6536 false-alarm class the channel
 * exists to kill. The cutover adds the recurring schedule trigger + the isolated pointer-read token
 * + the inngest-config-drift Sentry monitor. Until then the comparator is exercisable ONLY on
 * demand (cron/inngest-config-drift.manual-trigger); its executor is channel-live-gated and exits
 * PENDING (green) when no pointer is promoted / no marker exists.
 *
 * HARD NON-GOAL: this function runs no comparison in-process, reads no Doppler pointer, and clones
 * no repo. It ONLY dispatches. The comparator core is apps/web-platform/infra/inngest-config-drift-compare.sh
 * (hermetically tested); the Better Stack query + pointer read live in the GHA executor.
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

const FUNCTION_NAME = "cron-inngest-config-drift";
const WORKFLOW_FILE = "inngest-config-drift.yml";
const TOKEN_MIN_LIFETIME_MS = 5 * 60 * 1000;

export async function cronInngestConfigDriftHandler({
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
      "Dispatched inngest-config-drift workflow",
    );
    return { ok: true };
  } catch (err) {
    const e = err as Error;
    const redacted = new Error(redactToken(e.message, installationToken));
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: FUNCTION_NAME,
      op: "dispatch-workflow",
      message: "inngest-config-drift workflow_dispatch failed",
      extra: { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
    });
    return { ok: false };
  }
}

export const cronInngestConfigDrift = inngest.createFunction(
  {
    id: "cron-inngest-config-drift",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  // EVENT-ONLY until the #6178 cutover (see the dormancy note above). The cutover adds the
  // `{ cron: }` schedule alongside the pointer + Sentry monitor.
  [{ event: "cron/inngest-config-drift.manual-trigger" }],
  cronInngestConfigDriftHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
