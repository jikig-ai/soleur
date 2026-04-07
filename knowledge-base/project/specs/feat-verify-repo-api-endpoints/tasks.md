# Tasks: Verify /api/repo/install and /api/repo/create Post-Deploy

Source plan: `knowledge-base/project/plans/2026-04-07-chore-verify-repo-api-endpoints-post-deploy-plan.md`

## Phase 0: Infrastructure Pre-Checks (No Auth Required)

- [x] 0.1 Verify `SUPABASE_URL` in Doppler prd: `doppler secrets get SUPABASE_URL -p soleur -c prd --plain`
- [x] 0.2 Verify direct Supabase REST API reachable: `curl -sf "$SUPABASE_URL/rest/v1/" -H "apikey: $ANON_KEY" -o /dev/null -w '%{http_code}'`
- [x] 0.3 Verify service role key works via direct URL: `curl -sf "$SUPABASE_URL/auth/v1/admin/users?per_page=1" -H "Authorization: Bearer $SERVICE_KEY" -H "apikey: $SERVICE_KEY" | jq '.users | length'`

## Phase 1: Health Endpoint Check

- [x] 1.1 Curl `https://app.soleur.ai/health` and check full response (`status`, `version`, `supabase`)
- [x] 1.2 If `supabase: "error"`, investigate root cause:
  - [x] 1.2.1 Check Sentry for server-side Supabase errors (24h window) — zero errors
  - [x] 1.2.2 Read-only SSH: `docker exec <container> printenv SUPABASE_URL` — correctly set
  - [x] 1.2.3 Root cause: health check uses anon key on `/rest/v1/` root (401), not a connectivity issue
  - [x] 1.2.4 Fix: updated health.ts to use service role key with Authorization header
- [x] 1.3 Document health check result

## Phase 2: Authenticated API Verification

- [x] 2.1 Authenticate via Playwright MCP:
  - [x] 2.1.1 Navigate to `https://app.soleur.ai/login`
  - [x] 2.1.2 Generate OTP magic link via Supabase admin API `generate_link` (email: `jean.deruelle@jikigai.com`)
  - [x] 2.1.3 Navigate to `action_link` to complete authentication (note: `action_link` is top-level, not under `properties`)
  - [x] 2.1.4 Verified authenticated state — manually set cookie, reached `/dashboard`

- [x] 2.2 Verify `/api/repo/install` identity resolution:
  - [x] 2.2.1 Called `fetch('/api/repo/install', ...)` with `installationId: 121881501`
  - [x] 2.2.2 Response: **200 `{"ok": true}`** — identity resolved, ownership verified
  - [x] 2.2.3 Documented: `auth.admin.getUserById` works via direct Supabase URL

- [x] 2.3 Verify `/api/repo/create` users table read:
  - [x] 2.3.1 Called `fetch('/api/repo/create', ...)` with `name: 'soleur-verify-test-20260407'`
  - [x] 2.3.2 Response: **200 `{"repoUrl":"...","fullName":"jikig-ai/soleur-verify-test-20260407"}`**
  - [x] 2.3.3 Documented: service client reads users table and creates repo successfully

## Phase 3: E2E Flow Verification (Conditional -- only if Phase 2 passes)

- [x] 3.1-3.3 Skipped browser E2E — API verification in Phase 2 already exercised the full create flow
- [x] 3.4 Cleaned up: deleted test repo `jikig-ai/soleur-verify-test-20260407` via GitHub App installation token (HTTP 204)
- [x] 3.5 Called `browser_close` to release Playwright resources

## Phase 4: Close Out

- [x] 4.1 Documented verification results as comment on issue #1686
- [x] 4.2 Close issue #1686 with evidence summary
- [x] 4.3 Health check bug fixed in this branch (not a connectivity problem — anon key on root endpoint)
- [x] 4.4 Filed follow-up issue #1703: add `supabase == "connected"` check to deploy health verification
