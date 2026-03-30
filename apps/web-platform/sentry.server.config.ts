import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
  // Error capture only — no performance tracing at current scale.
  // Enable tracesSampleRate when investigating specific performance issues.
  tracesSampleRate: 0,
  beforeSend(event) {
    // Strip sensitive headers
    if (event.request?.headers) {
      delete event.request.headers["x-nonce"];
      delete event.request.headers.cookie;
    }
    return event;
  },
});
