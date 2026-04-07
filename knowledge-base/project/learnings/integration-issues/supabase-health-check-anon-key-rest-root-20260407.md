---
module: System
date: 2026-04-07
problem_type: integration_issue
component: authentication
symptoms:
  - "/health returns supabase: error despite Supabase being reachable"
  - "Health check reports false negative for weeks without being caught by deploy verification"
root_cause: wrong_api
resolution_type: code_fix
severity: medium
tags: [supabase, health-check, anon-key, service-role-key, rest-api]
---

# Troubleshooting: Supabase Health Check False Negative Due to Anon Key on REST Root

## Problem

The production health endpoint (`/health`) perpetually returned `supabase: "error"` despite the Supabase service client working correctly for all API operations. This masked actual connectivity status and went undetected because the deploy health verification only checks `status` and `version`, not `supabase`.

## Environment

- Module: System (server/health.ts)
- Affected Component: Health check probe in `apps/web-platform/server/health.ts`
- Date: 2026-04-07

## Symptoms

- `curl https://app.soleur.ai/health` returns `{"supabase": "error"}` with version 0.14.10
- Zero Sentry errors for Supabase in the last 24h
- `SUPABASE_URL` confirmed set correctly in the container via SSH
- All actual API calls (`/api/repo/install`, `/api/repo/create`) work correctly

## What Didn't Work

**Direct solution:** The problem was identified on the first investigation attempt by reproducing the exact health check call (`/rest/v1/` with only `apikey` header) and observing the 401.

## Session Errors

**`draft-pr` script broke the worktree directory**

- **Recovery:** Ran `git worktree prune` and recreated the worktree
- **Prevention:** The `worktree-manager.sh draft-pr` command uses `cd` internally which can break the shell's CWD if the worktree is removed and recreated. Investigate and fix the script's directory handling.

**Stale Playwright cookie from prior e2e test session**

- **Recovery:** Cleared all cookies via `document.cookie` manipulation and re-authenticated
- **Prevention:** When testing authenticated endpoints via Playwright, always verify the cookie identity matches the expected user before making API calls. Clear cookies explicitly at the start of each verification session.

**Magic link hash fragment not processed by client-side JS**

- **Recovery:** Manually set the auth cookie via `document.cookie` with base64-encoded session data
- **Prevention:** For programmatic auth in Playwright, set cookies directly rather than relying on client-side JS hash fragment processing. The Supabase SSR client's `onAuthStateChange` may not fire in isolated browser profiles.

**Plan prescribed wrong `action_link` path (`properties.action_link`)**

- **Recovery:** Checked response keys and found `action_link` at the top level
- **Prevention:** The Supabase `generate_link` response has `action_link` as a top-level field, not under `properties`. Verify API response structure before prescribing paths in plans.

## Solution

Changed the health check to use the service role key (which the server already has for `createServiceClient()`) instead of the anon key.

**Code changes:**

```typescript
// Before (broken):
const response = await fetch(`${serverUrl()}/rest/v1/`, {
  headers: { apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "" },
  signal: AbortSignal.timeout(2000),
});

// After (fixed):
const key = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const response = await fetch(`${serverUrl()}/rest/v1/`, {
  headers: {
    apikey: key,
    Authorization: `Bearer ${key}`,
  },
  signal: AbortSignal.timeout(2000),
});
```

Key design decisions:

1. Use `SUPABASE_SERVICE_ROLE_KEY!` directly (no fallback to anon key) — a missing service role key is a deployment bug that should surface as `supabase: error`
2. Include both `apikey` and `Authorization` headers — Supabase REST API requires both for authenticated access to `/rest/v1/` root

## Why This Works

1. **Root cause:** The Supabase REST API root endpoint (`/rest/v1/`) returns 401 when accessed with only the `apikey` header (anon key). It requires both `apikey` AND `Authorization: Bearer <key>` headers with a key that has sufficient privileges.
2. **Why the fix works:** The service role key with both headers returns 200 on `/rest/v1/` root because it bypasses RLS and has full access.
3. **Why no fallback:** If `SUPABASE_SERVICE_ROLE_KEY` is missing, the health check correctly reports "error" — this matches reality (the server cannot perform privileged operations without it).

## Prevention

- Health check probes should use the same credential tier as the services they verify. If the service uses a service role key, the health check should too.
- Deploy health verification should check all fields, not just `status` and `version`. Filed as issue #1703.
- When adding a health check for an external service, test the exact probe call in isolation before deploying.

## Related Issues

- See also: [supabase-identities-null-email-first-users-20260403.md](supabase-identities-null-email-first-users-20260403.md)
- See also: [2026-04-06-supabase-server-side-connectivity-docker-container.md](2026-04-06-supabase-server-side-connectivity-docker-container.md)
- Follow-up: #1703 (add supabase connectivity check to deploy health verification)
