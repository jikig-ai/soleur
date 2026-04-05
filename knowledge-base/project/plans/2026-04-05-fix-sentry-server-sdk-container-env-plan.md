---
title: "fix: Sentry server-side SDK not sending events from production container"
type: fix
date: 2026-04-05
---

# fix: Sentry server-side SDK not sending events from production container

## Enhancement Summary

**Deepened on:** 2026-04-05
**Sections enhanced:** 6
**Research sources:** Context7 (Sentry docs), WebSearch (esbuild tree-shaking, Docker env-file, Sentry troubleshooting), institutional learnings (5 relevant)

### Key Improvements

1. Added `Sentry.flush()` on SIGTERM as a best-practice hardening step (Sentry docs recommend this for all Node.js servers)
2. Added `debug: true` diagnostic strategy with specific log patterns to look for during troubleshooting
3. Identified middleware `/monitoring` tunnel risk (not currently active but documents the pitfall for future reference)
4. Added esbuild `--metafile` diagnostic step to verify side-effect import preservation in the bundle
5. Expanded diagnosis decision tree with concrete commands for each scenario
6. Added Doppler fallback learning from #1493 -- prior silent `.env` fallback was fixed, but validates the fix is still in place

### New Considerations Discovered

- `@sentry/nextjs` declares `"sideEffects": false` in package.json, but since esbuild marks it as `--external`, this does not affect bundling -- the tree-shaking concern is limited to local files only
- Sentry SDK with `debug: true` logs to stderr -- in Docker, these appear in `docker logs` and can be searched with `grep -i sentry`
- No `Sentry.flush()` on SIGTERM exists -- events in the transport buffer may be lost during container restarts (Docker sends SIGTERM then SIGKILL after 10s grace period)
- The middleware matcher `/((?!_next/static|...).*)`  would catch `/monitoring` if a Sentry tunnel were added in the future -- document this as a known pitfall

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
- `knowledge-base/project/learnings/integration-issues/2026-04-03-doppler-not-installed-env-fallback-outage.md`:
  The Doppler `.env` fallback was removed in favor of hard failures.
  `resolve_env_file()` now exits with specific error messages when Doppler
  is unavailable. This fix means if SENTRY_DSN were missing from Doppler,
  the deploy would fail entirely (good). But it also means we can rule out
  "stale .env fallback" as a possible cause -- the current deploy either
  gets ALL Doppler prd secrets or fails completely.
- `knowledge-base/project/learnings/integration-issues/production-observability-sentry-pino-health-web-platform-20260328.md`:
  Documents the original Sentry integration. Confirms: custom server init
  via direct import, `--external:@sentry/nextjs` in esbuild, `beforeSend`
  strips sensitive headers only.
- Constitution rule: "Never use `doppler run -- docker run` to inject
  secrets into Docker containers -- Docker containers do not inherit the
  parent shell's environment."

### Sentry SDK Documentation Findings (Context7)

**Custom server init pattern**: Sentry docs confirm that for custom servers,
`Sentry.init()` must be called as the very first import, before `next`,
`http`, or any app code. The current code does this correctly
(`server/index.ts` line 3: `import "../sentry.server.config"`).

**Debug mode**: Setting `debug: true` in `Sentry.init()` enables verbose
logging to stderr. This is the recommended first troubleshooting step.
When enabled, the SDK logs:

- Whether the DSN is valid
- Whether events are being created
- Whether the transport is sending events
- Any errors during event submission

**Automatic DSN reading**: The Sentry SDK can auto-read from `SENTRY_DSN`
env var if `dsn` option is omitted from `init()`. The current code
explicitly reads `process.env.SENTRY_DSN` which is equivalent but more
explicit.

**Graceful shutdown**: Sentry docs recommend calling `Sentry.flush(2000)`
on `SIGTERM`/`SIGINT` to ensure all pending events are sent before
process exit. The current server has NO shutdown handler. While this does
not explain zero events (the server runs continuously), it means events
captured just before a container restart could be lost.

### esbuild Side-Effect Analysis

The esbuild command (`--bundle --external:@sentry/nextjs`) inlines local
files but keeps `@sentry/nextjs` as a runtime `require()`. The
`sentry.server.config.ts` is a side-effect-only module (no exports, just
`Sentry.init()`).

