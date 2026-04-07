---
title: "chore: verify /api/repo/install and /api/repo/create work post-deploy"
type: chore
date: 2026-04-07
---

# Verify /api/repo/install and /api/repo/create Work Post-Deploy

## Overview

PR #1680 fixed a critical production issue where Docker's DNS resolver could not follow the CNAME chain for the custom Supabase domain (`api.soleur.ai`). The fix introduced a `SUPABASE_URL` env var pointing directly to `ifsccnjhymdmidffkzhl.supabase.co`, bypassing the DNS issue for server-side service client calls.

This verification task confirms that the deployed fix (web-v0.14.9) resolves the two specific failures:

1. `/api/repo/install` returning 403 because `auth.admin.getUserById()` failed to resolve GitHub identities
2. `/api/repo/create` returning 400 because `serviceClient.from("users").select()` failed to read the users table

**Current state:** The `/health` endpoint still returns `supabase: "error"` as of 2026-04-07, which is a concerning signal that the `SUPABASE_URL` env var may not be reaching the running container, or the container may need a restart/redeploy.

## Source Context

- **Source PR:** #1680 (merged 2026-04-06 19:32 UTC)
- **Source issue:** #1679
- **Follow-through issue:** #1686
- **Learning docs:**
  - `knowledge-base/project/learnings/runtime-errors/docker-dns-supabase-custom-domain-20260406.md`
  - `knowledge-base/project/learnings/integration-issues/2026-04-06-supabase-server-side-connectivity-docker-container.md`

## Verification Strategy

Verification proceeds in layers, from cheapest to most expensive:

### Phase 1: Health Endpoint Check

Verify the health endpoint reports `supabase: "connected"` instead of `supabase: "error"`.

```bash
curl -s https://app.soleur.ai/health | jq '.supabase'
```

- **Expected:** `"connected"`
- **If "error":** The `SUPABASE_URL` env var is not reaching the container. Check:
  1. `doppler secrets get SUPABASE_URL -p soleur -c prd --plain` -- confirm it exists
  2. SSH (read-only) to check container env: `docker exec <container> printenv SUPABASE_URL`
  3. If missing, the container needs a redeploy to pick up the new Doppler secret

### Phase 2: API Endpoint Verification via Authenticated Browser Session

Both `/api/repo/install` and `/api/repo/create` require an authenticated session (Supabase auth cookie). Verification requires:

1. **Authenticate via Playwright MCP:**
   - Navigate to `https://app.soleur.ai/login`
   - Use OTP magic link via Supabase `generate_link` API (use `action_link`, not `email_otp`)
   - Navigate to the action link to complete auth

2. **Test `/api/repo/install`** (verifies `auth.admin.getUserById` works):
   - From the authenticated browser session, call the install endpoint with a test installation ID
   - The endpoint should reach the `verifyInstallationOwnership` step (not return 403 at the identity resolution step)
   - Expected: 200 with `{"ok": true}` (if the installation ID is valid and owned) or 403 with an ownership verification error (not "No GitHub identity linked")

3. **Test `/api/repo/create`** (verifies `serviceClient.from("users").select()` works):
   - From the authenticated browser session, call the create endpoint with a test repo name
   - The endpoint should successfully read `github_installation_id` from the users table
   - Expected: 200 with repo creation result, or 400 with "GitHub App not installed" (if user has no installation ID -- but importantly NOT a generic Supabase connectivity error)

### Phase 3: E2E Flow Verification (Conditional)

Only if Phase 2 passes, optionally run the full "Start Fresh" flow:

1. Navigate to `/connect-repo`
2. If GitHub App is already installed, verify the page shows "Start Fresh" option
3. Click "Start Fresh", enter a test repo name
4. Verify repo creation succeeds
5. Clean up: delete the test repo via GitHub API

## Acceptance Criteria

- [ ] `/health` returns `supabase: "connected"` (not `"error"`)
- [ ] `/api/repo/install` does NOT return 403 with "No GitHub identity linked" for a user with GitHub identity
- [ ] `/api/repo/create` does NOT return 400 with Supabase connectivity error for a user with `github_installation_id` set
- [ ] If health check fails, root cause is identified (missing env var, stale container, etc.)
- [ ] Results documented and issue #1686 closed with verification evidence

## Test Scenarios

- Given the production container has `SUPABASE_URL` set to the direct Supabase project URL, when `/health` is called, then it should return `supabase: "connected"`
- Given an authenticated user with a GitHub identity, when `/api/repo/install` is called with a valid installation ID, then it should NOT fail at the identity resolution step (no 403 "No GitHub identity linked")
- Given an authenticated user with `github_installation_id` set, when `/api/repo/create` is called, then it should successfully read the users table (no 400 from Supabase query failure)
- Given the health endpoint returns `supabase: "error"`, when investigating, then check if the container was redeployed after the Doppler secret was added

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure verification task.

## Key Files

| File | Role |
|------|------|
| `apps/web-platform/lib/supabase/service.ts` | `serverUrl()` helper and `createServiceClient()` |
| `apps/web-platform/lib/supabase/server.ts` | Re-exports service client, provides cookie-based client |
| `apps/web-platform/app/api/repo/install/route.ts` | Install endpoint using `auth.admin.getUserById()` |
| `apps/web-platform/app/api/repo/create/route.ts` | Create endpoint using `serviceClient.from("users")` |
| `apps/web-platform/server/health.ts` | Health check using `serverUrl()` |
| `apps/web-platform/test/install-route-handler.test.ts` | Unit tests for install route |
| `apps/web-platform/test/create-route-error.test.ts` | Unit tests for create route |

## References

- PR #1680: fix: use direct Supabase URL for server-side service client
- Issue #1679: Server-side Supabase connectivity investigation
- Issue #1686: Follow-through verification issue
- PR #1673: E2E verify Start Fresh flow for org installation
