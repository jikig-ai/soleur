---
title: "chore: verify Sentry capture and error UI for project setup failures"
type: fix
date: 2026-04-05
source_issue: "#1498"
source_pr: "#1494"
---

# Verify Sentry Capture and Error UI for Project Setup Failures

Follow-through verification for PR #1494, which added error handling to project
setup: Sentry capture, `repo_error` database column, and error details in the
failure page UI.

## Context

PR #1494 fixed a blind spot where `provisionWorkspaceWithRepo` failures produced
a generic "Project Setup Failed" page with no details, no Sentry events, and no
persisted error message. The fix added:

1. Step-specific error wrapping in `server/workspace.ts` (token generation,
   credential helper, git clone with stderr capture)
2. `Sentry.captureException(err)` in the `.catch()` handler of
   `app/api/repo/setup/route.ts`
3. `repo_error` column via migration `013_repo_error.sql`
4. `errorMessage` field in `GET /api/repo/status` response
5. Error details card in `FailedState` component

This plan verifies all five pieces work end-to-end in production.

## Pre-Verification Checks (Already Confirmed)

- [x] Migration `013_repo_error.sql` applied -- `repo_error` column exists in
  production `users` table (verified via Supabase REST API)
- [x] Sentry project `soleur-web-platform` in org `jikigai` is configured
  (DSN present in Doppler `prd` config)
- [x] Sentry API token available in Doppler `prd` config

## Acceptance Criteria

- [ ] **AC1: Sentry event captured** -- After triggering a setup failure, the
  Sentry API returns at least one issue/event within 5 minutes containing the
  error message from the failed setup attempt
- [ ] **AC2: Error message displayed in UI** -- The failure page shows an "Error
  details" card with a specific error message (not just "Something went wrong"
  or "Project Setup Failed" with no details)
- [ ] **AC3: Database error persisted** -- The `repo_error` column in the
  `users` table contains the error message from the failed attempt
- [ ] **AC4: Error cleared on retry** -- After clicking "Try Again" and starting
  a new setup attempt, `repo_error` is set to `null` (verified via code review:
  line 66 of `setup/route.ts` sets `repo_error: null` in the optimistic lock
  UPDATE -- no runtime test needed)

## Test Scenarios

### Scenario 1: Trigger Setup Failure with Inaccessible Repo

**Given** a logged-in user with a GitHub App installation
**When** the user starts setup with a repository the installation does not have
access to (e.g., a private repo in a different org)
**Then**:

1. The setup POST returns `{ status: "cloning" }` (background clone starts)
2. The clone fails because the installation token cannot access the repo
3. The error is wrapped as `Git clone failed: <sanitized stderr>`
4. `Sentry.captureException` is called with the wrapped error
5. `repo_error` is updated in the database with the truncated message
6. Polling `GET /api/repo/status` returns `{ status: "error", errorMessage: "Git clone failed: ..." }`
7. The UI transitions to the `FailedState` and displays the error card

### Scenario 2: Verify Sentry Receives the Event

**Given** a setup failure has been triggered (Scenario 1)
**When** querying the Sentry API within 5 minutes
**Then** at least one event exists with the error message matching
`/Token generation failed|Git clone failed|Credential helper/`

**API verify:**

```bash
doppler run -c prd -- curl -s "https://sentry.io/api/0/projects/jikigai/soleur-web-platform/issues/?query=&statsPeriod=1h" -H "Authorization: Bearer <SENTRY_API_TOKEN>"
```

### Scenario 3: Verify Error Displayed in UI

**Given** a setup failure has been triggered (Scenario 1)
**When** the user views the failure page
**Then** the page contains:

- "Project Setup Failed" heading
- An "Error details" card with a `font-mono` error message
- The error message contains specific text (e.g., "Git clone failed")
- "Try Again" and "GitHub Status Page" buttons are visible

**Browser:** Navigate to `https://app.soleur.ai/connect-repo`, trigger setup
with an inaccessible repo, wait for failure state, screenshot the error card.

### Scenario 4: Verify Database Persistence

**Given** a setup failure has been triggered (Scenario 1)
**When** querying the `users` table for the test user
**Then** `repo_error` is not null and contains a descriptive error message

**API verify:**

```bash
doppler run -c prd -- curl -s "<SUPABASE_URL>/rest/v1/users?select=repo_status,repo_error&repo_status=eq.error&limit=1" \
  -H "apikey: <SUPABASE_SERVICE_ROLE_KEY>" \
  -H "Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>"
```

## Implementation Approach

### Phase 1: Trigger the Failure and Verify UI (Playwright MCP)

1. Navigate to `https://app.soleur.ai` and authenticate
2. Navigate to `/connect-repo`
3. Select a repository that the GitHub App installation cannot access, OR
   modify the setup request to use a known-inaccessible repo URL
4. Wait for the failure state to appear (poll or wait for UI transition)
5. Screenshot the failure page
6. Confirm the "Error details" card is visible with a specific error message
   (not just "Something went wrong" or the generic heading alone)

**Key consideration:** The setup flow requires a real GitHub App installation.
The simplest approach is to use the founder's account (already has the app
installed) and attempt to clone a repo the installation cannot access. If no
inaccessible repo exists, an alternative is to temporarily revoke repository
access in the GitHub App settings for a specific repo, trigger setup, then
restore access.

### Phase 2: Verify Sentry (API)

1. Wait 2-3 minutes after the failure for Sentry ingestion
2. Query Sentry API for recent issues in `soleur-web-platform`
3. Verify event contains the error message

### Phase 3: Verify Database (API)

1. Query Supabase REST API for the test user's `repo_error` column
2. Verify it contains the expected error message

### Phase 4: Cleanup

1. Reset the test user's `repo_status` to `null` and `repo_error` to `null`
2. Close the Playwright browser

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| No inaccessible repo available to trigger failure | Use a nonexistent private repo URL or temporarily modify GitHub App permissions |
| Sentry ingestion delay exceeds 5 minutes | Retry the Sentry API query with increasing wait intervals (1m, 3m, 5m) |
| Playwright `--isolated` mode requires fresh auth every time | Authenticate via the login flow as the first step in Phase 1 |
| Setup route rejects invalid URL format before reaching clone | Use a valid-format URL (e.g., `https://github.com/octocat/private-repo`) that passes validation but fails at clone |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal verification/follow-through task.

## Files Involved

| File | Role |
|------|------|
| `apps/web-platform/app/api/repo/setup/route.ts` | Setup route with `Sentry.captureException` and `repo_error` persistence |
| `apps/web-platform/app/api/repo/status/route.ts` | Status route returning `errorMessage` |
| `apps/web-platform/components/connect-repo/failed-state.tsx` | UI component displaying error details card |
| `apps/web-platform/server/workspace.ts` | Workspace provisioning with step-specific error wrapping |
| `apps/web-platform/sentry.server.config.ts` | Sentry server configuration |
| `apps/web-platform/supabase/migrations/013_repo_error.sql` | Migration adding `repo_error` column |
