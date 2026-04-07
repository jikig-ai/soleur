---
title: "chore: verify /api/repo/install and /api/repo/create work post-deploy"
type: chore
date: 2026-04-07
---

# Verify /api/repo/install and /api/repo/create Work Post-Deploy

## Enhancement Summary

**Deepened on:** 2026-04-07
**Sections enhanced:** 4 (Verification Strategy, Acceptance Criteria, Test Scenarios, Key Files)
**Research sources:** 5 institutional learnings, deploy pipeline analysis, production health probe

### Key Improvements

1. Added concrete diagnostic commands for the health endpoint failure (SSH `printenv`, Sentry API query, Doppler verification)
2. Identified that the deploy health verification workflow does NOT check `supabase` field -- only `status` and `version` -- meaning deploys can succeed with broken Supabase connectivity
3. Added a Phase 0 (pre-check) that can be run entirely without authentication to narrow down the failure before launching Playwright
4. Added cleanup and rollback procedures for Phase 3 E2E testing

### New Considerations Discovered

- The `web-platform-release.yml` deploy verification (lines 98-121) only checks `status == "ok"` and version match. It does not verify `supabase == "connected"`. A deploy can pass health verification while Supabase connectivity is broken.
- Learning from `2026-04-06-doppler-stderr-contaminates-docker-env-file.md`: Recent deploy pipeline fixes separated stderr from stdout in `resolve_env_file()`. If those fixes were applied AFTER the v0.14.9 deploy, the `SUPABASE_URL` env var may be present in Doppler but absent from the container's env file.
- Learning from `stale-env-deploy-pipeline-terraform-bridge-20260405.md`: The deploy pipeline previously had a fallback to a stale `.env` file. While this was fixed, similar patterns could re-emerge if the Doppler download fails silently.
- Consider filing a follow-up issue to add `supabase == "connected"` to the deploy health verification check in `web-platform-release.yml`.

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

Verification proceeds in layers, from cheapest to most expensive. Each phase gates the next -- stop and fix before proceeding if a phase fails.

### Phase 0: Pre-Check (No Auth Required)

Before launching Playwright or authenticating, verify the infrastructure preconditions are met.

**Step 0.1: Confirm `SUPABASE_URL` exists in Doppler prd config:**

```bash
doppler secrets get SUPABASE_URL -p soleur -c prd --plain
```

Expected: `https://ifsccnjhymdmidffkzhl.supabase.co`

**Step 0.2: Verify direct Supabase connectivity from the agent machine:**

```bash
curl -sf "https://ifsccnjhymdmidffkzhl.supabase.co/rest/v1/" \
  -H "apikey: $(doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c prd --plain)" \
  -o /dev/null -w '%{http_code}'
```

Expected: `200`. If this fails, Supabase itself is down -- not a container-specific issue.

**Step 0.3: Verify the service role key can call admin API:**

```bash
SUPABASE_URL=$(doppler secrets get SUPABASE_URL -p soleur -c prd --plain)
SERVICE_KEY=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd --plain)
curl -sf "$SUPABASE_URL/auth/v1/admin/users?per_page=1" \
  -H "Authorization: Bearer $SERVICE_KEY" \
  -H "apikey: $SERVICE_KEY" | jq '.users | length'
```

Expected: `1` (at least one user). This confirms the service role key + direct URL combination works.

### Phase 1: Health Endpoint Check

Verify the health endpoint reports `supabase: "connected"` instead of `supabase: "error"`.

```bash
curl -s https://app.soleur.ai/health | jq '.'
```

- **Expected:** `supabase: "connected"`, `version: "0.14.9"` or later
- **If `supabase: "error"`:** The `SUPABASE_URL` env var is not reaching the container. Diagnose with:

  1. **Check Sentry for server-side errors** (per AGENTS.md observability priority chain):

     ```bash
     SENTRY_TOKEN=$(doppler secrets get SENTRY_API_TOKEN -p soleur -c prd --plain)
     curl -s "https://sentry.io/api/0/projects/jikig-ai/soleur-web-platform/issues/?query=supabase+error&statsPeriod=24h" \
       -H "Authorization: Bearer $SENTRY_TOKEN" | jq '.[0:3] | .[] | {title, count, lastSeen}'
     ```

  2. **Read-only SSH diagnosis** (only if Sentry is insufficient):

     ```bash
     ssh deploy@<server-ip> "docker exec \$(docker ps -q --filter name=web-platform) printenv SUPABASE_URL"
     ```

     If empty: the container was deployed before `SUPABASE_URL` was added to Doppler. Fix: trigger a redeploy via `gh workflow run web-platform-release.yml`.

  3. **If env var IS present but health still fails:** Check if the container can resolve the direct Supabase URL:

     ```bash
     ssh deploy@<server-ip> "docker exec \$(docker ps -q --filter name=web-platform) wget -q -O /dev/null --timeout=5 https://ifsccnjhymdmidffkzhl.supabase.co/rest/v1/ 2>&1"
     ```

