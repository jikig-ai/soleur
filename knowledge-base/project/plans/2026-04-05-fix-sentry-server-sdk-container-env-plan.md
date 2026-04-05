---
title: "fix: Sentry server-side SDK not sending events from production container"
type: fix
date: 2026-04-05
---

# fix: Sentry server-side SDK not sending events from production container

## Overview

The Sentry server-side SDK (`@sentry/nextjs`) has never sent a single event
from the production web-platform container. Zero events across all time
despite `captureException` calls in 12+ error handlers across ws-handler,
agent-runner, and setup/route. The DSN is valid (manual curl test received by
Sentry within 60s) and the secret exists in Doppler prd. The gap is in the
env injection pipeline between Doppler and the container's `process.env`.

Closes #1533

## Problem Statement / Motivation

All server-side errors are silently lost. No alerting on production
exceptions -- setup failures, WebSocket errors, and agent runner crashes
are invisible. This undermines the entire observability stack deployed
in the production observability feature (PR #1494).

## Research Insights

### Existing Learnings Applied

- `knowledge-base/project/learnings/integration-issues/sentry-zero-events-production-verification-20260405.md`:
  Documented the investigation -- DSN valid, code integration correct,
  SSH access blocked. Root cause narrowed to `SENTRY_DSN` not reaching
  `process.env` in the container.
- `knowledge-base/project/learnings/2026-03-28-unapplied-migration-command-center-chat-failure.md`:
  First session where zero Sentry events were observed. Noted as a side
  finding but not investigated.
- Constitution rule: "Never use `doppler run -- docker run` to inject
  secrets into Docker containers -- Docker containers do not inherit the
  parent shell's environment."

### Code Analysis

The deployment pipeline has three handoff points where `SENTRY_DSN` could
be lost:

1. **Doppler download**: `doppler secrets download --no-file --format docker
   --project soleur --config prd` -- Verified: `SENTRY_DSN` is in the
   output (correct `KEY=VALUE` format, no quoting issues, clean URL value).

2. **Env file write**: Written to temp file with `chmod 600`. The file
   is passed to `docker run --env-file`. This should work.

3. **Container process.env**: The Node.js process reads `process.env.SENTRY_DSN`
   in `sentry.server.config.ts`. If the env var is present, `Sentry.init()`
   configures the SDK. If absent, the SDK initializes in no-op mode --
   `captureException` silently does nothing.

### Build-Time vs Runtime

- **Client-side (`NEXT_PUBLIC_SENTRY_DSN`)**: Baked at build time via
  Docker `ARG` in the builder stage. This is passed as a `build-arg` in
  `reusable-release.yml:300`. Client-side Sentry should work.
- **Server-side (`SENTRY_DSN`)**: Must be available at runtime via
  `process.env`. The Dockerfile does NOT declare `SENTRY_DSN` as an `ARG`
  in the runner stage (correct -- it should come from `--env-file`).
  The `ci-deploy.sh` script handles runtime injection.

### Key Architecture Points

- Custom server (`server/index.ts`) imports `sentry.server.config.ts` as
  first import (line 3). The config calls `Sentry.init({ dsn: process.env.SENTRY_DSN })`.
- esbuild bundles the server with `--external:@sentry/nextjs`, so the
  Sentry import resolves at runtime from `node_modules`.
- `@sentry/nextjs` is a production dependency (not devDep), installed
  by `npm ci --omit=dev` in the runner stage.
- `instrumentation.ts` documents that `register()` is NOT called with
  custom servers -- server-side init happens via direct import.

## Proposed Solution

Diagnose and fix the env injection pipeline in three phases:

### Phase 1: Diagnose (SSH verification)

SSH into the production server and check the container environment:

```text
docker exec soleur-web-platform printenv SENTRY_DSN
```

**If empty/missing** -- the env file pipeline is broken. Investigate:

```text
doppler secrets download --no-file --format docker --project soleur --config prd | grep SENTRY_DSN
docker inspect soleur-web-platform --format='{{range .Config.Env}}{{println .}}{{end}}' | grep SENTRY
```

**If present** -- the env var reaches the container but Sentry SDK is not
initializing properly. Add diagnostic logging (Phase 2).

### Phase 2: Fix (depends on Phase 1 findings)

**Scenario A: SENTRY_DSN missing from container env**

The most likely cause based on all evidence. Possible sub-causes:

1. **Doppler service token scope mismatch**: The server's `DOPPLER_TOKEN`
   might be scoped to a different config than `prd`. Verify with:
   `doppler secrets --only-names` (using the server's token, not our local one).

2. **Env file format issue**: Some Docker versions have issues with
   certain `--env-file` formats (trailing whitespace, UTF-8 BOM, etc.).
   Check the downloaded env file content.

3. **Stale env file**: If a previous deploy failed partway, the env file
   might have been cleaned up before the current container read it.
   However, ci-deploy.sh uses the same env file for both canary and
   production, so this is unlikely.

**Scenario B: SENTRY_DSN present but SDK not initializing**

Less likely but possible:

1. **esbuild tree-shaking the side-effect import**: The
   `import "../sentry.server.config"` is a side-effect-only import.
   esbuild might tree-shake it if `sideEffects` is not configured.
   Verify by checking the bundle output for Sentry.init call.

2. **Module resolution issue**: The CJS bundle trying to require
   `@sentry/nextjs` might fail silently in the container. Add a
   try/catch around the import or check for module resolution errors.

3. **Network egress blocked**: The container might not be able to reach
   `ingest.de.sentry.io`. Test with `curl` from inside the container.

**Scenario C: SDK initializes but events not sent**

Least likely:

1. **`beforeSend` filtering**: The current `beforeSend` only strips
   headers -- it should not drop events.
2. **Missing `Sentry.flush()`**: Long-running server process should
   not need explicit flush (transport sends asynchronously), but
   verify event buffer is not stuck.

### Phase 3: Verify and Harden

1. **Add startup diagnostic log**: Log whether `SENTRY_DSN` is set at
   server startup (`server/index.ts`). This makes future diagnosis
   instant without SSH.

2. **Add SENTRY_DSN to `/health` response**: Include a `sentry` field
   showing whether the DSN is configured (not the DSN value itself).

3. **Send a test event on startup**: Call `Sentry.captureMessage("Server
   startup")` at server startup and verify it appears in Sentry. This
   confirms the full pipeline works.

4. **Add post-deploy Sentry verification**: After deploy, query the
   Sentry API for the startup event within a timeout window.

## Technical Considerations

- **Architecture impact**: None -- this is a config/deployment fix.
- **Performance impact**: Adding a startup `captureMessage` adds one
  HTTP request to Sentry at server start. Negligible.
- **Security**: The `/health` endpoint must NOT expose the DSN value,
  only whether it is configured (boolean).
- **Backward compatibility**: No breaking changes.

## Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/server/index.ts` | Add SENTRY_DSN presence log at startup, add `sentry: 'configured'\|'not-configured'` to health response, add startup test event |
| `apps/web-platform/sentry.server.config.ts` | Add `debug: true` conditionally for diagnosing init failures (remove after fix confirmed) |
| `apps/web-platform/infra/ci-deploy.sh` | (only if env file pipeline is broken) Fix env injection |
| `.github/workflows/web-platform-release.yml` | (only if post-deploy Sentry check added) Add verification step |

## Acceptance Criteria

- [ ] **AC1: SENTRY_DSN present in container env** -- `docker exec soleur-web-platform printenv SENTRY_DSN` returns the DSN value
- [ ] **AC2: Sentry receives events** -- Query Sentry API and confirm at least one event exists in the `soleur-web-platform` project after fix is deployed
- [ ] **AC3: Health endpoint reports Sentry status** -- `curl https://app.soleur.ai/health | jq .sentry` returns `"configured"`
- [ ] **AC4: Startup log confirms DSN** -- Server logs on startup include a line indicating SENTRY_DSN is set
- [ ] **AC5: Existing error handlers work** -- Trigger an error (e.g., setup failure) and verify it appears in Sentry within 60 seconds

## Test Scenarios

### Scenario 1: Verify Container Environment

**Given** a deployed web-platform container
**When** inspecting the container environment
**Then** `SENTRY_DSN` is present and matches the Doppler prd value

### Scenario 2: Server Startup Sentry Event

**Given** a freshly deployed web-platform container with the fix
**When** the server starts
**Then** a "Server startup" message appears in Sentry within 60 seconds

**API verify:** `curl -sH "Authorization: Bearer <SENTRY_API_TOKEN>" "https://de.sentry.io/api/0/projects/jikigai/soleur-web-platform/events/?query=Server+startup&statsPeriod=24h" | jq 'length > 0'` expects `true`

### Scenario 3: Health Endpoint Sentry Status

**Given** a running web-platform container
**When** querying the health endpoint
**Then** the response includes `"sentry": "configured"`

**API verify:** `curl -sf https://app.soleur.ai/health | jq -r '.sentry'` expects `configured`

### Scenario 4: Error Handler Integration

**Given** a running web-platform with Sentry configured
**When** a repo setup failure occurs (permission denied, clone error)
**Then** a Sentry event is captured with the exception details

### Scenario 5: Graceful Degradation Without DSN

**Given** a web-platform container started without `SENTRY_DSN`
**When** an error occurs
**Then** the server continues operating normally (no crash), and the health endpoint shows `"sentry": "not-configured"`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/deployment debugging fix.

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| SSH access blocked (prior session had key agent issues) | Unlock SSH key before starting work. Fall back to `hcloud` CLI or Playwright for server console. |
| Env file pipeline works correctly (SENTRY_DSN is present) | If present, shift diagnosis to SDK initialization. Add `debug: true` to Sentry config temporarily. |
| Sentry startup event adds latency | `captureMessage` is async and non-blocking. No measurable impact. |
| Exposing internal state via health endpoint | Only expose boolean configured/not-configured, never the DSN value. |

## References and Research

### Internal References

- `apps/web-platform/sentry.server.config.ts` -- Server-side Sentry init
- `apps/web-platform/server/index.ts:3` -- Sentry config import (first import)
- `apps/web-platform/Dockerfile:15` -- `NEXT_PUBLIC_SENTRY_DSN` build ARG (client only)
- `apps/web-platform/infra/ci-deploy.sh:33` -- Doppler secrets download for env file
- `apps/web-platform/infra/ci-deploy.sh:138` -- `--env-file` passed to docker run
- `.github/workflows/reusable-release.yml:300` -- Build-time Sentry args
- `apps/web-platform/instrumentation.ts` -- Documents that register() is NOT called with custom servers

### Related Issues

- #1533 -- This issue (Sentry server-side SDK not sending events)
- #1498 / PR #1494 -- Error handling for setup failures (where the gap was discovered)
- Learning: `sentry-zero-events-production-verification-20260405.md`
- Learning: `2026-03-28-unapplied-migration-command-center-chat-failure.md`
