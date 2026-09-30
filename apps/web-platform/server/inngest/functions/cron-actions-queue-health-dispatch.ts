/**
 * cron-actions-queue-health-dispatch — Inngest-dispatched trigger for the
 * GitHub Actions queue-health monitor workflow (#9273).
 *
 * DISPATCH HYBRID: this function is the SCHEDULER only. It fires on its cron
 * schedule (every 30 minutes, ≤2-min jitter) and triggers
 * `.github/workflows/scheduled-actions-queue-health.yml` via a
 * `workflow_dispatch` API call. The GHA workflow remains the EXECUTOR — it
 * runs the extracted, unit-tested probe at scripts/actions-queue-health.sh in
 * an ephemeral runner and posts the terminal `scheduled-actions-queue-health`
 * Sentry heartbeat.
 *
 * WHY NOT `schedule:`-only — the workflow's own every-30-minutes cron is a
 * FALLBACK, kept byte-identical for the parity gates. GHA `schedule:` delivery
 * was measured degrading to ~4 fires/day under org load on 2026-09-29→30:
 * every deferred slot registered a `missed` check-in (~47 pages/day) while the
 * probe's verdict was HEALTHY whenever it landed. Deferral is not starvation,
 * and a monitor that pages on scheduler jitter trains the operator to ignore
 * the one monitor that catches merge-blocking runner starvation.
 *
 * WHY INNGEST DISPATCH IS ELIGIBLE HERE (the self-reference objection is
 * answered by separating trigger delivery from execution substrate): the
 * dispatch only POSTs `workflow_dispatch` — it needs the Inngest scheduler +
 * GitHub REST, NO runner — while the executor still lands in the measured
 * runner pool, preserving the self-referential starvation signal: if the pool
 * is so starved the dispatched probe cannot get a runner, no check-in arrives
 * and the monitor pages. The anti-circularity corollary passes: if the checked
 * thing (runner assignment) fails completely, the trigger still fires.
 * (Residual, accepted: during an Inngest-substrate outage the `schedule:`
 * fallback alone delivers ~4×/day — an Inngest outage is itself paged by
 * `scheduled_inngest_health`, and the missed check-ins in that window stay
 * loud rather than silent.)
 *
 * HARD NON-GOAL: this function does NOT probe the runner queue — the probe's
 * `actions: read` + `issues: write` grants stay in the ephemeral GHA runner.
 * This function ONLY dispatches; it holds nothing but a short-lived,
 * `actions: write`-scoped GitHub App installation token bounded to this repo.
 *
 * Liveness:
 *  - Scheduler liveness: `cron-inngest-cron-watchdog` + the parity-guarded
 *    `EXPECTED_CRON_FUNCTIONS` manifest keep this cron in the watchdog's
 *    purview.
 *  - End-to-end liveness: if the dispatch never reaches a runner, no GHA
 *    heartbeat arrives and the `scheduled-actions-queue-health` Sentry
 *    monitor goes red within its 60-min margin.
 *  - Dispatch error path: an Octokit failure inside `dispatch-workflow` is
 *    reported loudly to the Sentry issues stream via `reportSilentFallback`
 *    (token redacted). A TOKEN-MINT failure is outside the try — it
 *    propagates, exhausts `retries: 1`, and is captured by the Inngest
 *    sentry-correlation middleware instead, tagged `inngest.fn_id`.
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

const FUNCTION_NAME = "cron-actions-queue-health-dispatch";
// The dispatches endpoint accepts the workflow FILE BASENAME as {workflow_id}
// (no numeric-ID lookup needed — see @octokit/openapi-types).
const WORKFLOW_FILE = "scheduled-actions-queue-health.yml";
// One short-lived API call; a modest floor is plenty.
const TOKEN_MIN_LIFETIME_MS = 5 * 60 * 1000;

export async function cronActionsQueueHealthDispatchHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean }> {
  const installationToken = await step.run(
    "mint-installation-token",
    async () =>
      mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
        // Least-privilege: the only call is the workflow_dispatch POST, which
        // needs actions:write and nothing else (hr-github-app-auth-not-pat +
        // the #5046 narrowed-token precedent). repositories pins the token to
        // this repo so a leaked token cannot be replayed elsewhere.
        permissions: { actions: "write" },
        repositories: [REPO_NAME],
      }),
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
      "Dispatched actions-queue-health workflow",
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
      message: "actions-queue-health workflow_dispatch failed",
      extra: { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
    });
    return { ok: false };
  }
}

export const cronActionsQueueHealthDispatch = inngest.createFunction(
  {
    id: "cron-actions-queue-health-dispatch",
    concurrency: [
      { scope: "fn", limit: 1 },
      // Deliberately NOT the shared `"cron-platform"` account lane: that lane
      // serializes against ~75 crons including the claude-eval cohort's 50-min
      // holds — a delay starting inside a hold would push the dispatch past
      // the monitor's margin, paging a false "monitor dead" while the queue
      // being measured is healthy. A ~2-5 s token-mint + POST needs no
      // host-protection lane.
      { scope: "account", key: '"cron-dispatch"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "*/30 * * * *" },
    { event: "cron/actions-queue-health-dispatch.manual-trigger" },
  ],
  cronActionsQueueHealthDispatchHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
