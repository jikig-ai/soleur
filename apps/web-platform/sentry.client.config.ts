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

export function scrubJwtFromEvent<T extends Sentry.ErrorEvent>(event: T): T {
  if (event.message) {
    event.message = scrubSensitive(event.message);
  }
  if (event.exception?.values) {
    for (const v of event.exception.values) {
      if (v.value) v.value = scrubSensitive(v.value);
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

export function stripUserContextFromEvent<T extends Sentry.ErrorEvent>(
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
  return event;
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

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NODE_ENV,
  release: sentryRelease,
  tracesSampleRate: 0,
  beforeSend(event) {
    // Sentry's `beforeSend` permits returning `null` to drop the event.
    // `scrubJwtFromEvent` never returns null today, but guarding here keeps
    // the chain composable if either step gains a drop-the-event branch.
    const scrubbed = scrubJwtFromEvent(event);
    return scrubbed ? stripUserContextFromEvent(scrubbed) : null;
  },
});
