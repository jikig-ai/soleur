# Tasks: Verify /api/repo/install and /api/repo/create Post-Deploy

Source plan: `knowledge-base/project/plans/2026-04-07-chore-verify-repo-api-endpoints-post-deploy-plan.md`

## Phase 0: Infrastructure Pre-Checks (No Auth Required)

- [ ] 0.1 Verify `SUPABASE_URL` in Doppler prd: `doppler secrets get SUPABASE_URL -p soleur -c prd --plain`
- [ ] 0.2 Verify direct Supabase REST API reachable: `curl -sf "$SUPABASE_URL/rest/v1/" -H "apikey: $ANON_KEY" -o /dev/null -w '%{http_code}'`
- [ ] 0.3 Verify service role key works via direct URL: `curl -sf "$SUPABASE_URL/auth/v1/admin/users?per_page=1" -H "Authorization: Bearer $SERVICE_KEY" -H "apikey: $SERVICE_KEY" | jq '.users | length'`

## Phase 1: Health Endpoint Check

- [ ] 1.1 Curl `https://app.soleur.ai/health` and check full response (`status`, `version`, `supabase`)
- [ ] 1.2 If `supabase: "error"`, investigate root cause:
  - [ ] 1.2.1 Check Sentry for server-side Supabase errors (24h window)
  - [ ] 1.2.2 Read-only SSH: `docker exec <container> printenv SUPABASE_URL`
  - [ ] 1.2.3 If env var missing, trigger redeploy: `gh workflow run web-platform-release.yml`
  - [ ] 1.2.4 Wait 5 minutes, re-check health
- [ ] 1.3 Document health check result

## Phase 2: Authenticated API Verification

- [ ] 2.1 Authenticate via Playwright MCP:
  - [ ] 2.1.1 Navigate to `https://app.soleur.ai/login`
  - [ ] 2.1.2 Generate OTP magic link via Supabase admin API `generate_link` (email: `jean.deruelle@jikigai.com`)
  - [ ] 2.1.3 Navigate to `action_link` (NOT `email_otp`) to complete authentication
  - [ ] 2.1.4 Verify authenticated state (redirected to dashboard or connect-repo)

- [ ] 2.2 Verify `/api/repo/install` identity resolution:
  - [ ] 2.2.1 Call `fetch('/api/repo/install', ...)` with `installationId: 121881501` via `browser_evaluate`
  - [ ] 2.2.2 Verify response is NOT 403 "No GitHub identity linked" and NOT 500 "Failed to resolve"
  - [ ] 2.2.3 Document actual response code and body

- [ ] 2.3 Verify `/api/repo/create` users table read:
  - [ ] 2.3.1 Call `fetch('/api/repo/create', ...)` with `name: 'soleur-verify-test-20260407'` via `browser_evaluate`
  - [ ] 2.3.2 Verify response is NOT a Supabase connectivity error (400 "GitHub App not installed" is acceptable)
  - [ ] 2.3.3 Document actual response code and body

## Phase 3: E2E Flow Verification (Conditional -- only if Phase 2 passes)

- [ ] 3.1 Navigate to `/connect-repo` in authenticated session
- [ ] 3.2 Verify "Start Fresh" option is available
- [ ] 3.3 Create test repo via "Start Fresh" flow (name: `soleur-e2e-verify-20260407`)
- [ ] 3.4 Clean up: delete test repo via GitHub App installation token (NOT `gh repo delete`)
- [ ] 3.5 Call `browser_close` to release Playwright resources

## Phase 4: Close Out

- [ ] 4.1 Document all verification results as a comment on issue #1686
- [ ] 4.2 Close issue #1686 with evidence summary
- [ ] 4.3 If health check still fails after redeploy, file a new issue for the remaining connectivity problem
- [ ] 4.4 Consider filing follow-up issue: add `supabase == "connected"` check to deploy health verification in `web-platform-release.yml`
