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

import { InngestMiddleware } from "inngest";
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

export const sentryCorrelationMiddleware = new InngestMiddleware({
  name: "sentry-correlation",
  init() {
    return {
      onFunctionRun({ ctx, fn }) {
        const fnId = fn.id();
        const runId = ctx.runId;
        const eventName = ctx.event.name;
        const eventId = (ctx.event as { id?: string }).id;

        return {
          transformInput() {
            // Tag the SCOPE — every Sentry.captureException /
            // Sentry.captureMessage / reportSilentFallback fired inside
            // the run inherits these tags automatically. No per-call-site
            // instrumentation needed.
            const scope = Sentry.getCurrentScope();
            scope.setTag("inngest.fn_id", fnId);
            scope.setTag("inngest.run_id", runId);
            scope.setTag("inngest.event_name", eventName);
            if (eventId) scope.setTag("inngest.event_id", eventId);
            scope.setExtra("inngest.event_data", ctx.event.data ?? {});

            safeAddBreadcrumb("inngest.run", `start ${fnId}`, {
              run_id: runId,
              event_name: eventName,
              event_id: eventId,
            });
          },

          beforeMemoization() {
            safeAddBreadcrumb("inngest.step", "before-memoization");
          },

          afterMemoization() {
            safeAddBreadcrumb("inngest.step", "after-memoization");
          },

          beforeExecution() {
            safeAddBreadcrumb("inngest.step", "execution-start");
          },

          afterExecution() {
            safeAddBreadcrumb("inngest.step", "execution-end");
          },

          // Inngest invokes transformOutput AFTER each step completes
          // (`ctx.step` present) AND once at the end of the run (`ctx.step`
          // absent). We use the absence to detect "function final result"
          // and capture any error there. Per-step errors are surfaced via
          // the breadcrumb trail instead — they're recoverable (Inngest
          // retries; only the FINAL error is non-recoverable).
          transformOutput({ result, step }) {
            if (step) {
              // Step-level event. Breadcrumb only — Inngest may retry.
              const ok = result.error == null;
              safeAddBreadcrumb(
                "inngest.step",
                `step ${ok ? "ok" : "error"}`,
                {
                  step_name: step.name,
                  step_op: (step as { op?: string }).op,
                },
                ok ? "info" : "warning",
              );
              return;
            }
            // Function-final event.
            if (result.error != null) {
              const err =
                result.error instanceof Error
                  ? result.error
                  : new Error(String(result.error));
              try {
                Sentry.captureException(err, {
                  tags: {
                    "inngest.fn_id": fnId,
                    "inngest.run_id": runId,
                    "inngest.event_name": eventName,
                  },
                  extra: { "inngest.event_data": ctx.event.data ?? {} },
                });
              } catch {
                // captureException failures must not propagate.
              }
              safeAddBreadcrumb(
                "inngest.run",
                `final error ${fnId}`,
                { run_id: runId },
                "error",
              );
            } else {
              safeAddBreadcrumb("inngest.run", `final ok ${fnId}`, {
                run_id: runId,
              });
            }
          },
        };
      },
    };
  },
});