Key findings:

- esbuild with `--bundle` preserves side-effect imports by default
- `@sentry/nextjs` declares `"sideEffects": false` in package.json, but
  this is irrelevant because esbuild marks it as `--external` (tree-shaking
  does not analyze external packages)
- To verify the import is preserved, run esbuild with `--metafile=meta.json`
  and check the output for `sentry.server.config` in the module graph

### Docker env-file Analysis

Common `--env-file` failure modes:

1. **File format**: Must be `KEY=VALUE` per line, no quotes around values.
   Doppler `--format docker` outputs this correctly.
2. **File encoding**: UTF-8 BOM at file start can cause the first variable
   to be invisible. Doppler output has no BOM (verified locally).
3. **File permissions**: Docker daemon needs read access. `chmod 600` with
   `deploy:deploy` ownership should work since the deploy user runs Docker.
4. **Special characters**: Values with `#` are truncated (treated as
   comments). The SENTRY_DSN URL has no `#` characters (verified).

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

**If empty/missing** -- the env file pipeline is broken. Follow
Scenario A diagnosis below.

**If present** -- the env var reaches the container but Sentry SDK is not
initializing properly. Follow Scenario B diagnosis.

#### Scenario A Diagnosis: SENTRY_DSN Missing from Container Env

This is the most likely cause. Steps:

1. **Check all container env vars for Sentry**:

   ```text
   docker inspect soleur-web-platform --format='{{range .Config.Env}}{{println .}}{{end}}' | grep -i SENTRY
   ```