### Research Insights (Phase 1)

**Deploy pipeline gap (from `web-platform-release.yml` lines 98-121):** The deploy verification only checks `status == "ok"` and version match. It does NOT check `supabase == "connected"`. This means the v0.14.9 deploy could have passed verification while Supabase was still broken. Consider filing a follow-up issue to add Supabase connectivity to the deploy health gate.

**Stale env file pattern (from learning `stale-env-deploy-pipeline-terraform-bridge-20260405.md`):** The deploy pipeline previously fell back to a stale `.env` file when Doppler download failed. While fixed in PR #1575, if the fix wasn't applied to the server's `ci-deploy.sh` via Terraform before the v0.14.9 deploy, the old script might have been used, potentially missing `SUPABASE_URL`.

**Doppler stderr contamination (from learning `2026-04-06-doppler-stderr-contaminates-docker-env-file.md`):** If the `ci-deploy.sh` stderr fix was not deployed before v0.14.9, a Doppler warning could have contaminated the env file, causing Docker to reject it and potentially falling back to no env file at all.

### Phase 2: API Endpoint Verification via Authenticated Browser Session

Both `/api/repo/install` and `/api/repo/create` require an authenticated session (Supabase auth cookie). Verification requires:

1. **Authenticate via Playwright MCP:**
   - Navigate to `https://app.soleur.ai/login`
   - Use Supabase admin API `generate_link` to get a magic link (use `action_link` from the response, NOT `email_otp` which returns null -- see learning `2026-04-06-supabase-server-side-connectivity-docker-container.md`)
   - The founder's auth email is `jean.deruelle@jikigai.com` (NOT `jean@jikigai.com` -- see same learning)
   - Navigate to the `action_link` URL to complete authentication
   - Verify redirect to `/dashboard` or `/connect-repo`

2. **Test `/api/repo/install`** (verifies `auth.admin.getUserById` works):
   - From the authenticated browser session, use `browser_evaluate` to call the install endpoint:

     ```javascript
     fetch('/api/repo/install', {
       method: 'POST',
       headers: { 'Content-Type': 'application/json' },
       body: JSON.stringify({ installationId: 121881501 })
     }).then(r => r.json().then(b => ({ status: r.status, body: b })))
     ```

   - **Success indicators (any of these means the service client works):**
     - 200 with `{"ok": true}` -- full success
     - 403 with ownership verification error containing "not associated" -- identity resolved, ownership check failed (acceptable, means service client works)
   - **Failure indicator (means service client is broken):**
     - 403 with "No GitHub identity linked" -- `auth.admin.getUserById` failed
     - 500 with "Failed to resolve GitHub identity" -- service client threw an exception

3. **Test `/api/repo/create`** (verifies `serviceClient.from("users").select()` works):
   - From the authenticated browser session, use `browser_evaluate` to call the create endpoint:

     ```javascript
     fetch('/api/repo/create', {
       method: 'POST',
       headers: { 'Content-Type': 'application/json' },
       body: JSON.stringify({ name: 'soleur-verify-test-20260407', private: true })
     }).then(r => r.json().then(b => ({ status: r.status, body: b })))
     ```

   - **Success indicators:**
     - 200 with repo creation result -- full success (will need cleanup in Phase 3)
     - 400 with "GitHub App not installed" -- service client successfully read the users table, user just doesn't have `github_installation_id` set
   - **Failure indicator:**
     - 400 with a Supabase error or timeout -- service client cannot reach Supabase

### Phase 3: E2E Flow Verification (Conditional)

Only if Phase 2 passes and `/api/repo/create` returned 200, run the full "Start Fresh" flow:

1. Navigate to `/connect-repo` in the authenticated session
2. If GitHub App is already installed, verify the page shows "Start Fresh" option
3. Click "Start Fresh", enter a test repo name (e.g., `soleur-e2e-verify-20260407`)
4. Verify repo creation succeeds
5. **Clean up:** Delete the test repo via GitHub API using the installation token (NOT `gh repo delete` which lacks `delete_repo` scope -- see learning `2026-04-06-supabase-server-side-connectivity-docker-container.md`):

   ```bash
   # Generate installation token via GitHub App JWT
   INST_TOKEN=$(curl -s -X POST \
     "https://api.github.com/app/installations/121881501/access_tokens" \
     -H "Authorization: Bearer $JWT" | jq -r .token)

   # Delete test repo
   curl -s -X DELETE "https://api.github.com/repos/jikig-ai/soleur-e2e-verify-20260407" \
     -H "Authorization: token $INST_TOKEN"
   ```

6. **Close browser:** Call `browser_close` after all Playwright work is done (per AGENTS.md rule)

## Acceptance Criteria

