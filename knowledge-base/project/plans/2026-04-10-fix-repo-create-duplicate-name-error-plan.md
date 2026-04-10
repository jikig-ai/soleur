---
title: "fix: handle duplicate repo name as user-facing error, not Sentry exception"
type: fix
date: 2026-04-10
---

# fix: handle duplicate repo name as user-facing error, not Sentry exception

## Problem

When a user tries to create a repository with a name that already exists on their GitHub account, the `POST /api/repo/create` endpoint throws an unhandled exception that gets reported to Sentry (Error ID: `3364ff7d699c40b5b411dcca8286cfe4`, April 7 2026). The GitHub API returns a 422 with `errors: [{ message: "name already exists on this account" }]`, which `createRepo()` correctly extracts into an `Error` message -- but the route handler treats ALL `createRepo` errors as 500 Internal Server Errors and reports them all to Sentry.

This is a user-correctable condition (pick a different name), not a system failure. It should not pollute Sentry alerts or return a 500 status code.

## Root Cause Analysis

The error flows through three layers, each with a gap:

### Layer 1: `server/github-app.ts` -- `createRepo()` (line 548-565)

When GitHub returns a 422 (Validation Failed), `createRepo` extracts the error message and throws a plain `Error("name already exists on this account")`. There is no way for callers to distinguish a user error (duplicate name, invalid name) from an infrastructure error (rate limit, network failure, auth failure).

### Layer 2: `app/api/repo/create/route.ts` -- `POST` handler (line 61-79)

The catch block:

1. Logs the error at `error` level (correct for server errors, noisy for user errors)
2. Calls `Sentry.captureException(err)` unconditionally -- user errors become Sentry noise
3. Returns HTTP 500 for all errors -- even for a 422 from GitHub that should map to 409 Conflict

### Layer 3: Client (`connect-repo/page.tsx` -- `handleCreateSubmit`, line 434-487)

The client only checks `createRes.ok` vs `createRes.status === 400`. A 500 response with status !== 400 falls through to `setState("failed")` which shows the generic `FailedState` component with "Project Setup Failed" -- unhelpful for "that name is taken, try another".

## Proposed Solution

Introduce a typed error class to distinguish user-facing GitHub API errors from infrastructure errors, then handle them appropriately at each layer.

### Phase 1: Add `GitHubApiError` class (`server/github-app.ts`)

Add a new error class that carries the HTTP status from the GitHub API:

```typescript
// server/github-app.ts
export class GitHubApiError extends Error {
  constructor(
    message: string,
    public readonly statusCode: number,
  ) {
    super(message);
  }
}
```

Update `createRepo()` to throw `GitHubApiError` instead of plain `Error` when the GitHub API returns a non-ok response:

```typescript
// In createRepo(), replace: throw new Error(errorMessage);
throw new GitHubApiError(errorMessage, response.status);
```

### Phase 2: Classify errors in route handler (`app/api/repo/create/route.ts`)

Update the catch block to check for `GitHubApiError` and map known status codes to appropriate HTTP responses:

- GitHub 422 (Validation Failed / duplicate name) --> HTTP 409 Conflict (user-facing, no Sentry)
- GitHub 403 (permissions) --> HTTP 403 Forbidden (user-facing, no Sentry)
- All other errors --> HTTP 500 (server error, report to Sentry)

```typescript
// route.ts catch block
catch (err) {
  // User-correctable GitHub API errors -- return appropriate status, skip Sentry
  if (err instanceof GitHubApiError && (err.statusCode === 422 || err.statusCode === 403)) {
    const status = err.statusCode === 422 ? 409 : 403;
    return NextResponse.json({ error: err.message }, { status });
  }

  // Genuine server errors -- log and report
  logger.error({ err, userId: user.id, repoName: name }, "Failed to create repository");
  Sentry.captureException(err);
  const message = err instanceof Error ? err.message : "Failed to create repository";
  return NextResponse.json({ error: message }, { status: 500 });
}
```

### Phase 3: Handle 409 on the client (`connect-repo/page.tsx`)

Update `handleCreateSubmit` to detect 409 and show an inline error on the create form instead of navigating to the `FailedState`:

