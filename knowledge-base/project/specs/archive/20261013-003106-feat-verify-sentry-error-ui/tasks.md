# Tasks: Verify Sentry Capture and Error UI for Project Setup Failures

Source: [Plan](../../plans/2026-04-05-chore-verify-sentry-error-ui-setup-failures-plan.md)
Issue: #1498

## Phase 1: Trigger Setup Failure and Verify UI

- [ ] 1.1 Authenticate to `https://app.soleur.ai` via Playwright MCP
- [ ] 1.2 Navigate to `/connect-repo` page
- [ ] 1.3 Select or input a repository URL the GitHub App cannot access
- [ ] 1.4 Wait for the failure state to appear (poll status or observe UI)
- [ ] 1.5 Screenshot the failure page showing the error details card
- [ ] 1.6 Confirm "Error details" card is visible with specific error message

## Phase 2: Verify Sentry Event

- [ ] 2.1 Wait 2-3 minutes for Sentry ingestion
- [ ] 2.2 Query Sentry API for recent issues in `soleur-web-platform`
- [ ] 2.3 Confirm event exists with descriptive error message (not generic)

## Phase 3: Verify Database Persistence

- [ ] 3.1 Query Supabase REST API for the test user's `repo_error` column
- [ ] 3.2 Confirm `repo_error` is not null and contains specific error text
- [ ] 3.3 Confirm `repo_status` is `"error"`

## Phase 4: Cleanup and Close

- [ ] 4.1 Reset test user's `repo_status` and `repo_error` to null
- [ ] 4.2 Close Playwright browser
- [ ] 4.3 Close issue #1498 with verification results
