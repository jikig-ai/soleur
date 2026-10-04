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
 * workflow header and ADR-270 point here instead of restating it.
 *
 * WHY NOT `schedule:`-only — the workflow's own every-10-minutes cron is
 * kept byte-identical as the FALLBACK clock, but GitHub `schedule:` delivery is
 * measured degraded on this repository: the six runs between 2026-06-30 and
 * 2026-07-01 are spaced 71, 86, 100, 236 and 249 minutes apart (median about
 * 100 minutes), against a 15-minute window between the 45-minute stall
 * threshold and the 60-minute merge-queue check timeout. A probe that can wait
 * longer than that window for its next run cannot report a stuck entry before
 * the queue ejects it. An Inngest cron fires on its own clock, so the probe
 * should run at its requested cadence regardless of GitHub scheduling (the
 * post-merge measurement of dispatched-run spacing confirms or refutes this).
 *
 * WHY INNGEST DISPATCH IS ELIGIBLE HERE: trigger on Inngest, execution in the
 * ephemeral runner is the shape ADR-033's 2026-06-02 scope note names as
 * correct. The anti-circularity corollary passes: the probe's subject is
 * GitHub's merge queue, not this host or Inngest, and the `schedule:` fallback
 * still fires through an Inngest-substrate outage, at its degraded delivery (so
 * it is a fallback, not a substitute for the 15-minute window). An Inngest
 * outage is itself paged by `scheduled_inngest_health`.
 *
 * HARD NON-GOAL: this function does NOT read the queue or file issues. Those
 * grants stay in the runner. It holds only a short-lived GitHub App
 * installation token pinned to this repo with the narrowest scope GitHub offers
 * for workflow_dispatch (actions:write, which also allows cancelling or
 * re-running runs; there is no dispatch-only scope).
 *
 * DETECTION LATENCY is now: stall threshold (45 minutes) + the wait for the next
 * 10-minute tick (0 to 10) + dispatch-to-runner-start + run time. Against the
 * 60-minute timeout the margin is 15 minus those three terms: about 5 minutes
 * at the worst tick phase with no runner delay, about 8 minutes at the average
 * tick phase and the measured median runner wait (about 30 s), and negative once runner wait exceeds
 * roughly 5 to 15 minutes, which the measured p90 (about 20 minutes on a
 * congested pool, ADR-248, 2026-09-24) does. A dispatch that lands but whose
 * run is delayed on the runner pool is NOT detected by this change, so the
 * probe stays BEST-EFFORT in both directions. The post-merge measurement of `startedAt - createdAt` over the
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

// One in-step retry for a transient failure (network error with no HTTP
// status, 5xx, 429). The dispatch step never throws, so the function-level
// `retries: 1` does not re-drive it, and a lost 10-minute tick consumes most of
// the probe's margin. A 4xx (403 grant drift, 404 rename, 422 no trigger) is a
// real defect and is reported immediately, without a retry.
const RETRY_DELAY_MS = 2_000;

type DispatchResult = { ok: boolean; errorSummary?: string };

// Never throws: the dispatch step's catch must stay total, and `String(err)`
// throws for a prototype-less object or a throwing toString.
function safeMessage(err: unknown): string {
  try {
    const m = (err as { message?: unknown } | null | undefined)?.message;
    return typeof m === "string" ? m : String(err);
  } catch {
    return "unserializable error";
  }
}

function isTransient(err: unknown): boolean {
  const status = (err as { status?: unknown } | null | undefined)?.status;
  return typeof status !== "number" || status >= 500 || status === 429;
}

export async function cronMergeQueueStallDispatchHandler({
  step,
  logger,
}: HandlerArgs): Promise<DispatchResult> {
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
    // A failing heartbeat must not replace the mint error that is rethrown
    // (postSentryHeartbeat reports its own failures), so it is contained here.
    try {
      await step.run("sentry-heartbeat-error", async () => {
        await postSentryHeartbeat({
          ok: false,
          sentryMonitorSlug: SENTRY_MONITOR_SLUG,
          cronName: FUNCTION_NAME,
          logger,
        });
      });
    } catch {
      // intentionally ignored: the mint error below is the one that matters
    }
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
        const send = () =>
          octokit.request(
            "POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches",
            {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              workflow_id: WORKFLOW_FILE,
              ref: "main",
            },
          );
        try {
          await send();
        } catch (first) {
          if (!isTransient(first)) throw first;
          // A retry that then succeeds leaves no other trace (no report, green
          // heartbeat), so keep it visible in the logs.
          logger.warn(
            { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
            "dispatch retried after a transient failure",
          );
          await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS));
          await send();
        }
        return { ok: true };
      } catch (err) {
        const e = (err ?? {}) as { name?: unknown };
        // Redact the minted token out of the message before it reaches Sentry,
        // preserving the original Error.name as a field (matches the
        // cron-weekly-analytics precedent).
        const redacted = new Error(
          redactToken(safeMessage(err), installationToken),
        );
        try {
          if (typeof e.name === "string") redacted.name = e.name;
        } catch {
          // a throwing name getter must not escape the never-throws step
        }
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
