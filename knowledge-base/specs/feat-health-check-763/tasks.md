# Tasks: fix telegram-bridge deploy health check

## Phase 1: Setup

- [ ] 1.1 Read existing `apps/telegram-bridge/src/health.ts` and `apps/telegram-bridge/test/health.test.ts`
- [ ] 1.2 Read `.github/workflows/telegram-bridge-release.yml` deploy step
- [ ] 1.3 Read `apps/telegram-bridge/Dockerfile` HEALTHCHECK directive

## Phase 2: Core Implementation

- [ ] 2.1 Add `/readyz` endpoint to `apps/telegram-bridge/src/health.ts`
  - [ ] 2.1.1 Add readiness check route returning 200 when CLI ready, 503 otherwise
  - [ ] 2.1.2 Return JSON body with `ready` boolean and `cli` state string
  - [ ] 2.1.3 Only accept GET method (return 404 for others)
- [ ] 2.2 Update CI deploy health check in `.github/workflows/telegram-bridge-release.yml`
  - [ ] 2.2.1 Replace `curl -sf` with HTTP status code capture (`-w '%{http_code}'`)
  - [ ] 2.2.2 Accept HTTP 200 or 503 as passing (container is alive)
  - [ ] 2.2.3 Reduce retries from 20 to 12 (60s total -- only waiting for endpoint, not CLI)
  - [ ] 2.2.4 Log attempt number and HTTP status for debugging
  - [ ] 2.2.5 Print response body on success for deploy log visibility
- [ ] 2.3 Update Dockerfile HEALTHCHECK to tolerate degraded state
  - [ ] 2.3.1 Add fallback grep for `"bot":"running"` when `curl -sf` fails

## Phase 3: Testing

- [ ] 3.1 Add `/readyz` tests to `apps/telegram-bridge/test/health.test.ts`
  - [ ] 3.1.1 Returns 200 when CLI is ready (cliProcess set, cliState="ready")
  - [ ] 3.1.2 Returns 503 when CLI is connecting (cliState="connecting")
  - [ ] 3.1.3 Returns 503 when CLI is in error state (cliState="error")
  - [ ] 3.1.4 Returns 503 when cliProcess is null even if state is ready
  - [ ] 3.1.5 Returns 404 for POST to /readyz
  - [ ] 3.1.6 Response body includes `ready` boolean and `cli` string
- [ ] 3.2 Verify all 8 existing health tests still pass
- [ ] 3.3 Run `bun test` from `apps/telegram-bridge/`
