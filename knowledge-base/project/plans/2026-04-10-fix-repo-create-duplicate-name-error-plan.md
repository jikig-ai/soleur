---
title: "fix: handle duplicate repo name as user-facing error, not Sentry exception"
type: fix
date: 2026-04-10
deepened: 2026-04-10
---

# fix: handle duplicate repo name as user-facing error, not Sentry exception

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 4 (Proposed Solution, Technical Considerations, Test Scenarios, References)
**Research sources:** 4 institutional learnings, codebase error-class pattern analysis (`kb/content` route, 5 existing typed error classes), GitHub REST API 422 error format

### Key Improvements

1. Discovered the `kb/content` route (`app/api/kb/content/[...path]/route.ts`) already implements the exact error classification pattern needed -- typed error classes with `instanceof` checks that return appropriate HTTP statuses without calling Sentry. The plan now references this as the canonical pattern.
2. Added `Error.name` assignment in the `GitHubApiError` constructor -- required for correct `instanceof` checks when the error crosses module boundaries in esbuild-bundled code (the custom server uses esbuild).
3. Added logger.warn for user-facing errors with structured context (statusCode, repoName) to maintain observability without Sentry noise.
4. Added edge case: GitHub 422 can also mean invalid repo name format (not just duplicate) -- the same handling applies since both are user-correctable.

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
    this.name = "GitHubApiError";
  }
}
```

### Research Insights (Phase 1)

**Codebase pattern alignment:** The codebase has 5 existing typed error classes that follow this pattern:

- `InstallationError` (`server/github-app.ts:48`) -- string `code` union
- `KbNotFoundError`, `KbAccessDeniedError`, `KbValidationError` (`server/kb-reader.ts`)
- `KeyInvalidError` (`lib/types.ts:19`)

The `kb/content` route (`app/api/kb/content/[...path]/route.ts:51-66`) is the canonical example of this pattern in route handlers -- `instanceof` checks in catch blocks returning appropriate HTTP statuses, with only truly unexpected errors hitting the generic 500 path.

**Edge case -- `Error.name` assignment:** Setting `this.name = "GitHubApiError"` in the constructor ensures correct error identification even when `instanceof` fails across module boundaries (possible in esbuild-bundled code where the custom server compiles `server/index.ts`). This follows the pattern used by `KeyInvalidError` in `lib/types.ts`.

**Edge case -- GitHub 422 is not only duplicate names:** The GitHub API returns 422 for multiple validation failures: duplicate name, invalid characters in name, repo name too long. All are user-correctable, so the same handling (return 409, skip Sentry) is correct for all.

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
    logger.warn(
      { statusCode: err.statusCode, userId: user.id, repoName: name },
      "GitHub API rejected repo creation (user-correctable)",
    );
    return NextResponse.json({ error: err.message }, { status });
  }

  // Genuine server errors -- log and report
  logger.error({ err, userId: user.id, repoName: name }, "Failed to create repository");
  Sentry.captureException(err);
  const message = err instanceof Error ? err.message : "Failed to create repository";
  return NextResponse.json({ error: message }, { status: 500 });
}
```

### Research Insights (Phase 2)

**Observability without noise:** The `logger.warn` call for user-facing errors maintains observability (you can still see how often users hit duplicate names) without polluting error-level monitoring or Sentry. This follows the pattern from the [silent setup failure learning](../../learnings/integration-issues/silent-setup-failure-no-error-capture-20260403.md): three things at every catch site (logging, error reporting, user display) -- but here we intentionally downgrade Sentry from "always" to "server errors only".

**Status code mapping rationale:**

