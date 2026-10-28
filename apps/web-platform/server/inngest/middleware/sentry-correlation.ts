// Inngest → Sentry correlation middleware.
//
// Applied once at `server/inngest/client.ts`; runs on every function
// invocation across the substrate. Three jobs:
//
//   1. Tag the active Sentry scope with `inngest.fn_id`, `inngest.run_id`,
//      `inngest.event_name` and attach the event payload as `extra` so
//      handler-side errors captured via `Sentry.captureException` or
//      `reportSilentFallback` carry the run identifier without per-call
//      site instrumentation.
//
//   2. Emit a Sentry breadcrumb per step transition (memoize-cache hit,
//      memoize-cache miss → executed). Categories follow Sentry's
//      "navigation"-style convention so the breadcrumb timeline reads as
//      a step trace.
//
//   3. Capture `transformOutput` errors at the function-level (Inngest's
//      final-failure path) so a function that returns `result.error`
//      surfaces in Sentry's issues stream as a regular exception, NOT
//      just as a missed Sentry-monitor checkin.
//
// Run-id is the load-bearing forensic key: every Sentry event tagged
// `inngest.run_id:<id>` correlates to one entry in Inngest's dashboard
// run history. The full chain (Sentry breadcrumbs + pino mirror via
// observability.ts + Inngest dashboard + Vector-shipped journald) gives
// an operator everything needed for RCA without SSH or `docker exec`.
//
// PII: event payloads are passed-through as Sentry `extra` and routed
// through `sentry.server.config.ts`'s `beforeSend` scrubber. Any field
// matching the scrubber's PII regex (cookies, tokens, emails) is
// redacted before transmission.

import { Middleware } from "inngest";
import * as Sentry from "@sentry/nextjs";

// Sentry's `addBreadcrumb` accepts an opaque `data` payload (typed `?: {
// [key: string]: any }`); we keep it narrow.
type BreadcrumbData = Record<string, unknown>;

function safeAddBreadcrumb(
  category: string,
  message: string,
  data?: BreadcrumbData,
  level: "info" | "warning" | "error" = "info",
): void {
  try {
    Sentry.addBreadcrumb({ category, message, data, level, type: "default" });
  } catch {
    // breadcrumb failures must NEVER propagate — they would convert
    // observability into a function-killing exception. Same defensive
    // pattern as observability.ts `reportSilentFallback`.
  }
}

// v4 port (#8628): registered on the client as a CLASS — the SDK instantiates
// one per request, so the run identity the v3 onFunctionRun closure captured
// moves to instance fields (fresh per request, matching v3's per-run scope).
// Hook mapping: transformInput → transformFunctionInput; the four
// before/after-memoization/execution breadcrumbs collapse onto the nearest v4
// lifecycle hooks (they were observability breadcrumbs only — loss-tolerable
// by design); the step-vs-final transformOutput split becomes onStepComplete/
// onStepError vs onRunComplete/onRunError, and the final-error capture gains
// the native `isFinalAttempt` gate v3 approximated with "transformOutput
// fires per attempt".
export class SentryCorrelationMiddleware extends Middleware.BaseMiddleware {
  readonly id = "sentry-correlation";

  private fnId = "";
  private runId: string | undefined;
  private eventName = "";
  private eventData: Record<string, unknown> = {};

  transformFunctionInput(
    arg: Middleware.TransformFunctionInputArgs,
  ): Middleware.TransformFunctionInputArgs {
    this.fnId = arg.fn.id();
    const ctx = arg.ctx;
    this.runId = ctx.runId;
    this.eventName = ctx.event?.name ?? "";
    this.eventData = (ctx.event?.data ?? {}) as Record<string, unknown>;
    const eventId = (ctx.event as { id?: string } | undefined)?.id;

    // Tag the SCOPE — every Sentry.captureException /
    // Sentry.captureMessage / reportSilentFallback fired inside
    // the run inherits these tags automatically. No per-call-site
    // instrumentation needed.
    const scope = Sentry.getCurrentScope();
    scope.setTag("inngest.fn_id", this.fnId);
    scope.setTag("inngest.run_id", this.runId);
    scope.setTag("inngest.event_name", this.eventName);
    if (eventId) scope.setTag("inngest.event_id", eventId);
    scope.setExtra("inngest.event_data", this.eventData);

    safeAddBreadcrumb("inngest.run", `start ${this.fnId}`, {
      run_id: this.runId,
      event_name: this.eventName,
      event_id: eventId,
    });
    return arg;
  }

  onMemoizationEnd(_arg: Middleware.OnMemoizationEndArgs): void {
    // v3 emitted paired before/after-memoization breadcrumbs; v4 hands a
    // single post-memoization hook — the pair collapses to one row, same
    // observability value (it marks "a replayed request just resolved its
    // memoized steps").
    safeAddBreadcrumb("inngest.step", "memoization-end");
  }

  onStepStart(arg: Middleware.OnStepStartArgs): void {
    safeAddBreadcrumb("inngest.step", "execution-start", {
      step: stepLabel(arg.stepInfo),
    });
  }

  onStepComplete(arg: Middleware.OnStepCompleteArgs): void {
    // Step-level event. Breadcrumb only — Inngest may retry.
    safeAddBreadcrumb("inngest.step", "step ok", {
      step: stepLabel(arg.stepInfo),
    });
  }

  onStepError(arg: Middleware.OnStepErrorArgs): void {
    safeAddBreadcrumb(
      "inngest.step",
      "step error",
      { step: stepLabel(arg.stepInfo), final_attempt: arg.isFinalAttempt },
      "warning",
    );
  }

  onRunComplete(_arg: Middleware.OnRunCompleteArgs): void {
    safeAddBreadcrumb("inngest.run", `final ok ${this.fnId}`, {
      run_id: this.runId,
    });
  }

  onRunError(arg: Middleware.OnRunErrorArgs): void {
    // Gate on the native final-attempt signal: a non-final thrown attempt
    // will retry — capturing it would file a Sentry ISSUE for a recoverable
    // error. The breadcrumb trail still records it.
    if (!arg.isFinalAttempt) {
      safeAddBreadcrumb(
        "inngest.run",
        `attempt error ${this.fnId}`,
        { run_id: this.runId },
        "warning",
      );
      return;
    }
    const err =
      arg.error instanceof Error ? arg.error : new Error(String(arg.error));
    try {
      Sentry.captureException(err, {
        tags: {
          "inngest.fn_id": this.fnId,
          "inngest.run_id": this.runId,
          "inngest.event_name": this.eventName,
        },
        extra: { "inngest.event_data": this.eventData },
      });
    } catch {
      // captureException failures must not propagate.
    }
    safeAddBreadcrumb(
      "inngest.run",
      `final error ${this.fnId}`,
      { run_id: this.runId },
      "error",
    );
  }
}

// v4 StepInfo carries `options` (the step's declared options) plus the hashed
// id — the v3 `step.name`/`step.op` pair maps to `options.id ?? hashedId`. The
// hooks hand a DeepReadonly arg, so the param type is the read-only shape.
function stepLabel(
  info: Middleware.OnStepStartArgs["stepInfo"],
): string {
  const id = (info.options as { id?: string } | undefined)?.id;
  return id ?? info.hashedId;
}
