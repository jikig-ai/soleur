/**
 * cron-merge-queue-stall-dispatch — Inngest-dispatched trigger for the
 * merge-queue stall probe (#9482, follow-up (a) of the ADR-270 decision record).
 *
 * DISPATCH HYBRID: this function is the TRIGGER only. It fires every 10
 * minutes and triggers `.github/workflows/merge-queue-stall-check.yml` through
 * a `workflow_dispatch` API call. The GitHub-hosted runner stays the EXECUTOR:
 * the workflow reads the merge queue and files the suspected-stall issue with
 * its own default `GITHUB_TOKEN` and no app secrets, which is why this function
 * holds nothing beyond a short-lived, dispatch-only token.
 *
 * THIS HEADER IS THE SINGLE AUTHORITY for the trigger and timing story. The
 * workflow header, ADR-270 and the Sentry README point here instead of
 * restating it.
 *
 * WHY NOT `schedule:`-only — the workflow's own every-10-minutes cron is
 * kept byte-identical as the FALLBACK clock, but GitHub `schedule:` delivery is
 * measured degraded on this repository: the six runs between 2026-06-30 and
 * 2026-07-01 are spaced 71, 86, 100, 236 and 249 minutes apart (median about
 * 100 minutes), against a 15-minute window between the 45-minute stall
 * threshold and the 60-minute merge-queue check timeout. A probe that can wait
 * longer than that window for its next run cannot report a stuck entry before
 * the queue ejects it. An Inngest cron fires on its own clock, so the probe
 * runs at its requested cadence regardless of GitHub scheduling.
 *
 * WHY INNGEST DISPATCH IS ELIGIBLE HERE: trigger on Inngest, execution in the
 * ephemeral runner is the shape ADR-033's 2026-06-02 scope note names as
 * correct. The anti-circularity corollary passes: the probe's subject is
 * GitHub's merge queue, not this host or Inngest, and the `schedule:` fallback
 * still fires through an Inngest-substrate outage (an Inngest outage is itself
 * paged by `scheduled_inngest_health`).
 *
 * HARD NON-GOAL: this function does NOT read the queue or file issues. Those
 * grants stay in the runner. It holds only a short-lived GitHub App
 * installation token scoped to the workflow-dispatch permission and pinned to
 * this repo.
 *
 * DETECTION LATENCY is now: stall threshold (45 minutes) + at most one
 * 10-minute cadence + dispatch-to-runner-start + run time. Against the
 * 60-minute timeout that leaves about 5 minutes in the best case and a negative
 * margin at the measured p90 runner wait (about 20 minutes on a congested
 * pool). A dispatch that lands but whose run is delayed on the runner pool is
 * NOT detected by this change, so the probe stays BEST-EFFORT in both
 * directions. The post-merge measurement of `startedAt - createdAt` over the
 * dispatched runs is the evidence for tuning cadence or adding an
 * executor-side heartbeat (tracked by the routing follow-up issue).
 *
 * Liveness (this is the first DISPATCHER-fed monitor slug): the heartbeat for
 * `scheduled-merge-queue-stall-dispatch` is posted by THIS function, not by the
 * executed workflow, because the workflow carries no Sentry secrets. A green
 * check-in therefore means "dispatched", not "probe executed". Do not "fix"
 * that by moving the heartbeat into the workflow without revisiting the
 * secrets posture documented in its header.
 *  - Dispatch error path: an Octokit failure inside `dispatch-workflow` is
 *    reported loudly to the Sentry issues stream via `reportSilentFallback`
 *    (token redacted) and the check-in carries an error status.
 *  - Token-mint failure: posts an error check-in, then rethrows so
 *    `retries: 1` and the Inngest sentry-correlation middleware (tagged
 *    `inngest.fn_id`) still apply.
 *
 * REPLAY SAFETY: Inngest re-executes the whole handler after every step, so a
 * side effect outside a `step.run` repeats on every replay. The report happens
 * INSIDE the dispatch step (memoized, and the step never throws, so the next
 * 10-minute tick is the retry), and the heartbeat is a step callback.
 */
import { inngest } from "@/server/inngest/client";
import {
  type HandlerArgs,
  mintInstallationToken,
  postSentryHeartbeat,
  redactToken,
  REPO_NAME,
  REPO_OWNER,
} from "./_cron-shared";
import { reportSilentFallback } from "@/server/observability";

const FUNCTION_NAME = "cron-merge-queue-stall-dispatch";
// The dispatches endpoint accepts the workflow FILE BASENAME as {workflow_id}
// (no numeric-ID lookup needed — see @octokit/openapi-types).
const WORKFLOW_FILE = "merge-queue-stall-check.yml";
const SENTRY_MONITOR_SLUG = "scheduled-merge-queue-stall-dispatch";
// One short-lived API call; a modest floor is plenty.
const TOKEN_MIN_LIFETIME_MS = 5 * 60 * 1000;

type DispatchResult = { ok: boolean; errorSummary?: string };

export async function cronMergeQueueStallDispatchHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean; errorSummary?: string }> {
  let installationToken: string;
  try {
    installationToken = await step.run("mint-installation-token", async () =>
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
  } catch (err) {
    // The mint is the most probable real failure. Without this check-in it
    // would surface only as a missed check-in about 40 minutes later. Rethrow
    // keeps retries and the Inngest sentry-correlation middleware capture.
    await step.run("sentry-heartbeat-error", async () => {
      await postSentryHeartbeat({
        ok: false,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: FUNCTION_NAME,
        logger,
      });
    });
    throw err;
  }

  // Catch and report INSIDE the step so the report is memoized across replays.
  // The step never throws: a failed POST is retried by the next cron tick.
  const dispatch = await step.run(
    "dispatch-workflow",
    async (): Promise<DispatchResult> => {
      try {
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
        return { ok: true };
      } catch (err) {
        const e = err as { name?: string; message?: unknown };
        // Redact the minted token out of the message before it reaches Sentry,
        // preserving the original Error.name as a field (matches the
        // cron-weekly-analytics precedent).
        const redacted = new Error(
          redactToken(
            typeof e.message === "string" ? e.message : String(e),
            installationToken,
          ),
        );
        if (typeof e.name === "string") redacted.name = e.name;
        reportSilentFallback(redacted, {
          feature: FUNCTION_NAME,
          op: "dispatch-workflow",
          message: "merge-queue-stall-dispatch workflow_dispatch failed",
          extra: { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
        });
        return { ok: false, errorSummary: redacted.message };
      }
    },
  );

  // Its own step, and a callback (not an eager promise): a heartbeat failure
  // must not be reported as a dispatch failure.
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok: dispatch.ok,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: FUNCTION_NAME,
      logger,
    });
  });

  if (dispatch.ok) {
    logger.info(
      { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
      "Dispatched merge-queue-stall-check workflow",
    );
    return { ok: true };
  }
  return { ok: false, errorSummary: dispatch.errorSummary };
}

export const cronMergeQueueStallDispatch = inngest.createFunction(
  {
    id: "cron-merge-queue-stall-dispatch",
    concurrency: [
      { scope: "fn", limit: 1 },
      // Deliberately NOT the shared `"cron-platform"` account lane: that lane
      // serializes against ~75 crons including the claude-eval cohort's 50-min
      // holds, and a delay starting inside a hold would push the dispatch past
      // the monitor's margin. A ~2-5 s token-mint + POST needs no
      // host-protection lane.
      { scope: "account", key: '"cron-dispatch"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "*/10 * * * *" },
    { event: "cron/merge-queue-stall-dispatch.manual-trigger" },
  ],
  cronMergeQueueStallDispatchHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
