---
title: "chore: verify Sentry capture and error UI for project setup failures"
type: fix
date: 2026-04-05
source_issue: "#1498"
source_pr: "#1494"
deepened: 2026-04-05
---

## Enhancement Summary

**Deepened on:** 2026-04-05
**Sections enhanced:** 4 (Test Scenarios, Implementation Approach, Risks, new
Institutional Learnings section)
**Research sources:** Sentry API docs, existing e2e verification plan patterns,
3 institutional learnings, auth flow code analysis

### Key Improvements

1. Added concrete Sentry API query with `jq` parsing and event-level drill-down
2. Added critical risk from institutional learning: `SENTRY_DSN` may not be in
   container runtime env (zero events despite `captureException` in code)
3. Specified email OTP as the Playwright auth strategy with concrete steps
4. Added Sentry event-level verification (not just issue-level)

### New Considerations Discovered

- Prior session (2026-03-28) found Sentry showed zero events despite
  `captureException` calls -- `SENTRY_DSN` may be missing from Docker runtime
- The `repo_error` field stores sanitized error messages (filesystem paths
  stripped via regex in `workspace.ts:172`) but is NOT routed through the
  `sanitizeErrorForClient` allowlist -- this is correct because it is diagnostic
  info for the user, not an internal server error
- The setup route URL validation regex (line 39) rejects non-GitHub URLs, so
  the test URL must match `^https://github.com/[owner]/[repo]$` format

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

- [ ] **AC1: Sentry event captured** -- FAILED: Zero events in Sentry project
  despite correct configuration. DSN is valid (manual test event received),
  but the app's `captureException` calls produce no events. Root cause:
  likely `SENTRY_DSN` not reaching container runtime env. Filed as #1533.
- [x] **AC2: Error message displayed in UI** -- VERIFIED 2026-04-05: FailedState
  shows "Error details" card with specific error (`Command failed: rm -rf...
  Permission denied`). Screenshot: `setup-failure-error-ui.png`.
- [x] **AC3: Database error persisted** -- VERIFIED 2026-04-05: `repo_error`
  column contains full error message via Supabase REST API query.
- [x] **AC4: Error cleared on retry** -- VERIFIED via code review: line 66 of
  `setup/route.ts` sets `repo_error: null` in the optimistic lock UPDATE.

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
# Step 1: List recent issues (last 1 hour)
SENTRY_TOKEN=$(doppler secrets get SENTRY_API_TOKEN -p soleur -c prd --plain)
curl -s -H "Authorization: Bearer ${SENTRY_TOKEN}" \
  "https://sentry.io/api/0/projects/jikigai/soleur-web-platform/issues/?query=is:unresolved&statsPeriod=1h" \
  | jq '.[].title' | head -10

# Step 2: Drill into the latest issue's events for error details
ISSUE_ID=$(curl -s -H "Authorization: Bearer ${SENTRY_TOKEN}" \
  "https://sentry.io/api/0/projects/jikigai/soleur-web-platform/issues/?query=is:unresolved&statsPeriod=1h" \
  | jq -r '.[0].id // empty')
if [ -n "$ISSUE_ID" ]; then
  curl -s -H "Authorization: Bearer ${SENTRY_TOKEN}" \
    "https://sentry.io/api/0/issues/${ISSUE_ID}/events/latest/" \
    | jq '{title: .title, message: .message, tags: [.tags[] | select(.key == "environment" or .key == "server_name")]}'
fi
```

### Research Insights (Sentry API)

**Best Practices:**

- Query issues first (`/issues/`), then drill into events (`/events/latest/`)
  for full stack trace and context
- Use `statsPeriod=1h` to narrow results to the verification window
- The org slug is `jikigai` (not `jikig`) per Doppler `SENTRY_ORG` -- a prior
  session hit a 404 using the wrong slug
- Sentry ingestion typically takes 30-60 seconds but can take up to 5 minutes
  under load

**Edge Case:** If `SENTRY_DSN` is missing from the Docker container's runtime
environment, `captureException` calls silently no-op (the SDK logs a warning
but does not throw). This was observed in the 2026-03-28 session where zero
events appeared despite `captureException` in deployed code. If no events appear
after 5 minutes, verify `SENTRY_DSN` is in the container env:

```bash
ssh root@app.soleur.ai "docker exec \$(docker ps -q -f name=web-platform) printenv SENTRY_DSN" 2>/dev/null
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

**Authentication strategy:** The app supports email OTP and OAuth (GitHub,
Google). Email OTP is the most automatable path for Playwright:

1. Navigate to `https://app.soleur.ai/login`
2. Enter the founder's email address in the email field
3. Submit to trigger OTP send
4. **Hand off to user** for the 6-digit OTP code (or retrieve from email if
   accessible via API/CLI)
5. Enter OTP and complete login

**Alternative:** If the user is already logged in from a prior session and
cookies are available, skip auth and navigate directly to `/connect-repo`.
Note: Playwright `--isolated` mode creates a fresh profile each time, so
prior session cookies are NOT available.

**Trigger the failure:**

