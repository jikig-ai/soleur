# Tasks: Production Observability

## Phase 1: Structured Logging (Pino)

- [ ] 1.1 Install dependencies: `pino` (dep), `pino-pretty` (devDep)
- [ ] 1.2 Create `server/logger.ts` — singleton Pino logger with child logger factory, `x-nonce` redaction
- [ ] 1.3 Add `pino` to esbuild `--external` in `build:server` script
- [ ] 1.4 Migrate `server/ws-handler.ts` FIRST — replace 21 `console.*` calls, verify esbuild builds
- [ ] 1.5 Migrate `server/agent-runner.ts` — replace 17 calls with child logger `agent`
- [ ] 1.6 Migrate `server/index.ts` — replace 4 calls
- [ ] 1.7 Migrate `server/workspace.ts` — replace 2 calls
- [ ] 1.8 Migrate `server/domain-router.ts` — replace 1 call
- [ ] 1.9 Migrate `lib/auth/resolve-origin.ts` — replace 1 call
- [ ] 1.10 Migrate `lib/auth/validate-origin.ts` — replace 1 call
- [ ] 1.11 Migrate `app/(auth)/callback/route.ts` — replace 4 calls
- [ ] 1.12 Migrate `app/api/accept-terms/route.ts` — replace 2 calls
- [ ] 1.13 Migrate `app/api/keys/route.ts` — replace 1 call
- [ ] 1.14 Migrate `app/api/workspace/route.ts` — replace 1 call
- [ ] 1.15 Migrate `app/api/webhooks/stripe/route.ts` — replace 1 call
- [ ] 1.16 Verify: all tests pass, JSON output in production, pretty-print in dev

## Phase 2: Sentry Integration

- [ ] 2.1 Install `@sentry/nextjs`
- [ ] 2.2 Create `sentry.server.config.ts` — server-side init, `tracesSampleRate: 0`, `beforeSend` filtering
- [ ] 2.3 Create `sentry.client.config.ts` — client-side init, `tracesSampleRate: 0`
- [ ] 2.4 Create `instrumentation.ts` — `onRequestError` export only (register() is a no-op for custom servers)
- [ ] 2.5 Create `app/global-error.tsx` — root error boundary with Sentry capture
- [ ] 2.6 Create `app/error.tsx` — app-level error boundary with Sentry capture
- [ ] 2.7 Add `import "../sentry.server.config"` as FIRST import in `server/index.ts`
- [ ] 2.8 Wrap `next.config.ts` with `withSentryConfig()` (org, project, authToken, source maps)
- [ ] 2.9 Add `*.ingest.sentry.io` to `connect-src` and `report-uri` directive in `lib/csp.ts`
- [ ] 2.10 Update CSP tests in `test/csp.test.ts` for Sentry domain and `report-uri`
- [ ] 2.11 Add `Sentry.captureException()` at call sites in `server/ws-handler.ts` catch blocks
- [ ] 2.12 Add `Sentry.captureException()` at call sites in `server/agent-runner.ts` catch blocks
- [ ] 2.13 Add `--external:@sentry/nextjs` to esbuild `build:server` and `next.config.mjs` scripts
- [ ] 2.14 Add `SENTRY_DSN` and `NEXT_PUBLIC_SENTRY_DSN` to `.env.example`
- [ ] 2.15 Add `ARG NEXT_PUBLIC_SENTRY_DSN`, `ARG SENTRY_AUTH_TOKEN`, `ARG SENTRY_ORG`, `ARG SENTRY_PROJECT` to Dockerfile builder stage
- [ ] 2.16 Add Sentry build-args to `.github/workflows/reusable-release.yml` Docker build step
- [ ] 2.17 Verify: CSP tests pass, error boundaries render, no sensitive data in Sentry events

## Phase 3: Enhanced Health Endpoint + Deploy Verification

- [ ] 3.1 Add `checkSupabase()` — lightweight REST API connectivity check (not business table query)
- [ ] 3.2 Enrich `/health` response: version, supabase status, uptime, memory
- [ ] 3.3 Return 503 when degraded (Supabase unreachable)
- [ ] 3.4 Add `ARG BUILD_VERSION` and `ENV BUILD_VERSION` to Dockerfile
- [ ] 3.5 Pass `BUILD_VERSION` to Docker build in reusable-release.yml
- [ ] 3.6 Replace existing CI health verification with version-aware check (12 attempts x 10s = 120s)
- [ ] 3.7 Verify: health endpoint returns enriched response, Docker healthcheck still works

## Phase 4: External Services Setup

- [ ] 4.1 Create Sentry project (Playwright MCP or CLI)
- [ ] 4.2 Get DSN values, construct `report-uri` URL from DSN
- [ ] 4.3 Store in Doppler: `SENTRY_DSN`, `NEXT_PUBLIC_SENTRY_DSN`, `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_CSP_REPORT_URI`
- [ ] 4.4 Add `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` as GitHub secrets
- [ ] 4.5 Create Better Stack account and uptime monitor (Playwright MCP)
- [ ] 4.6 Configure Sentry Telegram webhook integration
- [ ] 4.7 Configure Better Stack Telegram notification channel
- [ ] 4.8 Test: trigger synthetic error, verify Telegram alert received
- [ ] 4.9 Test: simulate health failure, verify Better Stack alerts to Telegram
- [ ] 4.10 Record Sentry and Better Stack in expenses.md (EUR 0/month free tiers)
- [ ] 4.11 Flag CLO: new sub-processors need privacy policy disclosure (#1048)

## Phase 5: Testing & Verification

- [ ] 5.1 Run full test suite — all existing tests pass
- [ ] 5.2 Verify Pino JSON output in Docker container
- [ ] 5.3 Verify Sentry receives test error event
- [ ] 5.4 Verify source maps produce readable client-side stack traces
- [ ] 5.5 Verify CSP `report-uri` sends violations to Sentry
- [ ] 5.6 Verify `/health` returns version, 503 on degraded
- [ ] 5.7 Verify CI deploy pipeline checks version match
- [ ] 5.8 Verify Better Stack monitors health endpoint
- [ ] 5.9 Verify Telegram receives alerts from both Sentry and Better Stack
