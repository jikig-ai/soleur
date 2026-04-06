# Tasks: E2E Verify Start Fresh Flow for Org Installation

## Phase 1: Pre-flight Checks

- [ ] 1.1 Verify #1672 is closed: `gh issue view 1672 --json state`
- [ ] 1.2 Verify GitHub App `administration:write` permission via API
- [ ] 1.3 Record Sentry error baseline (unresolved count in last 1h)

## Phase 2: Playwright E2E Flow

- [ ] 2.1 Navigate to `https://app.soleur.ai/connect-repo`
- [ ] 2.2 Verify "Start Fresh" card is visible in the choose state
- [ ] 2.3 Click "Start Fresh" to enter create_project state
- [ ] 2.4 Enter project name `soleur-e2e-test-20260406` and submit
- [ ] 2.5 Verify transition to github_redirect state
- [ ] 2.6 Click "Continue to GitHub" to redirect to GitHub App install page
- [ ] 2.7 **USER HANDOFF:** User completes OAuth consent for jikig-ai org
- [ ] 2.8 After redirect, verify setting_up state with progress steps
- [ ] 2.9 Wait for all 5 setup steps to complete
- [ ] 2.10 Verify ready state with repo name displayed
- [ ] 2.11 Take screenshot of final ready state

## Phase 3: Post-verification

- [ ] 3.1 Verify repo exists on GitHub: `gh repo view jikig-ai/soleur-e2e-test-20260406`
- [ ] 3.2 Query Sentry for new unresolved errors in last 15 minutes (expect 0)
- [ ] 3.3 Delete test repo: `gh repo delete jikig-ai/soleur-e2e-test-20260406 --yes`
- [ ] 3.4 Close issue #1673 with verification evidence comment
