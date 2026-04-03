---
module: web-platform
date: 2026-04-03
problem_type: integration_issue
component: tooling
symptoms:
  - "Project setup fails at 'Copying your project files' step"
  - "Generic 'Project Setup Failed' error with no details"
  - "Sentry receives zero events from production (7-day window)"
  - "repo_status set to 'error' but no error message preserved"
root_cause: incomplete_setup
resolution_type: code_fix
severity: high
tags: [error-handling, sentry, observability, project-setup, workspace-provisioning]
---

# Silent Project Setup Failure — No Error Capture

## Problem

After connecting a GitHub repository, the setup process fails at "Copying your project files" with a generic error page. The actual error is invisible because:

1. `provisionWorkspaceWithRepo` throws undecorated errors (no step identification)
2. The `.catch()` handler in `setup/route.ts` logs via pino but does NOT call `Sentry.captureException()`
3. No `repo_error` column exists to persist the error message
4. The UI shows "Something went wrong" with no details

## Investigation

- Queried Sentry API — zero events in 7 days (confirmed Sentry was working but no `captureException` calls existed in the setup route)
- Checked production database — user stuck with `repo_status: "error"` and no error details
- Traced code path: `provisionWorkspaceWithRepo` → token generation → credential helper write → git clone → any failure propagates as generic error to `.catch()` which sets `repo_status: "error"` only

## Solution

1. **Error wrapping** (`server/workspace.ts`): Each step wrapped in individual try-catch with descriptive messages:
   - `Token generation failed: <original message>`
   - `Credential helper write failed: <original message>`
   - `Git clone failed: <sanitized stderr>`
2. **Sentry capture** (`app/api/repo/setup/route.ts`): Added `Sentry.captureException(err)` in the `.catch()` handler
3. **Error persistence**: Added `repo_error` column (migration 013), stored truncated error message (max 2000 chars) in `.catch()`, cleared on retry
4. **Error display**: Status route returns `errorMessage` when `status === "error"`, FailedState component shows error details card
5. **Timer cleanup**: Clear step animation timer when POST fails (was running after error)
6. **Path sanitization**: Strip internal filesystem paths from git stderr before storing (security review finding)

## Key Insight

Background tasks that fire-and-forget (like `provisionWorkspaceWithRepo`) need three things at the catch site: (1) structured logging, (2) error reporting to Sentry, and (3) error persistence in the database for user-facing display. Missing any one creates an observability blind spot. The "temporarily generic error page" pattern becomes permanent when nobody can see what's failing.

## Session Errors

1. **Sentry API 404 due to wrong org slug** — Used `jikig` instead of `jikigai` when querying Sentry API. Recovery: checked `SENTRY_ORG` in Doppler prd config. **Prevention:** Always read `SENTRY_ORG` from Doppler before constructing Sentry API URLs.

## Tags

category: integration-issues
module: web-platform
