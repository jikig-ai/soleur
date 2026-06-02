/**
 * cron-main-health-monitor — Inngest-dispatched trigger for the main-branch
 * health-monitor GitHub Actions workflow.
 *
 * DISPATCH HYBRID: this function is the SCHEDULER only. It fires on its cron
 * schedule (every 6 hours on the hour UTC, ≤2-min jitter) and
 * triggers the EXISTING `.github/workflows/main-health-monitor.yml` workflow via
 * a `workflow_dispatch` API call. The GHA workflow remains the EXECUTOR — it
 * still runs the FULL test suite (`bash scripts/test-all.sh`) against `main` in
 * an ephemeral runner and files/clears a P1 `ci/main-broken` issue on failure.
 *
 * Migrated off the GHA `schedule:` trigger so Inngest is the single scheduling
 * substrate across the platform (mirrors the just-merged cron-terraform-drift
 * dispatch-hybrid).
 *
 * HARD NON-GOAL: this function does NOT run the test suite in-process and does
 * NOT clone the repo. `scripts/test-all.sh` needs the full repo checkout + the
 * toolchain; running it inside the Node app server is both a security/resource
 * regression and defeats the point (the suite must run against the runner's
 * clean `main` checkout, not the long-lived app process). The test suite stays
 * in the ephemeral GHA runner. This function ONLY dispatches; it holds nothing
 * but a short-lived, `actions: write`-scoped GitHub App installation token.
 *
 * Liveness (Design A — no own Sentry monitor):
 *  - Scheduler liveness: `cron-inngest-cron-watchdog` + the parity-guarded
 *    `EXPECTED_CRON_FUNCTIONS` manifest keep this cron in the watchdog's purview
 *    (NEW for this workflow — it had no scheduler-liveness alerting under raw
 *    GHA `schedule:`).
 *  - End-to-end liveness: if the dispatch never reaches the runner, the suite
 *    does not run and a broken `main` goes un-issued — the existing
 *    operator-visible absence signal this workflow already relies on.
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

const FUNCTION_NAME = "cron-main-health-monitor";
// The dispatches endpoint accepts the workflow FILE BASENAME as {workflow_id}
// (no numeric-ID lookup needed — see @octokit/openapi-types).
const WORKFLOW_FILE = "main-health-monitor.yml";
// One short-lived API call; a modest floor is plenty.
const TOKEN_MIN_LIFETIME_MS = 5 * 60 * 1000;

export async function cronMainHealthMonitorHandler({
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
      "Dispatched main-health-monitor workflow",
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
      message: "main-health-monitor workflow_dispatch failed",
      extra: { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
    });
    return { ok: false };
  }
}

export const cronMainHealthMonitor = inngest.createFunction(
  {
    id: "cron-main-health-monitor",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 */6 * * *" },
    { event: "cron/main-health-monitor.manual-trigger" },
  ],
  cronMainHealthMonitorHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
