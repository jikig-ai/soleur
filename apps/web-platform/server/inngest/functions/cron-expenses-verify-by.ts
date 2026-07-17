/**
 * cron-expenses-verify-by — Inngest-dispatched trigger for the scheduled
 * expenses verify_by expiry-gate GitHub Actions workflow (#6602).
 *
 * DISPATCH HYBRID: this function is the SCHEDULER only. It fires on its cron
 * schedule (weekly, Mon 08:00 UTC) and triggers the EXISTING
 * `.github/workflows/scheduled-expenses-verify-by.yml` workflow via a
 * `workflow_dispatch` API call. The GHA workflow remains the EXECUTOR — it runs
 * the deterministic `scripts/expenses-verify-by-check.sh` checker in an
 * ephemeral runner, parses the machine-readable `verify_by` markers in
 * `knowledge-base/operations/expenses.md`, and files an idempotent GitHub issue
 * only when an estimate row has outlived its verify_by date (the #6589 defect
 * class: an unverified estimate that rots past its own verification window).
 *
 * Inngest is the single scheduling substrate across the platform (ADR-033); a
 * raw GHA `schedule:` trigger is the rejected mechanism (blocked by the
 * new-scheduled-cron-prefer-inngest PreToolUse hook). This mirrors the
 * cron-domain-model-drift / cron-dev-migration-drift dispatch-hybrids.
 *
 * HARD NON-GOAL: this function does NOT run the checker in-process and does NOT
 * clone the repo. The executor only needs a checkout + bash + a GH token;
 * running it inside the Node app server would add ephemeral-clone / disk
 * management for zero benefit (the checker writes nothing — it files an issue
 * via `gh`). This function ONLY dispatches; it holds nothing but a short-lived,
 * `actions: write`-scoped GitHub App installation token.
 *
 * Liveness (Design A — cost-aware, NO Sentry cron monitor):
 *  - Scheduler liveness: `cron-inngest-cron-watchdog` + the parity-guarded
 *    `EXPECTED_CRON_FUNCTIONS` manifest keep this cron in the watchdog's purview.
 *  - Executor liveness: intentionally NOT backed by a Sentry cron monitor. A
 *    monitor seat costs $0.78/mo against the ~$7.78 PAYG headroom on the very
 *    Sentry row the sibling correction fixed (#6589) — not worth it for a
 *    low-stakes weekly advisory checker. A missed run only delays noticing an
 *    expired estimate by a week, and the workflow is on-demand runnable. This
 *    mirrors cron-dev-migration-drift (Design A), NOT domain-model-drift (B).
 *  - Dispatch error path: an Octokit `workflow_dispatch` failure is caught and
 *    reported loudly to the Sentry issues stream via `reportSilentFallback`
 *    (token redacted). A token-mint failure occurs BEFORE the try/catch and
 *    carries no token to leak — it surfaces via the Inngest sentry-correlation
 *    middleware (Layer 1) after `retries: 1`.
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

const FUNCTION_NAME = "cron-expenses-verify-by";
// The dispatches endpoint accepts the workflow FILE BASENAME as {workflow_id}
// (no numeric-ID lookup needed — see @octokit/openapi-types).
const WORKFLOW_FILE = "scheduled-expenses-verify-by.yml";
// One short-lived API call; a modest floor is plenty.
const TOKEN_MIN_LIFETIME_MS = 5 * 60 * 1000;

export async function cronExpensesVerifyByHandler({
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
      "Dispatched expenses verify_by workflow",
    );
    return { ok: true };
  } catch (err) {
    const e = err as Error;
    // Redact the minted token out of the message before it reaches Sentry,
    // preserving the original Error.name as a field (matches the
    // cron-domain-model-drift precedent).
    const redacted = new Error(redactToken(e.message, installationToken));
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: FUNCTION_NAME,
      op: "dispatch-workflow",
      message: "expenses verify_by workflow_dispatch failed",
      extra: { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
    });
    return { ok: false };
  }
}

export const cronExpensesVerifyBy = inngest.createFunction(
  {
    id: "cron-expenses-verify-by",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 8 * * 1" },
    { event: "cron/expenses-verify-by.manual-trigger" },
  ],
  cronExpensesVerifyByHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
