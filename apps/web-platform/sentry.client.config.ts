import * as Sentry from "@sentry/nextjs";
import { PII_KEY_RE } from "@/lib/client-observability";

// Strip sensitive substrings (JWTs, email addresses) from any string field on
// the event before transport. Two leak vectors this closes:
//   - JWT preview: validator throws (`lib/supabase/validate-anon-key.ts`) embed
//     a JWT preview in `error.message`.
//   - Email: Supabase auth errors (`verifyOtp`/`signInWithOtp`) carry the user's
//     email in `error.message`, and `reportSilentFallback` forwards the raw
//     error object to `Sentry.captureException`, so the message lands in
//     `event.exception.values[].value`. The structured `extra` payload is
//     already email-free (only enum `code` / int `status`), but the captured
//     exception value is the residual vector this scrub covers.
// Sentry is a shared cross-tenant project — over-redacting here is the safe
// direction (an email is never wanted in error telemetry).
const JWT_PATTERN = /eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g;
const JWT_REDACTION = "<jwt-redacted>";
const EMAIL_PATTERN = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const EMAIL_REDACTION = "<email-redacted>";

function scrubSensitive(input: string | undefined): string | undefined {
  if (!input) return input;
  return input
    .replace(JWT_PATTERN, JWT_REDACTION)
    .replace(EMAIL_PATTERN, EMAIL_REDACTION);
}

// `@sentry/nextjs` does not re-export `SpanJSON` on its merged type index
// (the options surface types `beforeSendSpan` with it, but the name itself
// isn't exported), so span payloads are typed structurally — `description`
// and `data` are the only fields the scrub touches. `Event.spans` members and
// `beforeSendSpan`'s `SpanJSON` parameter both satisfy this shape.
interface SpanPayload {
  description?: string;
  data?: Record<string, unknown>;
}

// Scrub JWT/email substrings from the string-bearing fields of a span
// payload (`SpanJSON`): `description` plus every string value in `data`.
// Span `data` attributes carry full URLs (`http.url`) whose query strings can
// hold tokens/emails — the same leak vector `scrubSensitive` closes on
// message/exception text.
function scrubSpanStrings(span: SpanPayload): void {
  if (span.description) {
    span.description = scrubSensitive(span.description);
  }
  if (span.data) {
    for (const [k, v] of Object.entries(span.data)) {
      if (typeof v === "string") {
        span.data[k] = scrubSensitive(v) ?? v;
      }
    }
  }
}

export function scrubJwtFromEvent<T extends Sentry.Event>(event: T): T {
  if (event.message) {
    event.message = scrubSensitive(event.message);
  }
  // Transaction envelopes (#9178): the transaction name and request fields
  // are string fields on the event — same substring contract as `message`.
  // Pageload `request.url` carries the full document URL including query
  // string; `cookies` values can hold `eyJ…`-shaped session payloads.
  if (event.transaction) {
    event.transaction = scrubSensitive(event.transaction);
  }
  if (event.request) {
    const req = event.request;
    if (typeof req.url === "string") {
      req.url = scrubSensitive(req.url);
    }
    if (typeof req.query_string === "string") {
      req.query_string = scrubSensitive(req.query_string);
    } else if (Array.isArray(req.query_string)) {
      req.query_string = req.query_string.map(
        ([k, v]) => [k, scrubSensitive(v) ?? v] as [string, string],
      );
    } else if (req.query_string) {
      for (const [k, v] of Object.entries(req.query_string)) {
        req.query_string[k] = scrubSensitive(v) ?? v;
      }
    }
    for (const rec of [req.headers, req.cookies]) {
      if (!rec) continue;
      for (const k of Object.keys(rec)) {
        const v = rec[k];
        if (typeof v === "string") {
          rec[k] = scrubSensitive(v) ?? v;
        }
      }
    }
  }
  if (event.exception?.values) {
    for (const v of event.exception.values) {
      if (v.value) v.value = scrubSensitive(v.value);
    }
  }
  // Embedded child spans on a transaction event are SpanJSON payloads —
  // substring side of the span scrub lives here (key stripping stays in
  // `stripUserContextFromEvent`, same division as extra/contexts).
  if (event.spans) {
    for (const span of event.spans) {
      scrubSpanStrings(span);
    }
  }
  return event;
}

// Strip PII keys (`userId`, `user_id`, `email`) from any structured field
// on the event before transport. Layer-3 backstop for the helper-boundary
// strip in `lib/client-observability.ts` — covers direct `Sentry.captureException`
// callers that bypass the helper (`lib/upload-attachments.ts`,
// `components/concurrency/upgrade-at-capacity-modal.tsx`,
// `components/chat/chat-surface.tsx`, `app/global-error.tsx`).
// `PII_KEY_RE` is imported from `lib/client-observability` so the helper
// boundary and this backstop cannot drift on which keys count as PII.

function stripPiiFromRecord(
  rec: Record<string, unknown> | undefined,
): void {
  if (!rec) return;
  for (const k of Object.keys(rec)) {
    if (PII_KEY_RE.test(k)) {
      delete rec[k];
    }
  }
}

