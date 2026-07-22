// PR-F (#3244, #3940) Phase 2 — Inngest client.
//
// Fail-closed at module load on missing/empty INNGEST_SIGNING_KEY or
// INNGEST_EVENT_KEY, and on malformed INNGEST_BASE_URL when set. The
// signing key gates inbound POST verification at /api/inngest; the event
// key signs outbound `inngest.send` envelopes from the Stripe webhook.
// Both are load-bearing for ADR-030 invariant I4 (signature-verify required
// at startup). A silent default would expose the runtime trigger surface
// to forged events.
//
// INNGEST_BASE_URL is optional. Self-hosted Hetzner deploys set it to the
// Inngest server URL — the dedicated soleur-inngest host http://10.0.1.40:8288
// post-cutover (#6178; formerly the co-located loopback http://127.0.0.1:8288
// per ADR-030); Inngest Cloud deploys (rejected, see ADR-030) would omit it.

import { Inngest } from "inngest";

import { sentryCorrelationMiddleware } from "@/server/inngest/middleware/sentry-correlation";
import { runLogMiddleware } from "@/server/inngest/middleware/run-log";
import { boundLoggerMiddleware } from "@/server/inngest/middleware/bound-logger";

const SIGNING_KEY = process.env.INNGEST_SIGNING_KEY;
const EVENT_KEY = process.env.INNGEST_EVENT_KEY;
const BASE_URL = process.env.INNGEST_BASE_URL;

// Next.js sets NEXT_PHASE during `next build` page-data collection, which
// loads route modules (including /api/inngest) without runtime env vars.
// Skip the load-time guards during build so the bundle compiles; they
// re-fire at first request via process-restart on Hetzner (the production
// node process starts with the Doppler-injected env vars).
const IS_BUILD_PHASE = process.env.NEXT_PHASE === "phase-production-build";

if (!IS_BUILD_PHASE) {
  if (!SIGNING_KEY) {
    throw new Error("INNGEST_SIGNING_KEY missing at startup");
  }
  if (!EVENT_KEY) {
    throw new Error("INNGEST_EVENT_KEY missing at startup");
  }
  // Review P2-1 (security-sentinel): in cloud mode the Inngest SDK
  // validates signatures; in dev mode it short-circuits validateSignature
  // to success (per node_modules/inngest/components/InngestCommHandler.js).
  // A Doppler prd misconfiguration setting INNGEST_DEV=1 would silently
  // disable I4 — refuse to load.
  if (
    process.env.NODE_ENV === "production" &&
    process.env.INNGEST_DEV === "1"
  ) {
    throw new Error(
      "INNGEST_DEV=1 in production refuses to load: signature verification would be bypassed (ADR-030 I4)",
    );
  }
}
if (BASE_URL) {
  try {
    new URL(BASE_URL);
  } catch {
    throw new Error(`INNGEST_BASE_URL malformed: ${BASE_URL}`);
  }
}

export const inngest = new Inngest({
  id: "soleur-runtime",
  eventKey: EVENT_KEY ?? "build-phase-placeholder",
  // sentry-correlation middleware tags every Sentry event captured during
  // a function run with `inngest.run_id` + `inngest.fn_id` and emits per-
  // step breadcrumbs. Final-result errors are captured to Sentry's issues
  // stream via the middleware's `transformOutput` hook. Applied once
  // here so every existing AND future Inngest function is covered without
  // per-handler instrumentation.
  // routine-run-log middleware (#5345) writes one terminal row per
  // EXPECTED_CRON_FUNCTIONS run to public.routine_runs (final-attempt-gated,
  // fail-soft). Ordered after sentry-correlation so a run-log write failure
  // still inherits the tagged Sentry scope.
  // bound-ctx-logger middleware (#6703) binds every function-valued property
  // of ctx.logger so a detached reference (`const f = logger.info`) can never
  // lose its receiver and throw `Cannot read properties of undefined (reading
  // 'enabled')`. Registered LAST so it wraps the ctx the earlier middlewares
  // have already finished composing. Deliberately NOT accompanied by a
  // `logger:` option — inngest wraps whatever you pass in ProxyLogger
  // regardless (Inngest.js:673), so wiring one would not fix the receiver loss,
  // and it would turn INFO ctx-logs into JSON that vector.toml then drops.
  middleware: [
    sentryCorrelationMiddleware,
    runLogMiddleware,
    boundLoggerMiddleware,
  ],
  ...(BASE_URL ? { baseUrl: BASE_URL } : {}),
});
