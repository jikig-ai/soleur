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
  // #5417 — drop the auto OnUncaughtException / OnUnhandledRejection
  // integrations. server/crash-handlers.ts installs MANUAL handlers for both
  // (so unhandledRejection deterministically exits — Sentry's default only
  // warns, leaving the process in an undefined post-rejection state). Keeping
  // the auto integrations would double-report every fatal. Guarded by
  // test/sentry-server-config-no-auto-global-handlers.test.ts.
  integrations: (defaults) =>
    defaults.filter(
      (i) =>
        i.name !== "OnUncaughtException" && i.name !== "OnUnhandledRejection",
    ),
  beforeSend(event) {
    return scrubSentryEvent(event);
  },
  beforeBreadcrumb(breadcrumb) {
    return scrubSentryBreadcrumb(breadcrumb);
  },
});
