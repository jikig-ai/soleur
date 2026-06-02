/**
 * cron-dev-migration-drift — Inngest-dispatched trigger for the scheduled
 * dev-migration-drift-probe GitHub Actions workflow.
 *
 * DISPATCH HYBRID: this function is the SCHEDULER only. It fires on its cron
 * schedule (every 6 hours at HH:15 UTC, ≤2-min jitter) and
 * triggers the EXISTING `.github/workflows/scheduled-dev-migration-drift.yml`
 * workflow via a `workflow_dispatch` API call. The GHA workflow remains the
 * EXECUTOR — it still runs the `dev-migration-drift-probe` composite action in
 * an ephemeral runner with the Doppler `DOPPLER_TOKEN_DEV_SCHEDULED` credential
 * and surfaces residual `_schema_migrations` drift via `::warning::`
 * annotations.
 *
 * Migrated off the GHA `schedule:` trigger so Inngest is the single scheduling
 * substrate across the platform (mirrors the just-merged cron-terraform-drift
 * dispatch-hybrid). The probe's Doppler dev credential must NOT be parked on
 * the app server, so execution stays in the ephemeral GHA runner.
 *
 * HARD NON-GOAL: this function does NOT run the migration-drift probe in-process
 * and does NOT clone the repo. The composite action needs the Doppler dev token
 * + the migration tooling; running it inside the Node app server would park that
 * credential on the prod host — a security/complexity regression. The probe
 * stays in the ephemeral GHA runner. This function ONLY dispatches; it holds
 * nothing but a short-lived, `actions: write`-scoped GitHub App installation
 * token.
 *
 * Liveness (Design A — no own Sentry monitor):
 *  - Scheduler liveness: `cron-inngest-cron-watchdog` + the parity-guarded
 *    `EXPECTED_CRON_FUNCTIONS` manifest keep this cron in the watchdog's purview
 *    (NEW for this workflow — it had no scheduler-liveness alerting under raw
 *    GHA `schedule:`).
 *  - End-to-end liveness: if the dispatch never reaches the runner, the probe
 *    does not run and drift goes un-annotated — the existing operator-visible
 *    absence signal these workflows already rely on.
 *  - Dispatch error path: a token-mint / Octokit failure is reported loudly to
 *    the Sentry issues stream via `reportSilentFallback` (token redacted).
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

const FUNCTION_NAME = "cron-dev-migration-drift";
// The dispatches endpoint accepts the workflow FILE BASENAME as {workflow_id}
// (no numeric-ID lookup needed — see @octokit/openapi-types).
const WORKFLOW_FILE = "scheduled-dev-migration-drift.yml";
// One short-lived API call; a modest floor is plenty.
const TOKEN_MIN_LIFETIME_MS = 5 * 60 * 1000;

export async function cronDevMigrationDriftHandler({
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
      "Dispatched dev-migration-drift workflow",
    );
    return { ok: true };
  } catch (err) {
    const e = err as Error;
    // Redact the minted token out of the message before it reaches Sentry,
    // preserving the original Error.name as a field (matches the
    // cron-weekly-analytics precedent).
    const redacted = new Error(redactToken(e.message, installationToken));
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: FUNCTION_NAME,
      op: "dispatch-workflow",
      message: "dev-migration-drift workflow_dispatch failed",
      extra: { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
    });
    return { ok: false };
  }
}

export const cronDevMigrationDrift = inngest.createFunction(
  {
    id: "cron-dev-migration-drift",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "15 */6 * * *" },
    { event: "cron/dev-migration-drift.manual-trigger" },
  ],
  cronDevMigrationDriftHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