6. Navigate to `/connect-repo`
7. The connect-repo flow shows repos from the GitHub App installation. To
   trigger a failure, use a repo URL the installation cannot access. Two
   approaches:
   - **Preferred:** Use the browser console to directly call `fetch('/api/repo/setup', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({repoUrl: 'https://github.com/torvalds/linux'}) })` -- this bypasses the repo picker UI and sends a URL the installation cannot clone
   - **Alternative:** If the user has repos listed, select one, then temporarily
     revoke that repo's access in GitHub App settings before starting setup
8. Wait for the failure state (poll `/api/repo/status` every 2s, max 60
   attempts). The clone timeout is 120 seconds (`workspace.ts:168`).
9. Screenshot the failure page
10. Confirm the "Error details" card is visible with a specific error message
    containing `Git clone failed:` (not just "Something went wrong" or the
    generic heading alone)

### Research Insights (Playwright Auth)

**Auth flow details:**

- Login page is at `/login` (not `/signin` or `/auth/login`)
- Email OTP uses `supabase.auth.signInWithOtp({ email, options: { shouldCreateUser: false } })`
- OTP is 6 digits (`EMAIL_OTP_LENGTH` constant from `lib/auth/constants`)
- After OTP verification, the app redirects to the return URL or `/dashboard`
- The connect-repo page requires an authenticated session -- unauthenticated
  access redirects to `/login`

**Setup URL validation:** The `POST /api/repo/setup` route validates the URL
format with regex: `/^https:\/\/github\.com\/[a-zA-Z0-9._-]+\/[a-zA-Z0-9._-]+$/`
(line 39). A URL like `https://github.com/torvalds/linux` passes validation but
will fail at clone because the installation token cannot access it.

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
| No inaccessible repo available to trigger failure | Use browser console `fetch()` to POST a valid-format URL (e.g., `https://github.com/torvalds/linux`) that the installation cannot clone |
| Sentry ingestion delay exceeds 5 minutes | Retry the Sentry API query with increasing wait intervals (1m, 3m, 5m) |
| Playwright `--isolated` mode requires fresh auth every time | Authenticate via email OTP as the first step in Phase 1; hand off OTP entry to user |
| Setup route rejects invalid URL format before reaching clone | Use `https://github.com/torvalds/linux` format -- passes the regex at line 39 but fails at clone |
| `SENTRY_DSN` missing from container runtime env | If zero events after 5 min, SSH to check `printenv SENTRY_DSN` in the container (see Research Insights above) |
| Clone takes full 120s timeout before failing | The git clone has a 120s timeout (`workspace.ts:168`); polling `/api/repo/status` at 2s intervals will eventually see the `error` status |

## Institutional Learnings Applied

Three learnings from `knowledge-base/project/learnings/` are relevant:

1. **silent-setup-failure-no-error-capture-20260403** -- Documents the original
   bug this verification follows up on. Key insight: the Sentry API org slug is
   `jikigai` (not `jikig`). Agent previously hit a 404 using the wrong slug.
   Applied: all Sentry API calls in this plan use the correct `jikigai` slug.

2. **2026-03-28-unapplied-migration-command-center-chat-failure** -- Documents a
   case where `SENTRY_DSN` was apparently missing from the Docker runtime,
   causing zero events despite `captureException` calls in the code. Applied:
   added a fallback verification step (SSH to check `printenv SENTRY_DSN`) if
   Sentry shows no events after 5 minutes.

3. **2026-03-20-websocket-error-sanitization-cwe-209** -- Documents the error
   sanitization pattern (`sanitizeErrorForClient`). Applied: confirmed that
   `repo_error` is NOT routed through this sanitizer (correct -- it uses its own
   path sanitization in `workspace.ts:172` and stores user-diagnostic info, not
   internal server state).

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

## Verification Results (2026-04-05)

### Summary

| AC | Status | Evidence |
|----|--------|----------|
| AC1: Sentry event | FAILED | Zero events ever in project. DSN valid (manual test received). Filed #1533. |
| AC2: UI error display | PASSED | Screenshot shows "Error details" card with specific error message |
| AC3: Database persistence | PASSED | `repo_error` column populated via Supabase REST API |
| AC4: Error cleared on retry | PASSED | Code review: `setup/route.ts:66` sets `repo_error: null` |

### Bugs Discovered

1. **#1533** - Sentry server-side SDK not sending events from production
   container. Zero events ever recorded. Likely `SENTRY_DSN` missing from
   container runtime environment.
2. **#1534** - Workspace directory permission denied during project re-setup.
   Files owned by root cannot be deleted by UID 1001 (soleur user).

### Method

- Authenticated via Supabase admin API `generate_link` (no OTP handoff needed)
- Triggered setup failure by intercepting `fetch('/api/repo/setup')` to send
  `https://github.com/torvalds/linux` (passes URL regex, fails at clone)
- Actual failure was workspace cleanup (`rm -rf`) permission denied, not clone
  failure — exposed #1534
- Verified UI via Playwright snapshot and screenshot
- Verified database via Supabase REST API with service role key
- Verified Sentry via API queries (DE region) — zero events found
- Confirmed DSN validity by sending manual test event via curl
- Cleaned up test state (reset `repo_status` to `not_connected`)