- GitHub 422 --> HTTP 409 (Conflict): Semantically correct for "resource already exists". 422 (Unprocessable Entity) would also work but 409 is more specific and widely used for duplicate resource creation in REST APIs.
- GitHub 403 --> HTTP 403 (Forbidden): Pass-through. The user lacks permission on the GitHub side (e.g., org doesn't allow members to create repos).
- GitHub 404 --> already handled by `InstallationError` in `getInstallationAccount`, which throws before `createRepo`'s response handling.
- GitHub 500/502/503 --> fall through to the generic catch, correctly reported to Sentry as infrastructure errors.

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

- [x] `POST /api/repo/create` returns HTTP 409 (not 500) when the GitHub API returns 422 "name already exists"
- [x] `Sentry.captureException` is NOT called for GitHub 422/403 errors (user-correctable)
- [x] `Sentry.captureException` IS still called for genuine server errors (network failures, 500s, unknown errors)
- [x] Error message from GitHub ("name already exists on this account") is preserved in the JSON response
- [x] Client displays the specific error message (not generic "Project Setup Failed")
- [x] Existing tests updated to reflect new status codes
- [x] `GitHubApiError` class is exported and used consistently in `createRepo`

## Test Scenarios

### Route handler (`create-route-error.test.ts`)

- Given a user tries to create a repo with an existing name, when `createRepo` throws `GitHubApiError` with statusCode 422, then the route returns HTTP 409 with the specific error message and does NOT call `Sentry.captureException`
- Given a user tries to create a repo without sufficient permissions, when `createRepo` throws `GitHubApiError` with statusCode 403, then the route returns HTTP 403 with the error message and does NOT call `Sentry.captureException`
- Given the GitHub API is down, when `createRepo` throws a generic `Error`, then the route returns HTTP 500, calls `Sentry.captureException`, and logs at error level
- Given a non-Error is thrown (string, object), when caught by the route handler, then it returns HTTP 500 with a generic message and calls `Sentry.captureException`
- Given a `GitHubApiError` with statusCode 500 (GitHub server error), when caught by the route handler, then it falls through to the generic catch and reports to Sentry (only 422 and 403 are user-correctable)

### GitHub App module (`github-app-create-repo.test.ts`)

- Given the GitHub API returns 422, when `createRepo` handles the error, then it throws `GitHubApiError` (not plain `Error`) with `statusCode: 422` and the extracted error message
- Given the GitHub API returns 403, when `createRepo` handles the error, then it throws `GitHubApiError` with `statusCode: 403`

### Research Insights (Tests)

**Test isolation from learnings:** Per the existing test file `github-app-create-repo.test.ts`, each test uses a unique `installationId` via `uniqueInstallationId()` to avoid token cache interference. New tests must follow this pattern.

**Negative Sentry assertion:** Use `expect(mockCaptureException).not.toHaveBeenCalled()` for user-facing error tests, and `expect(mockCaptureException).toHaveBeenCalledWith(err)` for server error tests. The existing test file already mocks `@sentry/nextjs` with `mockCaptureException`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- backend error classification fix with no UI layout changes, no new user flows, no financial/legal/marketing impact.

## Technical Considerations

- The `GitHubApiError` class follows the same pattern as the existing `InstallationError` class in `github-app.ts` (line 48-55), maintaining consistency
- The `createPullRequest` function (line 581-637) has the same error pattern -- it should also be updated to throw `GitHubApiError` for consistency, but that is out of scope for this fix (no Sentry reports for PR creation errors currently). `createPullRequest` is called from `agent-runner.ts` (not a route handler), so its error handling context differs.
- HTTP 409 Conflict is the semantically correct status for "resource already exists" -- it is widely used by APIs for duplicate resource creation
- The logger level for user-facing errors should be `warn` (not `error`) to reduce noise in error-level log monitoring

### Research Insights (Technical)

**Sentry context from learnings:** Per [sentry-zero-events learning](../../learnings/integration-issues/sentry-zero-events-production-verification-20260405.md), the Sentry server-side SDK may not be delivering events from production due to a `SENTRY_DSN` env var delivery issue (tracked in #1533). Even if Sentry is currently not receiving events, the fix is still correct -- when the DSN issue is resolved, Sentry should only receive genuine server errors, not user-correctable ones.

**`instanceof` reliability:** The custom server uses esbuild with `@sentry/nextjs` as `--external`. Since `GitHubApiError` and the route handler are both in the app code (not external), they share the same class reference. `instanceof` will work correctly. Setting `this.name` is defense-in-depth for future refactors where the class might move to an external module.

**Client-side error handling gap:** The `handleCreateSubmit` function in `connect-repo/page.tsx` has two call sites for `/api/repo/create` -- the direct call (line 437) and the retry after auto-detection (line 457). Both need to handle the new 409 status. Currently, the retry path does not extract or display error messages from the response -- it falls through to `setPendingCreate` and `setState("github_redirect")`, which is incorrect for a 409 (the user already has a GitHub App installed, the name is just taken). The fix should add 409 handling to both call paths.

**Future consideration -- error code enum:** If more GitHub API errors need classification later, consider an enum or string union on `GitHubApiError` (similar to `InstallationError.code`) rather than relying on raw HTTP status codes. For now, `statusCode: number` is simpler and sufficient.

## References

### Source Files

- `apps/web-platform/server/github-app.ts` (lines 522-573) -- `createRepo` function, error throw site
- `apps/web-platform/app/api/repo/create/route.ts` -- Route handler catch block
- `apps/web-platform/app/(auth)/connect-repo/page.tsx` (handleCreateSubmit, lines 434-487) -- Client-side error handling
- `apps/web-platform/app/api/kb/content/[...path]/route.ts` (lines 51-66) -- Canonical error classification pattern to follow

### Existing Tests

- `apps/web-platform/test/create-route-error.test.ts` -- Route handler error tests (update)
- `apps/web-platform/test/github-app-create-repo.test.ts` -- createRepo unit tests (update)

### Existing Typed Error Classes (pattern references)

- `apps/web-platform/server/github-app.ts:48` -- `InstallationError` (string code union)
- `apps/web-platform/server/kb-reader.ts:40,47,54` -- `KbNotFoundError`, `KbAccessDeniedError`, `KbValidationError`
- `apps/web-platform/lib/types.ts:19` -- `KeyInvalidError`

### Institutional Learnings

- [Silent setup failure](../../learnings/integration-issues/silent-setup-failure-no-error-capture-20260403.md) -- Three things at every catch site: logging, error reporting, user display
- [Sentry zero events](../../learnings/integration-issues/sentry-zero-events-production-verification-20260405.md) -- SENTRY_DSN delivery gap in production
- [Production observability](../../learnings/integration-issues/production-observability-sentry-pino-health-web-platform-20260328.md) -- Sentry integration architecture
- [Fire-and-forget catch](../../learnings/2026-03-20-fire-and-forget-promise-catch-handler.md) -- `instanceof` pattern for typed errors

### External

- Sentry Error ID: `3364ff7d699c40b5b411dcca8286cfe4` (April 7, 2026)
- Related plan: `knowledge-base/project/plans/2026-04-06-fix-create-project-setup-failure-plan.md`
- GitHub API 422 response format: `{ message: "Validation Failed", errors: [{ message: "name already exists on this account" }] }`
