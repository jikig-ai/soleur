import * as Sentry from "@sentry/nextjs";

// Strip JWT-shaped substrings from any string field on the event before
// transport. Validator throws (`lib/supabase/validate-anon-key.ts`) embed a
// JWT preview in `error.message`; without this scrub the preview ships to
// every Sentry-project reader.
const JWT_PATTERN = /eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g;
const JWT_REDACTION = "<jwt-redacted>";

function scrubJwt(input: string | undefined): string | undefined {
  if (!input) return input;
  return input.replace(JWT_PATTERN, JWT_REDACTION);
}

export function scrubJwtFromEvent<T extends Sentry.ErrorEvent>(event: T): T {
  if (event.message) {
    event.message = scrubJwt(event.message);
  }
  if (event.exception?.values) {
    for (const v of event.exception.values) {
      if (v.value) v.value = scrubJwt(v.value);
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
const PII_KEY_RE = /^user_?id$|^email$/i;

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
    event.user.id = undefined;
    event.user.email = undefined;
    event.user.username = undefined;
    event.user.ip_address = undefined;
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

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NODE_ENV,
  tracesSampleRate: 0,
  beforeSend(event) {
    return stripUserContextFromEvent(scrubJwtFromEvent(event));
  },
});
