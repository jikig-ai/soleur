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
  // Header-scoped tracing (#8978 Phase 0): the committed perf probe sends
  // `x-perf-probe: 1` on every request and samples at 1.0, so cold-path
  // server spans are observable without a Doppler/env change. All other
  // traffic pays a 0.02 floor for baseline coverage. The header is not a
  // secret — worst case is extra transaction volume on traffic the caller
  // already generates (Sentry quota spend only).
  tracesSampler: (samplingContext) => {
    const headers = samplingContext.normalizedRequest?.headers;
    if (headers) {
      for (const [key, value] of Object.entries(headers)) {
        if (key.toLowerCase() === "x-perf-probe" && value === "1") return 1;
      }
    }
    return 0.02;
  },
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
  // Transaction envelopes bypass `beforeSend` — with tracing armed by the
  // sampler above they must route through the same scrub walk (#3829 gate).
  beforeSendTransaction(event) {
    return scrubSentryEvent(event);
  },
  beforeBreadcrumb(breadcrumb) {
    return scrubSentryBreadcrumb(breadcrumb);
  },
});
