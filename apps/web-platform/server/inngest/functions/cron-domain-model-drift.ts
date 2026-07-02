/**
 * cron-domain-model-drift — Inngest-dispatched trigger for the scheduled
 * domain-model-drift GitHub Actions workflow.
 *
 * DISPATCH HYBRID: this function is the SCHEDULER only. It fires on its cron
 * schedule (weekly, Mon 08:00 UTC) and triggers the EXISTING
 * `.github/workflows/scheduled-domain-model-drift.yml` workflow via a
 * `workflow_dispatch` API call. The GHA workflow remains the EXECUTOR — it
 * still runs the deterministic `scripts/domain-model-drift.sh drift` analyzer
 * in an ephemeral runner, parses the stale-citation sub-count, and files an
 * idempotent GitHub issue only when the register cites an unresolvable source
 * (stale > 0).
 *
 * Inngest is the single scheduling substrate across the platform (ADR-033); a
 * raw GHA `schedule:` trigger is the rejected mechanism (blocked by the
 * new-scheduled-cron-prefer-inngest PreToolUse hook). This mirrors the
 * cron-dev-migration-drift / cron-terraform-drift dispatch-hybrids.
 *
 * HARD NON-GOAL: this function does NOT run the drift analyzer in-process and
 * does NOT clone the repo. The executor only needs a checkout + bash + jq + a
 * GH token; running it inside the Node app server would add ephemeral-clone /
 * disk management for zero benefit (the analyzer writes nothing — it files an
 * issue via `gh`). This function ONLY dispatches; it holds nothing but a
 * short-lived, `actions: write`-scoped GitHub App installation token.
 *
 * Liveness:
 *  - Scheduler liveness: `cron-inngest-cron-watchdog` + the parity-guarded
 *    `EXPECTED_CRON_FUNCTIONS` manifest keep this cron in the watchdog's purview.
 *  - Executor liveness: the `scheduled-domain-model-drift` Sentry cron monitor
 *    (infra/sentry/cron-monitors.tf) receives a heartbeat each executor run
 *    (ok on rc 0/1, error on rc 2/3 or empty-stale anomaly). A weekly-cadence
 *    cron's absence-based liveness is too weak on its own, so this workflow
 *    provisions its own monitor (unlike Design A dev-migration-drift).
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

const FUNCTION_NAME = "cron-domain-model-drift";
// The dispatches endpoint accepts the workflow FILE BASENAME as {workflow_id}
// (no numeric-ID lookup needed — see @octokit/openapi-types).
const WORKFLOW_FILE = "scheduled-domain-model-drift.yml";
// One short-lived API call; a modest floor is plenty.
const TOKEN_MIN_LIFETIME_MS = 5 * 60 * 1000;

export async function cronDomainModelDriftHandler({
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
      "Dispatched domain-model-drift workflow",
    );
    return { ok: true };
  } catch (err) {
    const e = err as Error;
    // Redact the minted token out of the message before it reaches Sentry,
    // preserving the original Error.name as a field (matches the
    // cron-dev-migration-drift precedent).
    const redacted = new Error(redactToken(e.message, installationToken));
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: FUNCTION_NAME,
      op: "dispatch-workflow",
      message: "domain-model-drift workflow_dispatch failed",
      extra: { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
    });
    return { ok: false };
  }
}

export const cronDomainModelDrift = inngest.createFunction(
  {
    id: "cron-domain-model-drift",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 8 * * 1" },
    { event: "cron/domain-model-drift.manual-trigger" },
  ],
  cronDomainModelDriftHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
