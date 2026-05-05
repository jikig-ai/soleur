import * as Sentry from "@sentry/nextjs";

import { scrubSentryEvent, scrubSentryBreadcrumb } from "@/server/sentry-scrub";

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
  debug: process.env.SENTRY_DEBUG === "1",
  // Error capture only — no performance tracing at current scale.
  // Enable tracesSampleRate when investigating specific performance issues.
  tracesSampleRate: 0,
  beforeSend(event) {
    return scrubSentryEvent(event);
  },
  beforeBreadcrumb(breadcrumb) {
    return scrubSentryBreadcrumb(breadcrumb);
  },
});
