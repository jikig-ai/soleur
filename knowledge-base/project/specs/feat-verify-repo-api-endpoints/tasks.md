# Tasks: Verify /api/repo/install and /api/repo/create Post-Deploy

Source plan: `knowledge-base/project/plans/2026-04-07-chore-verify-repo-api-endpoints-post-deploy-plan.md`

## Phase 1: Health Endpoint Check

- [ ] 1.1 Curl `https://app.soleur.ai/health` and check `supabase` field
- [ ] 1.2 If `supabase: "error"`, investigate root cause:
  - [ ] 1.2.1 Verify `SUPABASE_URL` exists in Doppler prd config
  - [ ] 1.2.2 Check if container has the env var (read-only SSH: `docker exec <container> printenv SUPABASE_URL`)
  - [ ] 1.2.3 If missing, trigger redeploy and re-check health
- [ ] 1.3 Document health check result

## Phase 2: Authenticated API Verification

- [ ] 2.1 Authenticate via Playwright MCP:
  - [ ] 2.1.1 Navigate to `https://app.soleur.ai/login`
  - [ ] 2.1.2 Generate OTP magic link via Supabase admin API `generate_link`
  - [ ] 2.1.3 Navigate to `action_link` to complete authentication
  - [ ] 2.1.4 Verify authenticated state (redirected to dashboard or connect-repo)

- [ ] 2.2 Verify `/api/repo/install` identity resolution:
  - [ ] 2.2.1 Call `/api/repo/install` with a test `installationId` from the authenticated session
  - [ ] 2.2.2 Verify response is NOT 403 "No GitHub identity linked"
  - [ ] 2.2.3 Document actual response code and body

- [ ] 2.3 Verify `/api/repo/create` users table read:
  - [ ] 2.3.1 Call `/api/repo/create` with a test repo name from the authenticated session
  - [ ] 2.3.2 Verify response is NOT 400 due to Supabase connectivity error
  - [ ] 2.3.3 Document actual response code and body

## Phase 3: E2E Flow Verification (Conditional)

- [ ] 3.1 Only proceed if Phase 2 passes
- [ ] 3.2 Navigate to `/connect-repo` in authenticated session
- [ ] 3.3 Verify "Start Fresh" option is available
- [ ] 3.4 Create test repo via "Start Fresh" flow
- [ ] 3.5 Clean up: delete test repo via GitHub API

## Phase 4: Close Out

- [ ] 4.1 Document all verification results in issue #1686
- [ ] 4.2 Close issue #1686 with evidence
- [ ] 4.3 If health check still fails, file a new issue for the remaining connectivity problem
