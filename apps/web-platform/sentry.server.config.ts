import * as Sentry from "@sentry/nextjs";

import { scrubSentryEvent, scrubSentryBreadcrumb } from "@/server/sentry-scrub";

// release: ties every captured event to the deployed build for diff/
// regression analysis. BUILD_VERSION + BUILD_SHA are baked into the
// Docker image at build time via reusable-release.yml build-args (lines
// 558-559). Shape `web-platform@<version>+<sha>` follows Sentry's
// release-name convention (project@version+commit). Falls back to "dev"
// (matches the Dockerfile ARG defaults) when running outside the
// release image — local dev, vitest, etc.
const sentryRelease = (() => {
  const v = process.env.BUILD_VERSION ?? "dev";
  const sha = process.env.BUILD_SHA ?? "dev";
  if (v === "dev" && sha === "dev") return undefined;
  return `web-platform@${v}+${sha}`;
})();

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
  release: sentryRelease,
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
