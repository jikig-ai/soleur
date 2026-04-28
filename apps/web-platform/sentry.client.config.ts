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

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NODE_ENV,
  tracesSampleRate: 0,
  beforeSend(event) {
    return scrubJwtFromEvent(event);
  },
});
