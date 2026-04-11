# Tasks: fix repo create duplicate name error

## Phase 1: Add GitHubApiError class

- [x] 1.1 Add `GitHubApiError` class to `apps/web-platform/server/github-app.ts` (follows `InstallationError` pattern at line 48-55)
- [x] 1.2 Update `createRepo()` to throw `GitHubApiError(errorMessage, response.status)` instead of `new Error(errorMessage)` (line 565)
- [x] 1.3 Export `GitHubApiError` from `github-app.ts`

## Phase 2: Update route handler error classification

- [x] 2.1 Import `GitHubApiError` in `apps/web-platform/app/api/repo/create/route.ts`
- [x] 2.2 Add early return for `GitHubApiError` with statusCode 422 -- return HTTP 409, skip Sentry
- [x] 2.3 Add early return for `GitHubApiError` with statusCode 403 -- return HTTP 403, skip Sentry
- [x] 2.4 Use `logger.warn` (not `logger.error`) for user-facing errors
- [x] 2.5 Keep existing catch-all for genuine server errors (500 + Sentry)

## Phase 3: Update tests

- [x] 3.1 Update `test/github-app-create-repo.test.ts` -- verify `createRepo` throws `GitHubApiError` with `statusCode: 422`
- [x] 3.2 Update `test/create-route-error.test.ts` -- "name already exists" test expects HTTP 409 (not 500)
- [x] 3.3 Add test: verify `Sentry.captureException` is NOT called for 422/409 errors
- [x] 3.4 Add test: verify 403 GitHub errors return HTTP 403
- [x] 3.5 Keep existing test: generic errors still return 500 + Sentry

## Phase 4: Verify

- [x] 4.1 Run test suite: `cd apps/web-platform && npx vitest run test/create-route-error.test.ts test/github-app-create-repo.test.ts`
- [x] 4.2 Verify no regressions in other tests (655 passed, 0 failed)