```typescript
// In handleCreateSubmit, after const errorData = ...
if (createRes.status === 409) {
  setSetupError(errorData?.error ?? "A repository with that name already exists");
  setState("failed");
  return;
}
```

Also update the `FailedState` component to show a contextual message for duplicate-name errors (or alternatively, return the user to the `create_project` state with an error message on the form).

Better approach: return to the create form with the error visible, rather than showing the generic failure page. This means `handleCreateSubmit` needs to propagate the error back to `CreateProjectState`. Currently `onSubmit` is fire-and-forget (returns void). Two options:

**Option A (simpler):** Keep the `FailedState` but make its message context-aware. The `errorMessage` prop already carries the specific error text. The user sees "name already exists on this account" in the error details card.

**Option B (better UX):** Have `handleCreateSubmit` set an error state that prevents transition away from `create_project`. This requires making `onSubmit` async and having `CreateProjectState` display the server error.

Recommend **Option A** for MVP since the infrastructure is already in place (`FailedState` displays `errorMessage`). The critical fix is the HTTP status code and Sentry classification. Option B can be a follow-up UX improvement.

### Phase 4: Update existing tests

Update `create-route-error.test.ts`:

- Change the "name already exists" test to expect status 409 (not 500)
- Verify `Sentry.captureException` is NOT called for 422 errors
- Add a test for 403 errors returning 403
- Keep the generic error test expecting 500 + Sentry

Update `github-app-create-repo.test.ts`:

- Verify `createRepo` throws `GitHubApiError` (not plain `Error`) with the correct `statusCode`

## Acceptance Criteria

- [ ] `POST /api/repo/create` returns HTTP 409 (not 500) when the GitHub API returns 422 "name already exists"
- [ ] `Sentry.captureException` is NOT called for GitHub 422/403 errors (user-correctable)
- [ ] `Sentry.captureException` IS still called for genuine server errors (network failures, 500s, unknown errors)
- [ ] Error message from GitHub ("name already exists on this account") is preserved in the JSON response
- [ ] Client displays the specific error message (not generic "Project Setup Failed")
- [ ] Existing tests updated to reflect new status codes
- [ ] `GitHubApiError` class is exported and used consistently in `createRepo`

## Test Scenarios

- Given a user tries to create a repo with an existing name, when the GitHub API returns 422, then the route returns HTTP 409 with the specific error message and does not call Sentry
- Given a user tries to create a repo without sufficient permissions, when the GitHub API returns 403, then the route returns HTTP 403 with the error message and does not call Sentry
- Given the GitHub API is down, when the user tries to create a repo, then the route returns HTTP 500, calls Sentry, and logs the error
- Given a non-Error is thrown (string, object), when caught by the route handler, then it returns HTTP 500 with a generic message and calls Sentry
- Given the client receives a 409 from the create endpoint, when displaying the error, then it shows the specific error message from the response body

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- backend error classification fix with no UI layout changes, no new user flows, no financial/legal/marketing impact.

## Technical Considerations

- The `GitHubApiError` class follows the same pattern as the existing `InstallationError` class in `github-app.ts` (line 48-55), maintaining consistency
- The `createPullRequest` function (line 581-637) has the same error pattern -- it should also be updated to throw `GitHubApiError` for consistency, but that is out of scope for this fix (no Sentry reports for PR creation errors currently)
- HTTP 409 Conflict is the semantically correct status for "resource already exists" -- it is widely used by APIs for duplicate resource creation
- The logger level for user-facing errors should be `warn` (not `error`) to reduce noise in error-level log monitoring

## References

- Sentry Error ID: `3364ff7d699c40b5b411dcca8286cfe4` (April 7, 2026)
- Source: `apps/web-platform/server/github-app.ts` (lines 522-573)
- Route: `apps/web-platform/app/api/repo/create/route.ts`
- Client: `apps/web-platform/app/(auth)/connect-repo/page.tsx` (handleCreateSubmit, line 434-487)
- Existing tests: `apps/web-platform/test/create-route-error.test.ts`, `apps/web-platform/test/github-app-create-repo.test.ts`
- Related plan: `knowledge-base/project/plans/2026-04-06-fix-create-project-setup-failure-plan.md`
- GitHub API 422 response format: `{ message: "Validation Failed", errors: [{ message: "name already exists on this account" }] }`