export function stripUserContextFromEvent<T extends Sentry.Event>(
  event: T,
): T {
  if (event.user) {
    // `delete` (vs assigning `undefined`) is defensible against future
    // SDK serializer changes that might stringify undefined as "undefined"
    // or coerce it to null; symmetric with `stripPiiFromRecord` below.
    delete event.user.id;
    delete event.user.email;
    delete event.user.username;
    delete event.user.ip_address;
  }
  if (event.extra) {
    stripPiiFromRecord(event.extra as Record<string, unknown>);
  }
  if (event.contexts) {
    for (const ctxKey of Object.keys(event.contexts)) {
      const ctx = event.contexts[ctxKey] as
        | Record<string, unknown>
        | undefined;
      if (ctx) stripPiiFromRecord(ctx);
    }
  }
  if (event.breadcrumbs) {
    for (const bc of event.breadcrumbs) {
      stripPiiFromRecord(bc.data as Record<string, unknown> | undefined);
    }
  }
  // Transaction envelopes (#9178): `request.data` (POST body capture) and
  // embedded child spans' `data` attributes are record fields that can carry
  // `user_id`/`email` keys — same strip contract as `extra`.
  if (
    event.request?.data &&
    typeof event.request.data === "object" &&
    !Array.isArray(event.request.data)
  ) {
    stripPiiFromRecord(event.request.data as Record<string, unknown>);
  }
  if (event.spans) {
    for (const span of event.spans) {
      stripPiiFromRecord(span.data);
    }
  }
  return event;
}

// The whole-payload span scrub wired as `beforeSendSpan`: PII-key strip plus
// JWT/email substring scrub — the same contract the composed
// `scrubJwtFromEvent` + `stripUserContextFromEvent` chain gives transaction
// envelopes (the SDK runs this callback over the root span and every embedded
// child span before `beforeSendTransaction`, per @sentry/core `client.js`
// `processBeforeSend`; this callback must never return null — the SDK warns
// and ships the un-scrubbed span instead).
export function scrubSpanPayload<T extends SpanPayload>(span: T): T {
  scrubSpanStrings(span);
  stripPiiFromRecord(span.data);
  return span;
}

// release: ties client-side events to the deployed build. BUILD_VERSION /
// BUILD_SHA reach the client bundle via next.config.ts `env:` (webpack
// inline-substitution at build time); same shape as
// sentry.server.config.ts. Falls back to undefined when unset (local dev,
// vitest) so Sentry doesn't shard local errors under a phantom release.
const sentryRelease = (() => {
  const v = process.env.BUILD_VERSION ?? "dev";
  const sha = process.env.BUILD_SHA ?? "dev";
  if (v === "dev" && sha === "dev") return undefined;
  return `web-platform@${v}+${sha}`;
})();

// The browser-tracing integration auto-registers `webVitalsIntegration`:
// pageload/navigation transactions carry LCP/CLS/INP/FCP/TTFB as measurements
// (#9178). The standalone `webVitalsIntegration` was rejected — verified
// against the installed @sentry/browser build, it emits CLS/LCP/INP spans only
// under `traceLifecycle: 'stream'`, and FCP/TTFB have no standalone path at
// all (`WebVitalName = 'cls' | 'inp' | 'lcp'`).
//
// Env guard: the tracing factory is exported only by the CLIENT build of
// `@sentry/nextjs` — under Node resolution (vitest unit env) the package
// resolves to `index.server` where the symbol is absent, and existing suites
// import this module for its exported helpers. In the browser bundle the
// export is always present. An integrations ARRAY is additive in SDK v10 —
// `[...defaultIntegrations, ...user]` per @sentry/core `getIntegrationsToSetup`
// — so this appends tracing rather than replacing the defaults.
// (The exported factory name appears exactly once in this file — the plan's
// discoverability probe greps for a single hit.)
const browserTracingFactory = Sentry.browserTracingIntegration;
const browserTracing =
  typeof browserTracingFactory === "function"
    ? browserTracingFactory()
    : undefined;

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NODE_ENV,
  release: sentryRelease,
  integrations: browserTracing ? [browserTracing] : [],
  // Header-scoped sampling is not possible client-side — a `tracesSampler`
  // receives no request headers — so the perf probe arms a storage marker
  // instead (`localStorage["soleur.perf-probe"] = "1"` via page.addInitScript
  // before navigation; client-side equivalent of the server's `x-perf-probe`
  // arm). Probe runs sample at 1.0; real sessions pay the 0.1 floor (NFR4 —
  // no fallback may exceed 0.1). Storage getters can throw where cookies are
  // disabled — the try/catch falls through to the floor.
  tracesSampler: () => {
    try {
      if (
        typeof localStorage !== "undefined" &&
        localStorage.getItem("soleur.perf-probe") === "1"
      ) {
        return 1;
      }
    } catch {
      // fall through to the floor rate
    }
    return 0.1;
  },
  beforeSend(event) {
    // Sentry's `beforeSend` permits returning `null` to drop the event.
    // `scrubJwtFromEvent` never returns null today, but guarding here keeps
    // the chain composable if either step gains a drop-the-event branch.
    const scrubbed = scrubJwtFromEvent(event);
    return scrubbed ? stripUserContextFromEvent(scrubbed) : null;
  },
  // Transaction envelopes bypass `beforeSend` — with tracing armed by the
  // sampler above they must route through the same scrub chain (#3829-class
  // gate; mirrors sentry.server.config.ts). Span coverage is inside the
  // helpers' `event.spans` walk, so this sink is self-contained even if
  // `beforeSendSpan` never ran for a given span.
  beforeSendTransaction(event) {
    const scrubbed = scrubJwtFromEvent(event);
    return scrubbed ? stripUserContextFromEvent(scrubbed) : null;
  },
  // Standalone/streamed span payloads bypass both event-level callbacks.
  beforeSendSpan(span) {
    return scrubSpanPayload(span);
  },
});
