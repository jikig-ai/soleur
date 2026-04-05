---
module: web-platform
date: 2026-04-05
problem_type: integration_issue
component: tooling
symptoms:
  - "Sentry server-side SDK sending zero events from production container"
  - "captureException calls silently do nothing"
  - "SENTRY_DSN missing from Docker container env despite being in Doppler prd"
root_cause: config_error
resolution_type: config_change
severity: high
tags: [sentry, doppler, docker, env-file, observability]
---

# Troubleshooting: Sentry server-side SDK not sending events -- SENTRY_DSN missing from container

## Problem

The Sentry server-side SDK (`@sentry/nextjs`) never sent any events from the production web-platform container. All `captureException` calls in 12+ error handlers silently did nothing because `SENTRY_DSN` was absent from the container's `process.env`.

## Environment

- Module: web-platform (apps/web-platform/)
- Affected Component: server/index.ts, sentry.server.config.ts, infra/ci-deploy.sh
- Date: 2026-04-05

## Symptoms

- Zero events in Sentry project `jikigai/soleur-web-platform` across all time
- Manual DSN test via curl succeeded (Sentry received the event within 60s)
- `docker exec soleur-web-platform printenv SENTRY_DSN` returned empty
- Container had only 18 of 32 Doppler prd secrets

## What Didn't Work

**Direct solution:** The root cause was identified through systematic diagnosis:

1. SSH into production server confirmed SENTRY_DSN missing from container env
2. Verified Doppler prd config contains SENTRY_DSN (server's service token can access it)
3. Verified Doppler `--format docker` output includes SENTRY_DSN on a clean line
4. Concluded: container was deployed with a stale env set that predated SENTRY_DSN being added to Doppler

## Session Errors

**Test file placed in wrong directory (`server/health.test.ts` instead of `test/server/health.test.ts`)**

- **Recovery:** Moved file to `test/server/` directory to match vitest include pattern
- **Prevention:** Read vitest config (`vitest.config.ts`) before creating test files to verify the include patterns. The web-platform vitest config only includes `test/**/*.test.ts` and `lib/**/*.test.ts`.

## Solution

Two-part fix:

**1. Root cause (env injection):** A redeploy picks up all current Doppler secrets via the existing `--env-file` pipeline in `ci-deploy.sh`. No code change needed for the env injection itself.

**2. Hardening (prevent silent failures):**

```typescript
// server/health.ts -- new sentry field in health endpoint
sentry: process.env.SENTRY_DSN ? "configured" : "not-configured",

// server/index.ts -- startup diagnostic log
log.info({
  sentryConfigured: !!process.env.SENTRY_DSN,
  sentryEnvironment: process.env.NODE_ENV,
}, "Sentry status");

// server/index.ts -- startup test event (gated by DSN)
if (process.env.SENTRY_DSN) {
  Sentry.captureMessage(`Server startup v${process.env.BUILD_VERSION || "dev"}`, "info");
}

// server/index.ts -- SIGTERM handler
process.on("SIGTERM", async () => {
  await Sentry.flush(2000);
  process.exit(0);
});

// sentry.server.config.ts -- conditional debug mode
debug: process.env.SENTRY_DEBUG === "1",
```

## Why This Works

The `ci-deploy.sh` script downloads ALL Doppler prd secrets to a temp env file (`doppler secrets download --no-file --format docker`) and passes it via `docker run --env-file`. This pipeline is correct. The container was simply running with an env set from before `SENTRY_DSN` was added to Doppler.

The hardening changes ensure:

1. `/health` endpoint immediately reveals whether Sentry is configured (no SSH needed)
2. Startup logs confirm DSN presence for log-based monitoring
3. A test event on startup verifies the full Sentry pipeline end-to-end
4. `SIGTERM` handler flushes buffered events before container shutdown (Docker's 10s grace period)
5. `SENTRY_DEBUG=1` env var enables verbose Sentry logging without code changes

## Prevention

- Always check `/health` endpoint after deploy to verify `sentry: "configured"`
- Query Sentry API for the startup event within 60s of deploy to verify end-to-end
- When adding new secrets to Doppler prd, trigger a redeploy to ensure the running container picks them up
- Use `SENTRY_DEBUG=1` in Doppler temporarily if events are not appearing

## Related Issues

- See also: [sentry-zero-events-production-verification-20260405.md](./sentry-zero-events-production-verification-20260405.md) -- Prior investigation that narrowed the root cause
- See also: [2026-04-03-doppler-not-installed-env-fallback-outage.md](./2026-04-03-doppler-not-installed-env-fallback-outage.md) -- Doppler fallback removal (rules out stale .env as cause)
- See also: [production-observability-sentry-pino-health-web-platform-20260328.md](./production-observability-sentry-pino-health-web-platform-20260328.md) -- Original Sentry integration documentation
