/**
 * cron-sentry-alert-drift — Inngest-dispatched trigger for the
 * `scheduled-sentry-alert-drift` GitHub Actions workflow (#7650 §2.9, AC22).
 *
 * WHAT THE WORKFLOW IT DISPATCHES IS FOR. The 27 Sentry rules adopted as
 * `sentry_alert` in #7650 Phase 2 can go dark WEEKS after the adopting apply:
 * renamed in the UI, muted, rebound to a different detector, or their
 * `tagged_event` key edited. Each of those leaves the rule present and the
 * `terraform plan` clean while it matches nothing and pages nobody. The
 * workflow makes one read-only GET against the non-deprecated org workflows
 * endpoint and diffs all 27 field-by-field against the committed capture.
 *
 * DISPATCH HYBRID, same shape and same reasoning as `cron-terraform-drift`:
 * this function is the SCHEDULER only. Execution stays in the ephemeral GHA
 * runner because it needs the `SENTRY_IAC_AUTH_TOKEN` repository secret, which
 * must not be parked on the app server. This function holds nothing but a
 * short-lived, `actions: write`-scoped GitHub App installation token.
 *
 * DAILY, not twice-daily. The window this closes is "a rule silently stopped
 * matching", whose cost accrues only when an incident happens to occur inside
 * it; halving a one-day window does not halve that risk, and each run is a
 * write-free API call against a vendor whose alert-rule family is already under
 * brownout pressure. 07:15 UTC deliberately avoids `cron-terraform-drift`'s
 * 06:00 fire so two Sentry-touching jobs do not stack.
 *
 * Liveness (Design A — no own Sentry monitor):
 *  - Scheduler liveness: `cron-inngest-cron-watchdog` plus the parity-guarded
 *    `EXPECTED_CRON_FUNCTIONS` manifest keep this cron in the watchdog's purview.
 *  - Dispatch error path: a token-mint / Octokit failure is reported loudly to
 *    the Sentry issues stream via `reportSilentFallback` (token redacted).
 *  - NOT covered yet: "the dispatch was accepted and the runner never ran". The
 *    workflow carries no `sentry-heartbeat` step because that needs a
 *    `sentry_cron_monitor` resource, and adding one to the Sentry root in the
 *    adoption PR would plan `1 to add` — which AC2 forbids. It is filed as a
 *    follow-up (#7834) to add once the adoption has applied. Stated here rather than
 *    left for a reader to infer from the absence of a step.
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

const FUNCTION_NAME = "cron-sentry-alert-drift";
// The dispatches endpoint accepts the workflow FILE BASENAME as {workflow_id}
// (no numeric-ID lookup needed — see @octokit/openapi-types).
const WORKFLOW_FILE = "scheduled-sentry-alert-drift.yml";
// One short-lived API call; a modest floor is plenty.
const TOKEN_MIN_LIFETIME_MS = 5 * 60 * 1000;

export async function cronSentryAlertDriftHandler({
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
      "Dispatched sentry-alert-drift workflow",
    );
    return { ok: true };
  } catch (err) {
    const e = err as Error;
    // Redact the minted token out of the message before it reaches Sentry,
    // preserving the original Error.name as a field.
    const redacted = new Error(redactToken(e.message, installationToken));
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: FUNCTION_NAME,
      op: "dispatch-workflow",
      message: "sentry-alert-drift workflow_dispatch failed",
      extra: { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
    });
    return { ok: false };
  }
}

export const cronSentryAlertDrift = inngest.createFunction(
  {
    id: "cron-sentry-alert-drift",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "15 7 * * *" },
    { event: "cron/sentry-alert-drift.manual-trigger" },
  ],
  cronSentryAlertDriftHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
