/**
 * cron-review-reminder — Inngest-dispatched trigger for the review-reminder
 * GitHub Actions workflow.
 *
 * DISPATCH HYBRID: this function is the SCHEDULER only. It fires on
 * `{ cron: "0 0 1 * *" }` (monthly, 1st at 00:00 UTC) and triggers the EXISTING
 * `.github/workflows/review-reminder.yml` workflow via a `workflow_dispatch` API
 * call. The GHA workflow remains the EXECUTOR — it still walks the repo for
 * `review_cadence` frontmatter and files reminder issues for due reviews.
 *
 * NO `inputs` are passed on dispatch. The workflow's `workflow_dispatch` declares
 * an OPTIONAL `date_override` input (kept for manual testing); when unset — as on
 * this scheduled dispatch — the workflow defaults `today` to `date -u +%Y-%m-%d`.
 * Omitting `inputs` is therefore equivalent to the old `schedule:` behavior.
 *
 * Migrated off the GHA `schedule:` trigger so Inngest is the single scheduling
 * substrate across the platform (mirrors the just-merged cron-terraform-drift
 * dispatch-hybrid).
 *
 * HARD NON-GOAL: this function does NOT walk the repo in-process and does NOT
 * clone the repo. The repo-walk needs the full checkout; running it inside the
 * Node app server is a complexity regression with no benefit. The repo-walk
 * stays in the ephemeral GHA runner. This function ONLY dispatches; it holds
 * nothing but a short-lived, `actions: write`-scoped GitHub App installation
 * token.
 *
 * Liveness (Design A — no own Sentry monitor):
 *  - Scheduler liveness: `cron-inngest-cron-watchdog` + the parity-guarded
 *    `EXPECTED_CRON_FUNCTIONS` manifest keep this cron in the watchdog's purview
 *    (NEW for this workflow — it had no scheduler-liveness alerting under raw
 *    GHA `schedule:`).
 *  - End-to-end liveness: if the dispatch never reaches the runner, no
 *    review-reminder issues are filed in the window — the existing
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

const FUNCTION_NAME = "cron-review-reminder";
// The dispatches endpoint accepts the workflow FILE BASENAME as {workflow_id}
// (no numeric-ID lookup needed — see @octokit/openapi-types).
const WORKFLOW_FILE = "review-reminder.yml";
// One short-lived API call; a modest floor is plenty.
const TOKEN_MIN_LIFETIME_MS = 5 * 60 * 1000;

export async function cronReviewReminderHandler({
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
      // No `inputs`: the workflow defaults `today` to the current UTC date when
      // `date_override` is unset, matching the old scheduled behavior.
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
      "Dispatched review-reminder workflow",
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
      message: "review-reminder workflow_dispatch failed",
      extra: { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
    });
    return { ok: false };
  }
}

export const cronReviewReminder = inngest.createFunction(
  {
    id: "cron-review-reminder",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 0 1 * *" },
    { event: "cron/review-reminder.manual-trigger" },
  ],
  cronReviewReminderHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
