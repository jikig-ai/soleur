import * as Sentry from "@sentry/nextjs";
import { PII_KEY_RE } from "@/lib/client-observability";
import {
  reduceTransactionName,
  sanitizeRequestUrl,
} from "@/lib/sentry-url-sanitize";

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
  // are string fields on the event. Two layers, same contract as the
  // server-side `sanitizeRequestForSentry` (server/sentry-scrub.ts):
  // (1) shape-driven URL/token reduction — pageload `request.url` carries the
  //   full document URL including query string (OAuth `code` params,
  //   implicit-flow `access_token` hash fragments) and the path tail can be
  //   a bearer credential (`/invite/<token>` stays valid for days); the
  //   transaction name carries the same tail for unrouted requests; and
  //   `request.query_string` is deleted outright (substring scrubbing it
  //   value-by-value misses non-JWT-shaped secrets).
  // (2) JWT/email substring scrub — `cookies` values and headers can hold
  //   `eyJ…`-shaped session payloads.
  if (event.transaction) {
    event.transaction = reduceTransactionName(
      scrubSensitive(event.transaction) ?? event.transaction,
    );
  }
  if (event.request) {
    const req = event.request;
    if (typeof req.url === "string") {
      req.url = scrubSensitive(sanitizeRequestUrl(req.url)) ?? req.url;
    }
    delete req.query_string;
    for (const rec of [req.headers, req.cookies]) {
      if (!rec) continue;
      for (const k of Object.keys(rec)) {
        const v = rec[k];
        if (typeof v === "string") {
          rec[k] = scrubSensitive(v) ?? v;
        }
      }
    }
    // `request.data` arrives as either a record (handled by
    // `stripUserContextFromEvent`'s PII-key walk) or a raw string — an
    // unparsed POST body can carry credentials verbatim.
    if (typeof req.data === "string") {
      req.data = scrubSensitive(req.data) ?? req.data;
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

// Breadcrumbs attach to every event (errors AND sampled transactions), and
// navigation breadcrumbs' `data.from`/`data.to` carry raw URLs — a pageload
// through `/invite/<token>` leaves the bearer tail in every subsequent
// envelope's breadcrumb trail. `message` gets substring scrub; `from`/`to`
// get the shared token-path reduction (both raw paths and full URLs — the
// reducer works on any string containing the prefix).
export function scrubSentryClientBreadcrumb<T extends Sentry.Breadcrumb>(
  bc: T,
): T {
  if (typeof bc.message === "string") {
    bc.message = reduceTransactionName(scrubSensitive(bc.message) ?? bc.message);
  }
  const data = bc.data as Record<string, unknown> | undefined;
  if (data) {
    // Parity with the server's `scrubSentryBreadcrumb` (scrubRecursive over
    // every string in the payload): any string-bearing data key — not just
    // navigation `from`/`to` — can carry a credential tail (a breadcrumb
    // added by app code, or nested record values).
    scrubBreadcrumbValue(data);
    stripPiiFromRecord(data);
  }
  return bc;
}

/** Deep-walk breadcrumb data scrubbing every string leaf (JWT/email
 * substring + token-path reduction), mutating in place. */
function scrubBreadcrumbValue(v: unknown): void {
  if (typeof v === "string") return; // callers scrub strings at the key site
  if (Array.isArray(v)) {
    for (let i = 0; i < v.length; i++) {
      if (typeof v[i] === "string") {
        v[i] = reduceTransactionName(scrubSensitive(v[i] as string) ?? v[i]);
      } else scrubBreadcrumbValue(v[i]);
    }
    return;
  }
  if (v && typeof v === "object") {
    const rec = v as Record<string, unknown>;
    for (const k of Object.keys(rec)) {
      const item = rec[k];
      if (typeof item === "string") {
        rec[k] = reduceTransactionName(scrubSensitive(item) ?? item);
      } else scrubBreadcrumbValue(item);
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
  // instead (`sessionStorage["soleur.perf-probe"] = "1"` via page.addInitScript
  // before navigation; client-side equivalent of the server's `x-perf-probe`
  // arm). Probe runs sample at 1.0; real sessions pay the 0.1 floor (NFR4 —
  // no fallback may exceed 0.1). Storage getters can throw where cookies are
  // disabled — the try/catch falls through to the floor.
  tracesSampler: () => {
    try {
      if (
        typeof sessionStorage !== "undefined" &&
        sessionStorage.getItem("soleur.perf-probe") === "1"
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
  // Breadcrumbs bypass all three envelope callbacks — navigation `from`/`to`
  // URLs reach every event attached to them (server wires the equivalent
  // `scrubSentryBreadcrumb` in sentry.server.config.ts).
  beforeBreadcrumb(bc) {
    return scrubSentryClientBreadcrumb(bc);
  },
});
