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
 * run is delayed on the runner pool IS detected by `check-previous-run`
 * (#9513): the next tick reads the previous run's status/conclusion through
 * the same `actions:write` token and posts an error check-in when the run
 * concluded red or is still non-completed past the executor's own
 * `timeout-minutes: 10` (the runner-wait gap). The probe still stays
 * BEST-EFFORT in both directions — the detection is one tick late by design,
 * so a margin-sized delay lands before the verdict does. The post-merge
 * measurement of `startedAt - createdAt` over the
 * dispatched runs is the evidence for tuning cadence or adding an
 * executor-side heartbeat (tracked by the routing follow-up issue).
 *
 * Liveness (this is the first DISPATCHER-fed monitor slug): the heartbeat for
 * `scheduled-merge-queue-stall-dispatch` is posted by THIS function, not by the
 * executed workflow, because the workflow carries no Sentry secrets. A green
 * check-in means "dispatched AND the previous executor run was not
 * red/stuck/unreadable" — an error check-in means the dispatch POST failed OR
 * the previous run concluded in the failure class OR was still non-completed
 * past `STUCK_RUN_AGE_MS` OR the runs-list read itself failed (a blind check
 * is a failed check). Do not "fix" this by moving the heartbeat into the
 * workflow without revisiting the secrets posture documented in its header.
 *  - Dispatch error path: an Octokit failure inside `dispatch-workflow` is
 *    reported loudly to the Sentry issues stream via `reportSilentFallback`
 *    (token redacted) and the check-in carries an error status.
 *  - Previous-run error path: a failure-class conclusion, a stuck run, or a
 *    failed runs-list read is reported through the same channel
 *    (`op: check-previous-run`) and flips the check-in to error while the
 *    function's result stays the dispatch verdict.
 *  - Token-mint failure: posts an error check-in, then rethrows so
 *    `retries: 1` and the Inngest sentry-correlation middleware (tagged
 *    `inngest.fn_id`) still apply.
 *
 * REPLAY SAFETY: Inngest re-executes the whole handler after every step, so a
 * side effect outside a `step.run` repeats on every replay. The reports happen
 * INSIDE the check and dispatch steps (memoized, and neither step throws, so
 * the next 10-minute tick is the retry), and the heartbeat is a step callback.
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

// #9513 — the check-previous-run verdicts. The newest listed run is
// deterministically the previous tick's because the check runs BEFORE this
// tick's dispatch POST lands in the list. The list is intentionally
// unfiltered: a schedule-fallback or manually-dispatched red run is the same
// alert gap as a dispatched one (this workflow only ever fires on
// schedule + workflow_dispatch, so nothing else can appear).
const RUNS_PER_PAGE = 5;
// The two non-completed bases a "stuck" verdict can rest on:
//  - `in_progress`: the job has exceeded its own `timeout-minutes: 10` —
//    judged from `run_started_at` (NOT `created_at`: a run that waited in the
//    queue is legitimately mid-flight when its job age is still under the cap;
//    GitHub itself marks a past-cap job `timed_out`, which the `failed`
//    verdict then catches — this branch only fires for a wedged one).
//  - queued / requested / waiting / pending: the run never got a runner.
//    Judged from `created_at` against a 5-minute floor — the previous tick's
//    run is ~10 min old at check time, so the floor separates it from a
//    schedule-fallback or manually-dispatched run that landed seconds ago
//    (a just-created queued run must never page).
const STUCK_RUN_AGE_MS = 11 * 60 * 1000;
const STUCK_QUEUE_AGE_MS = 5 * 60 * 1000;
// Failure-class conclusions (exhaustive against the Actions enum; `skipped`
// and `neutral` are not reds).
const BAD_CONCLUSIONS = new Set([
  "failure",
  "timed_out",
  "cancelled",
  "startup_failure",
  "action_required",
  "stale",
]);

type PreviousRunVerdict =
  | { verdict: "ok" }
  | { verdict: "pending" }
  | { verdict: "none" }
  | {
      verdict: "failed";
      conclusion: string;
      runId?: number;
      runUrl?: string;
    }
  | {
      verdict: "stuck";
      status: string;
      ageMinutes: number;
      runId?: number;
      runUrl?: string;
    }
  | { verdict: "unknown"; errorSummary: string };

// The dispatch step's own outcome.
type DispatchOutcome = { ok: boolean; errorSummary?: string };

// The handler's result: the dispatch verdict plus what the check found.
type DispatchResult = DispatchOutcome & {
  previousRun: PreviousRunVerdict["verdict"];
};

type WorkflowRunRow = {
  id?: number;
  status?: string | null;
  conclusion?: string | null;
  created_at?: string;
  run_started_at?: string;
  html_url?: string;
};

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

  // #9513 — executor-visibility check. Runs BEFORE the dispatch so the newest
  // listed run is deterministically the previous tick's (afterwards, the
  // just-POSTed run races into the list and "previous" becomes ambiguous). It
  // reads through the same actions:write installation token — the runs-list
  // endpoint is a read under the existing grant, no new secret or permission.
  // Never throws: a failed read is the `unknown` verdict, which reports and
  // pages (a blind check is a failed check) but never aborts this tick's
  // dispatch. The report happens INSIDE the step so it is memoized across
  // replays exactly like the dispatch report.
  const previousRun = await step.run(
    "check-previous-run",
    async (): Promise<PreviousRunVerdict> => {
      const reportRed = (
        kind: string,
        detail: Record<string, unknown>,
      ): void => {
        reportSilentFallback(
          new Error(`previous merge-queue-stall-check run ${kind}`),
          {
            feature: FUNCTION_NAME,
            op: "check-previous-run",
            message: `merge-queue-stall-dispatch found a ${kind} previous run`,
            extra: { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE, ...detail },
          },
        );
      };
      try {
        const { Octokit } = await import("@octokit/core");
        const octokit = new Octokit({ auth: installationToken });
        const resp = await octokit.request(
          "GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs",
          {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            workflow_id: WORKFLOW_FILE,
            per_page: RUNS_PER_PAGE,
          },
        );
        const runs =
          ((resp.data ?? {}) as { workflow_runs?: WorkflowRunRow[] })
            .workflow_runs ?? [];
        const prev = runs[0];
        if (!prev) return { verdict: "none" };
        if (prev.status !== "completed") {
          // Non-completed: two bases (see STUCK_*_AGE_MS comments). A field we
          // could not read (unparseable timestamp) is pending, never stuck —
          // never page on a value we failed to parse.
          const nowMs = Date.now();
          const stuckIf = (
            ageMs: number,
          ): PreviousRunVerdict | null => {
            if (ageMs <= 0) return null;
            const v: PreviousRunVerdict = {
              verdict: "stuck",
              status: String(prev.status),
              ageMinutes: Math.floor(ageMs / 60_000),
              runId: prev.id,
              runUrl: prev.html_url,
            };
            reportRed(`stuck (status=${prev.status})`, v);
            return v;
          };
          if (prev.status === "in_progress") {
            const startedMs = Date.parse(prev.run_started_at ?? "");
            if (
              Number.isFinite(startedMs) &&
              nowMs - startedMs > STUCK_RUN_AGE_MS
            ) {
              return stuckIf(nowMs - startedMs) ?? { verdict: "pending" };
            }
            return { verdict: "pending" };
          }
          // queued / requested / waiting / pending — never got a runner.
          const createdMs = Date.parse(prev.created_at ?? "");
          if (
            Number.isFinite(createdMs) &&
            nowMs - createdMs > STUCK_QUEUE_AGE_MS
          ) {
            return stuckIf(nowMs - createdMs) ?? { verdict: "pending" };
          }
          return { verdict: "pending" };
        }
        if (
          typeof prev.conclusion === "string" &&
          BAD_CONCLUSIONS.has(prev.conclusion)
        ) {
          const v: PreviousRunVerdict = {
            verdict: "failed",
            conclusion: prev.conclusion,
            runId: prev.id,
            runUrl: prev.html_url,
          };
          reportRed(`red (conclusion=${prev.conclusion})`, v);
          return v;
        }
        return { verdict: "ok" };
      } catch (err) {
        // Same redaction contract as the dispatch step: the minted token can
        // ride inside an Octokit error message on its way to Sentry.
        const redacted = new Error(
          redactToken(safeMessage(err), installationToken),
        );
        const e = (err ?? {}) as { name?: unknown };
        try {
          if (typeof e.name === "string") redacted.name = e.name;
        } catch {
          // a throwing name getter must not escape the never-throws step
        }
        reportSilentFallback(redacted, {
          feature: FUNCTION_NAME,
          op: "check-previous-run",
          message: "merge-queue-stall-dispatch previous-run check failed",
          extra: { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
        });
        return { verdict: "unknown", errorSummary: redacted.message };
      }
    },
  );

  // Catch and report INSIDE the step so the report is memoized across replays.
  // The step never throws: a failed POST is retried by the next cron tick.
  const dispatch = await step.run(
    "dispatch-workflow",
    async (): Promise<DispatchOutcome> => {
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
  // must not be reported as a dispatch failure. The check-in is red when the
  // dispatch failed OR the previous-run check found red/stuck/unknown —
  // `pending` (still legitimately in flight) and `none` (first-ever tick) are
  // not failures (issue #9513).
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok:
        dispatch.ok &&
        (previousRun.verdict === "ok" ||
          previousRun.verdict === "pending" ||
          previousRun.verdict === "none"),
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
    return { ok: true, previousRun: previousRun.verdict };
  }
  return {
    ok: false,
    errorSummary: dispatch.errorSummary,
    previousRun: previousRun.verdict,
  };
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
