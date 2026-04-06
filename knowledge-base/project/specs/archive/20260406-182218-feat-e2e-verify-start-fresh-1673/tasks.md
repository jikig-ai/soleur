# Tasks: E2E Verify Start Fresh Flow for Org Installation

## Phase 1: Pre-flight Checks

- [ ] 1.1 Verify #1672 is closed: `gh issue view 1672 --json state`
- [ ] 1.2 Verify GitHub App `administration:write` permission via API
- [ ] 1.3 Verify Sentry configured in container: `curl -s https://app.soleur.ai/health | jq '.sentry'` (expect `"configured"`)
- [ ] 1.4 Record Sentry error baseline (use `statsPeriod=24h`, NOT `1h`; use `de.sentry.io` EU region)

## Phase 1.5: Playwright Authentication

- [ ] 1.5.1 Navigate to `https://app.soleur.ai/login`
- [ ] 1.5.2 Enter user email and click "Send sign-in code" in UI FIRST
- [ ] 1.5.3 Call `generate_link` admin API to retrieve OTP code (after UI send, not before -- rate limiter)
- [ ] 1.5.4 Enter OTP code in browser and submit
- [ ] 1.5.5 Verify authenticated state (redirect to dashboard)

## Phase 2: Playwright E2E Flow

- [ ] 2.1 Navigate to `https://app.soleur.ai/connect-repo`
- [ ] 2.2 Verify "Start Fresh" card is visible in the choose state
- [ ] 2.3 Click "Start Fresh" to enter create_project state
- [ ] 2.4 Enter project name `soleur-e2e-test-20260406` and submit
- [ ] 2.5 Verify transition to github_redirect state
- [ ] 2.6 Click "Continue to GitHub" to redirect to GitHub App install page
- [ ] 2.7 **USER HANDOFF:** User completes OAuth consent for jikig-ai org
- [ ] 2.8 After redirect, verify setting_up state with progress steps
- [ ] 2.9 Wait for all 5 setup steps to complete (or read error from FailedState if it fails)
- [ ] 2.10 Verify ready state with repo name displayed
- [ ] 2.11 Take screenshot of final ready state

## Phase 3: Post-verification

- [ ] 3.1 Verify repo exists on GitHub: `gh repo view jikig-ai/soleur-e2e-test-20260406`
- [ ] 3.2 Query Sentry for new unresolved errors (use `de.sentry.io` + `jq` type guard, expect 0)
- [ ] 3.3 Delete test repo: `gh repo delete jikig-ai/soleur-e2e-test-20260406 --yes`
- [ ] 3.4 Close issue #1673 with verification evidence comment
