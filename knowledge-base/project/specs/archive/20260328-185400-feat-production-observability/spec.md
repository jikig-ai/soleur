# Feature: Production Observability

## Problem Statement

The Soleur web platform has zero production observability. Errors go to `console.error` in rotating Docker logs (30MB cap). The CSP nonce bug (#1213) was live and undetected until manual discovery. The founder SSHes into the server to debug — unsustainable and unreliable since logs rotate out within hours.

## Goals

- Detect production errors automatically (client-side and server-side)
- Monitor uptime externally with alerting
- Replace ad-hoc `console.*` logging with structured, queryable output
- Route alerts to Telegram for immediate visibility
- Enrich the health endpoint with dependency checks and version info
- Add post-deploy verification that confirms the correct version is running

## Non-Goals

- KPI metrics dashboards (deferred to Phase 3 with #1063)
- Product analytics on app.soleur.ai (deferred to Phase 3, item 3.11)
- Synthetic monitoring with Playwright browser checks (Phase 4+)
- OpenTelemetry distributed tracing (Phase 4, when container-per-workspace lands)
- Self-hosted observability tools (CX33 has 8GB RAM, not viable)
- PostHog (consolidation option for Phase 3.11 evaluation)

## Functional Requirements

### FR1: Error Tracking (Sentry)

Server-side Sentry (`@sentry/node`) captures Express errors, unhandled rejections, and WebSocket handler exceptions. Client-side Sentry (`@sentry/nextjs`) captures JS exceptions, unhandled promise rejections, and CSP violations. Errors include structured context (request ID, user ID where available, route). Source maps uploaded at build time for readable client-side stack traces.

### FR2: Uptime Monitoring (Better Stack)

External monitor pings `https://app.soleur.ai/health` at 3-minute intervals. Alerts on failure (HTTP non-200 or timeout). Free tier: 5 monitors.

### FR3: Structured Logging (Pino)

Replace all `console.log`/`console.error`/`console.warn` calls with Pino logger. JSON output with log levels (info, warn, error), timestamps, request IDs, and tagged contexts (`[ws]`, `[agent]`, `[sec]`, etc.). Request ID middleware for Express routes.

### FR4: Telegram Alerting

Sentry and Better Stack alerts route to Telegram via webhook/bot integration. Alerts reach the founder's mobile device. No email-only alerting (risk of inbox burial).

### FR5: Enhanced Health Endpoint

Enrich `/health` response with: version (from build-time env var or package.json), Supabase connectivity check, uptime, and memory usage. Return HTTP 200 for healthy, 503 for degraded. Model after telegram-bridge's richer health endpoint.

### FR6: Post-Deploy Version Verification

CI workflow verifies that the deployed version matches the expected tag by checking the `/health` response version field. Fail the deploy pipeline if version mismatch detected.

## Technical Requirements

### TR1: CSP Compatibility

Add Sentry domains to CSP directives in `lib/csp.ts`: `*.ingest.sentry.io` in `connect-src` for error reporting. Update CSP tests in `test/csp.test.ts`. Do NOT add Sentry to `script-src` if using the npm package (bundled, not loaded from CDN).

### TR2: Next.js Error Boundaries

Add `error.tsx` and `global-error.tsx` for Sentry to capture rendering errors. These do not currently exist anywhere in the app directory.

### TR3: Environment Variables

New Doppler secrets: `SENTRY_DSN` (server-side), `NEXT_PUBLIC_SENTRY_DSN` (client-side, baked at build time). Follow existing patterns: Dockerfile ARGs for `NEXT_PUBLIC_*`, runtime env-file for server-only. Agent subprocess environment (`agent-env.ts`) must NOT include Sentry DSN.

### TR4: Security Constraints

- `x-nonce` header must never be logged or sent to external services
- Error sanitizer (`error-sanitizer.ts`) should forward raw errors to Sentry BEFORE sanitizing for client
- Sentry SDK must not capture sensitive env vars (BYOK_ENCRYPTION_KEY, SUPABASE_SERVICE_ROLE_KEY, etc.)

### TR5: Docker and Infrastructure

No infrastructure changes required (SaaS-only tools). Dockerfile needs `NEXT_PUBLIC_SENTRY_DSN` as a build ARG. CI workflow needs Sentry auth token for source map uploads. Docker log rotation unchanged — structured logging improves what's captured, not where it goes.

### TR6: Credential Management

Follow existing credential monitoring pattern: Doppler provisioning with per-environment isolation, expiry monitoring for service tokens, rotation runbook. Sentry DSN does not expire but auth tokens for source maps do.