2. **Check Doppler download on the server** (uses the server's service token):

   ```text
   doppler secrets download --no-file --format docker --project soleur --config prd 2>/dev/null | grep SENTRY_DSN
   ```

3. **If Doppler download fails**: The service token may be expired or
   mis-scoped. Check:

   ```text
   cat /etc/default/webhook-deploy
   ```

   Verify `DOPPLER_TOKEN` is present and non-empty. Then try:

   ```text
   DOPPLER_TOKEN=$(grep DOPPLER_TOKEN /etc/default/webhook-deploy | cut -d= -f2) doppler secrets --only-names --project soleur --config prd
   ```

4. **If Doppler works but SENTRY_DSN is missing**: The secret was added
   to Doppler after the server's service token was created. Doppler
   service tokens are scoped to a config -- they see ALL secrets in that
   config. If the token works but SENTRY_DSN is absent, the secret may
   be in a different config (check `prd` vs `prd_terraform` vs `ci`).

#### Scenario B Diagnosis: SENTRY_DSN Present but SDK Not Initializing

1. **Temporarily add `debug: true`** to `sentry.server.config.ts`:

   ```typescript
   Sentry.init({
     dsn: process.env.SENTRY_DSN,
     debug: process.env.NODE_ENV !== "production" || process.env.SENTRY_DEBUG === "1",
     // ... rest of config
   });
   ```

   Deploy, then set `SENTRY_DEBUG=1` in Doppler prd temporarily and
   redeploy. Check `docker logs soleur-web-platform 2>&1 | grep -i sentry`
   for debug output.

2. **Verify esbuild preserves the side-effect import**: Run locally:

   ```text
   cd apps/web-platform
   npx esbuild server/index.ts --bundle --platform=node --target=node22 \
     --outfile=/tmp/test-server.cjs --external:@sentry/nextjs \
     --metafile=/tmp/meta.json
   grep sentry /tmp/test-server.cjs | head -5
   cat /tmp/meta.json | jq '.inputs | keys[] | select(contains("sentry"))'
   ```

   If `sentry.server.config` is not in the metafile inputs, esbuild
   tree-shook it.

3. **Test network egress from container**:

   ```text
   docker exec soleur-web-platform node -e "
     fetch('https://ingest.de.sentry.io/')
       .then(r => console.log('Status:', r.status))
       .catch(e => console.error('Error:', e.message))
   "
   ```

4. **Check module resolution**: Verify `@sentry/nextjs` is importable:

   ```text
   docker exec soleur-web-platform node -e "
     try { require('@sentry/nextjs'); console.log('OK') }
     catch(e) { console.error('FAIL:', e.message) }
   "
   ```

### Phase 2: Fix (depends on Phase 1 findings)

**Scenario A: SENTRY_DSN missing from container env**

Possible sub-causes and fixes:

1. **Doppler service token scope mismatch**: The server's `DOPPLER_TOKEN`
   might be scoped to a different config than `prd`. Fix: create a new
   service token scoped to `prd` and update `/etc/default/webhook-deploy`.

2. **Env file format issue**: Some Docker versions have issues with
   certain `--env-file` formats (trailing whitespace, UTF-8 BOM, etc.).
   Fix: validate the temp file content before passing to Docker.

3. **Stale env file**: The Doppler fallback removal (#1493) means deploys
   now fail entirely if Doppler is unavailable. If the container is
   running, it got its env from a successful Doppler download. The issue
   is more likely that SENTRY_DSN was added to Doppler AFTER the last
   deploy, and no redeploy occurred since.

**Scenario B: SENTRY_DSN present but SDK not initializing**

1. **esbuild tree-shaking**: If the side-effect import was removed, add
   explicit `Sentry.init()` call directly in `server/index.ts` instead
   of relying on a separate side-effect module import.

2. **Module resolution failure**: If `require('@sentry/nextjs')` fails
   in the container, the production `npm ci --omit=dev` may have excluded
   a transitive dependency. Fix: check `node_modules/@sentry/nextjs`
   existence in the runner image.

3. **Network egress blocked**: If the container cannot reach
   `ingest.de.sentry.io`, check if Docker network configuration or
   firewall rules block outbound HTTPS.

**Scenario C: SDK initializes but events not sent**

1. **`beforeSend` filtering**: The current `beforeSend` only strips
   headers -- it does not return `null` (which would drop events). Safe.
2. **Transport buffer stuck**: Add `Sentry.flush()` on SIGTERM to ensure
   events drain before container shutdown.

### Phase 3: Verify and Harden

1. **Add startup diagnostic log**: Log whether `SENTRY_DSN` is set at
   server startup (`server/index.ts`). This makes future diagnosis
   instant without SSH.

   ```typescript
   log.info({
     sentryConfigured: !!process.env.SENTRY_DSN,
     sentryEnvironment: process.env.NODE_ENV,
   }, "Sentry status");
   ```

2. **Add SENTRY_DSN to `/health` response**: Include a `sentry` field
   showing whether the DSN is configured (not the DSN value itself).

   ```typescript
   sentry: process.env.SENTRY_DSN ? "configured" : "not-configured",
   ```

3. **Send a test event on startup**: Call `Sentry.captureMessage("Server
   startup", "info")` at server startup and verify it appears in Sentry.
   This confirms the full pipeline works. Gate behind `SENTRY_DSN` check
   to avoid noise in development:

   ```typescript
   if (process.env.SENTRY_DSN) {
     Sentry.captureMessage(`Server startup v${process.env.BUILD_VERSION || "dev"}`, "info");
   }
   ```

4. **Add SIGTERM handler with Sentry flush** (Sentry best practice):

   ```typescript
   process.on("SIGTERM", async () => {
     log.info("SIGTERM received, flushing Sentry events...");
     await Sentry.flush(2000);
     process.exit(0);
   });
   ```

5. **Add post-deploy Sentry verification**: After deploy, query the
   Sentry API for the startup event within a timeout window.

## Technical Considerations

- **Architecture impact**: None -- this is a config/deployment fix.
- **Performance impact**: Adding a startup `captureMessage` adds one
  HTTP request to Sentry at server start. Negligible.
- **Security**: The `/health` endpoint must NOT expose the DSN value,
  only whether it is configured (boolean). The DSN is a public identifier
  (rate-limited by Sentry), but exposing it needlessly violates
  least-privilege.
- **Backward compatibility**: No breaking changes.
- **SIGTERM handling**: Docker sends SIGTERM, waits 10s grace period,
  then SIGKILL. The `Sentry.flush(2000)` timeout (2s) is well within
  this window.
- **Middleware pitfall**: If a Sentry tunnel (`/monitoring`) is ever
  added, the current middleware matcher would intercept it and redirect
  to `/login`. The matcher would need an exclusion for `/monitoring`.
  This is not relevant now but should be documented.

## Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/server/index.ts` | Add SENTRY_DSN presence log at startup, add `sentry` field to health response, add startup test event, add SIGTERM handler with `Sentry.flush()` |
| `apps/web-platform/sentry.server.config.ts` | Add conditional `debug: true` via `SENTRY_DEBUG` env var for diagnosing init failures |
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

### Scenario 6: SIGTERM Flushes Events

**Given** a running web-platform container with pending Sentry events
**When** the container receives SIGTERM (e.g., during deploy swap)
**Then** pending events are flushed within 2 seconds before exit

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/deployment debugging fix.

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| SSH access blocked (prior session had key agent issues) | Unlock SSH key before starting work. Fall back to `hcloud` CLI for server console access. |
| Env file pipeline works correctly (SENTRY_DSN is present) | If present, shift diagnosis to SDK initialization. Add `debug: true` to Sentry config temporarily via `SENTRY_DEBUG` env var. |
| Sentry startup event adds latency | `captureMessage` is async and non-blocking. No measurable impact on server startup time. |
| Exposing internal state via health endpoint | Only expose boolean configured/not-configured, never the DSN value. |
| SIGTERM handler interfering with graceful shutdown | 2-second `Sentry.flush` timeout is well within Docker's 10-second grace period. |
| esbuild tree-shaking the Sentry init | Verify with `--metafile` before and after changes. If tree-shaken, move init inline to `server/index.ts`. |

## References and Research

### Internal References

- `apps/web-platform/sentry.server.config.ts` -- Server-side Sentry init
- `apps/web-platform/server/index.ts:3` -- Sentry config import (first import)
- `apps/web-platform/Dockerfile:15` -- `NEXT_PUBLIC_SENTRY_DSN` build ARG (client only)
- `apps/web-platform/infra/ci-deploy.sh:33` -- Doppler secrets download for env file
- `apps/web-platform/infra/ci-deploy.sh:138` -- `--env-file` passed to docker run
- `.github/workflows/reusable-release.yml:300` -- Build-time Sentry args
- `apps/web-platform/instrumentation.ts` -- Documents that register() is NOT called with custom servers
- `apps/web-platform/middleware.ts:134-138` -- Middleware matcher (would catch `/monitoring` tunnel if added)

### Institutional Learnings

- `sentry-zero-events-production-verification-20260405.md` -- Prior investigation documenting the gap
- `2026-03-28-unapplied-migration-command-center-chat-failure.md` -- First observation of zero Sentry events
- `2026-04-03-doppler-not-installed-env-fallback-outage.md` -- Doppler fallback removal (rules out stale .env)
- `production-observability-sentry-pino-health-web-platform-20260328.md` -- Original Sentry integration docs
- `2026-03-29-doppler-service-token-config-scope-mismatch.md` -- Doppler token scope pitfall

### External References

- [Sentry Next.js Custom Server Init](https://github.com/getsentry/sentry-docs/blob/master/platform-includes/migration/javascript-v8/troubleshooting/javascript.nextjs.mdx) -- Official custom server pattern
- [Sentry Debug Mode](https://github.com/getsentry/sentry-javascript/blob/develop/docs/triaging.md) -- `debug: true` for troubleshooting
- [Sentry Graceful Shutdown](https://docs.sentry.io/platforms/javascript/guides/nextjs/) -- `Sentry.flush()` on SIGTERM
- [Sentry captureException Not Sending](https://github.com/getsentry/sentry-javascript/issues/15885) -- Known issue with event ID generated but no network request
- [Docker env-file Format](https://docs.docker.com/reference/cli/docker/container/run/) -- Official env-file spec
- [esbuild Tree Shaking](https://esbuild.github.io/api/) -- Side-effect preservation behavior

### Related Issues

- #1533 -- This issue (Sentry server-side SDK not sending events)
- #1498 / PR #1494 -- Error handling for setup failures (where the gap was discovered)
- #1493 -- Doppler not installed / silent .env fallback (related infrastructure fix)