- [ ] `SUPABASE_URL` confirmed in Doppler prd config pointing to `https://ifsccnjhymdmidffkzhl.supabase.co`
- [ ] Direct Supabase REST API reachable with anon key (pre-check baseline)
- [ ] Service role key can call `auth.admin.getUserById` via direct URL (pre-check baseline)
- [ ] `/health` returns `supabase: "connected"` (not `"error"`)
- [ ] `/api/repo/install` does NOT return 403 with "No GitHub identity linked" for a user with GitHub identity
- [ ] `/api/repo/create` does NOT return 400 with Supabase connectivity error for a user with `github_installation_id` set
- [ ] If health check fails, root cause is identified and fixed (missing env var, stale container, redeploy needed)
- [ ] If a redeploy is needed, trigger it and re-verify all criteria
- [ ] Results documented and issue #1686 closed with verification evidence
- [ ] Test repo cleaned up if created during verification (use installation token, not `gh` CLI)
- [ ] Browser closed after Playwright verification (`browser_close`)

## Test Scenarios

### Infrastructure Pre-Checks

- **API verify:** `doppler secrets get SUPABASE_URL -p soleur -c prd --plain` expects `https://ifsccnjhymdmidffkzhl.supabase.co`
- **API verify:** `curl -sf "https://ifsccnjhymdmidffkzhl.supabase.co/rest/v1/" -H "apikey: $(doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c prd --plain)" -o /dev/null -w '%{http_code}'` expects `200`

### Health Endpoint

- Given the production container has `SUPABASE_URL` set to the direct Supabase project URL, when `/health` is called, then it should return `supabase: "connected"`
- **API verify:** `curl -s https://app.soleur.ai/health | jq '.supabase'` expects `"connected"`

### Install Endpoint

- Given an authenticated user with a GitHub identity, when `/api/repo/install` is called with installation ID `121881501`, then it should NOT return 403 with "No GitHub identity linked" (403 with ownership verification error is acceptable)
- **Browser:** Navigate to `https://app.soleur.ai/login`, authenticate via OTP magic link, call `fetch('/api/repo/install', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({installationId: 121881501}) })`, verify response status is not 403 with identity error or 500

### Create Endpoint

- Given an authenticated user, when `/api/repo/create` is called with name `soleur-verify-test-20260407`, then the service client should successfully read the users table (400 "GitHub App not installed" is acceptable -- means the query worked)
- **Browser:** From authenticated session, call `fetch('/api/repo/create', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({name: 'soleur-verify-test-20260407', private: true}) })`, verify response is not a Supabase connectivity error

### Failure Recovery

- Given the health endpoint returns `supabase: "error"`, when investigating, then check container env via SSH (`docker exec <container> printenv SUPABASE_URL`) and trigger redeploy if missing
- Given a redeploy is triggered, when health is re-checked after 5 minutes, then `supabase` should be `"connected"`

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure verification task.

## Key Files

| File | Role |
|------|------|
| `apps/web-platform/lib/supabase/service.ts` | `serverUrl()` helper and `createServiceClient()` -- the fix target |
| `apps/web-platform/lib/supabase/server.ts` | Re-exports service client, provides cookie-based client |
| `apps/web-platform/app/api/repo/install/route.ts` | Install endpoint using `auth.admin.getUserById()` (line 53) |
| `apps/web-platform/app/api/repo/create/route.ts` | Create endpoint using `serviceClient.from("users")` (line 48) |
| `apps/web-platform/server/health.ts` | Health check using `serverUrl()` (line 5) |
| `apps/web-platform/test/install-route-handler.test.ts` | Unit tests for install route identity resolution |
| `apps/web-platform/test/create-route-error.test.ts` | Unit tests for create route error handling |
| `apps/web-platform/infra/ci-deploy.sh` | Deploy script -- `resolve_env_file()` downloads Doppler secrets |
| `.github/workflows/web-platform-release.yml` | Release workflow -- deploy verification (lines 98-121) |

## Potential Follow-Up Issues

If verification succeeds, consider filing:

1. **Deploy health gate enhancement:** Add `supabase == "connected"` check to `web-platform-release.yml` deploy verification (currently only checks `status` and `version`)
2. **Automated Supabase connectivity E2E:** Add a smoke test in `apps/web-platform/e2e/smoke.e2e.ts` that verifies `/health` returns `supabase: "connected"` against the deployed environment

## References

- PR #1680: fix: use direct Supabase URL for server-side service client
- Issue #1679: Server-side Supabase connectivity investigation
- Issue #1686: Follow-through verification issue
- PR #1673: E2E verify Start Fresh flow for org installation
- Learning: `knowledge-base/project/learnings/runtime-errors/docker-dns-supabase-custom-domain-20260406.md`
- Learning: `knowledge-base/project/learnings/integration-issues/2026-04-06-supabase-server-side-connectivity-docker-container.md`
- Learning: `knowledge-base/project/learnings/integration-issues/2026-04-06-doppler-stderr-contaminates-docker-env-file.md`
- Learning: `knowledge-base/project/learnings/integration-issues/stale-env-deploy-pipeline-terraform-bridge-20260405.md`
- Learning: `knowledge-base/project/learnings/integration-issues/supabase-identities-null-email-first-users-20260403.md`
