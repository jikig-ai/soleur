---
title: "chore: production verification of GitHub project setup flow"
branch: feat-one-shot-1489-gh-project-setup-verification
issue: "#1489"
date: 2026-04-06
---

# Tasks: Production Verification of GitHub Project Setup Flow

## Phase 1: Observability Check

- [ ] 1.1 Retrieve `SENTRY_API_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` from Doppler `prd` config
- [ ] 1.2 Query Sentry API (EU region: `de.sentry.io`) for unresolved issues matching `getUserById OR PGRST106 OR identity` with `statsPeriod=14d`
- [ ] 1.3 Verify zero matching Sentry errors (note: zero may mean SDK is broken per #1533, not that no errors occurred)
- [ ] 1.4 Check production health endpoint: `curl -s https://app.soleur.ai/health | jq '.'` -- verify `status` and `version` fields
- [ ] 1.5 Query Supabase REST API for users with `github_installation_id IS NOT NULL` -- confirm at least 1 user completed flow
- [ ] 1.6 Query Supabase for users with `repo_status = 'error'` -- check for residual failures with `PGRST106` or identity errors in `repo_error`

## Phase 2: Browser Verification (Playwright MCP)

- [ ] 2.1 Authenticate via OTP flow (use `generate_link` admin API, NOT magic links)
- [ ] 2.2 Navigate to `https://app.soleur.ai/connect-repo`
- [ ] 2.3 Take screenshot of initial "choose" state
- [ ] 2.4 Click "Connect Existing Repository" to start GitHub App install flow
- [ ] 2.5 Handle redirect: if app already installed for jikig-ai org (ID 121112974), expect immediate callback with `installation_id`
- [ ] 2.6 Verify page transitions to repo selection (not "interrupted" or "failed")
- [ ] 2.7 Take screenshot of repo selection state
- [ ] 2.8 Select a repository and observe setup status transitions
- [ ] 2.9 Take screenshot of final state
- [ ] 2.10 Call `browser_close` to clean up

## Phase 3: Close Issue

- [ ] 3.1 Compile verification evidence (Sentry query results, Supabase query results, Playwright screenshots)
- [ ] 3.2 Post summary comment on #1489 with all evidence
- [ ] 3.3 If all pass: close #1489
- [ ] 3.4 If any fail: create follow-up fix issue with specific failure details, leave #1489 open
