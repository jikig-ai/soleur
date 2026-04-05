---
module: web-platform
date: 2026-04-05
problem_type: integration_issue
component: tooling
symptoms:
  - "Sentry project soleur-web-platform has zero events ever despite captureException calls in code"
  - "Setup failure error not appearing in Sentry API queries (24h and 14d ranges)"
  - "Manual test event via curl to same DSN was received within 60 seconds"
root_cause: config_error
resolution_type: documentation_update
severity: high
tags: [sentry, observability, docker, doppler, env-vars, verification]
---

# Sentry Server-Side SDK Not Sending Events from Production

## Problem

During follow-through verification of PR #1494 (error handling for project
setup failures), discovered that the Sentry server-side SDK has NEVER sent
any events from the production web-platform container. The `captureException`
call at `setup/route.ts:123` executes when setup fails, but no event appears
in the Sentry project.

## Investigation

1. **Verified DSN is valid:** Sent a manual test event via `curl` directly
   to the DSN endpoint (`ingest.de.sentry.io`). Event appeared in Sentry
   within 60 seconds. DSN is not the problem.

2. **Verified code integration:**
   - `sentry.server.config.ts` calls `Sentry.init({ dsn: process.env.SENTRY_DSN })`
   - `server/index.ts` imports sentry config as first import (line 3)
   - `@sentry/nextjs` is a production dependency (not devDep)
   - `next.config.ts` wraps with `withSentryConfig`
   - esbuild marks `@sentry/nextjs` as `--external` (runtime import, not inlined)

3. **Verified Doppler has the secret:** `SENTRY_DSN` exists in Doppler `prd`
   config. `ci-deploy.sh` downloads ALL prd secrets as Docker env file via
   `doppler secrets download --no-file --format docker`.

4. **Could not verify container env:** SSH to server timed out
   (`app.soleur.ai:22`), then direct IP (`135.181.45.178`) returned
   "agent refused operation" (SSH key locked). Cannot confirm `SENTRY_DSN`
   is in the container's `process.env`.

5. **Checked Sentry API regions:** DSN uses `ingest.de.sentry.io` (EU).
   Queried both `sentry.io` and `de.sentry.io` API endpoints. Zero events
   on both.

## Root Cause

Most likely: `SENTRY_DSN` is not reaching the container's runtime
environment. The Sentry SDK calls `Sentry.init({ dsn: process.env.SENTRY_DSN })`
at server startup. If `SENTRY_DSN` is `undefined`, the SDK initializes in
no-op mode -- `captureException` silently does nothing.

The exact mechanism by which Doppler's `prd` config fails to deliver
`SENTRY_DSN` to the container is unknown. Verification requires SSH access
to run `docker exec soleur-web-platform printenv SENTRY_DSN`.

## Solution

Filed #1533 to track the Sentry integration fix. Resolution requires:

1. SSH into server and verify `printenv SENTRY_DSN` in container
2. If missing, investigate `doppler secrets download` output format
3. If present, add a startup log line: `console.log('Sentry DSN:', process.env.SENTRY_DSN ? 'set' : 'NOT SET')`
4. Consider adding Sentry DSN presence to the `/health` endpoint response

## Key Insight

A valid DSN in Doppler config does not guarantee the env var reaches the
container runtime. The deployment pipeline has multiple handoff points
(Doppler download -> env file -> docker run --env-file -> process.env) and
any can silently fail. Runtime env var verification should be part of
deployment health checks, not just build-time configuration validation.

## Session Errors

1. **Magic link redirect not processed by app** -- Supabase `generate_link`
   returned an action_link URL with auth tokens in the `#fragment`. Navigating
   to it in Playwright landed on `/login#access_token=...` but the app's
   client-side code didn't process the fragment, redirecting to login.
   Recovery: Used email OTP flow instead (called `generate_link` after app
   sent OTP to get the current OTP code).
   **Prevention:** For Playwright auth, always use the OTP flow (generate_link
   to get the code, not the action_link URL). The magic link flow requires
   client-side hash processing that Playwright navigation doesn't trigger.

2. **Sentry API `statsPeriod=1h` rejected** -- Plan specified `statsPeriod=1h`
   for Sentry queries. API returned "Invalid stats_period. Valid choices are
   '', '24h', and '14d'". Recovery: Switched to `statsPeriod=24h`.
   **Prevention:** Sentry API `statsPeriod` only accepts `24h` and `14d`
   (not arbitrary intervals). Update plan templates to use `24h`.

3. **SSH access blocked** -- Could not SSH to production server (timeout on
   hostname, key agent refused on IP). Recovery: Verified via Doppler config
   and code review instead. Filed the gap as #1533.
   **Prevention:** Ensure SSH key is unlocked before sessions requiring
   production access. Consider adding env var verification to the `/health`
   endpoint so SSH is never needed for this check.

4. **Workspace permission bug exposed unexpected error** -- Expected a "git
   clone failed" error but got "rm -rf permission denied" because the existing
   workspace had root-owned files. Recovery: Filed #1534. The verification
   still succeeded (AC2/AC3 verified with this different error).
   **Prevention:** Fix workspace provisioning to ensure consistent file
   ownership (UID 1001) from initial creation.

## Related

- [silent-setup-failure-no-error-capture-20260403](../integration-issues/silent-setup-failure-no-error-capture-20260403.md) -- The original bug this verification follows up on
- [production-observability-sentry-pino-health-web-platform-20260328](../integration-issues/production-observability-sentry-pino-health-web-platform-20260328.md) -- Prior Sentry setup session
- [2026-03-28-unapplied-migration-command-center-chat-failure](../2026-03-28-unapplied-migration-command-center-chat-failure.md) -- Prior session where SENTRY_DSN was suspected missing from container
- GitHub issues: #1533 (Sentry fix), #1534 (workspace permissions)

## Tags

category: integration-issues
module: web-platform
