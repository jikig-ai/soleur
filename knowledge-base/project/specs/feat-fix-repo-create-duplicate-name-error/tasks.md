# Tasks: fix repo create duplicate name error

## Phase 1: Add GitHubApiError class

- [ ] 1.1 Add `GitHubApiError` class to `apps/web-platform/server/github-app.ts` (follows `InstallationError` pattern at line 48-55)
- [ ] 1.2 Update `createRepo()` to throw `GitHubApiError(errorMessage, response.status)` instead of `new Error(errorMessage)` (line 565)
- [ ] 1.3 Export `GitHubApiError` from `github-app.ts`

## Phase 2: Update route handler error classification

- [ ] 2.1 Import `GitHubApiError` in `apps/web-platform/app/api/repo/create/route.ts`
- [ ] 2.2 Add early return for `GitHubApiError` with statusCode 422 -- return HTTP 409, skip Sentry
- [ ] 2.3 Add early return for `GitHubApiError` with statusCode 403 -- return HTTP 403, skip Sentry
- [ ] 2.4 Use `logger.warn` (not `logger.error`) for user-facing errors
- [ ] 2.5 Keep existing catch-all for genuine server errors (500 + Sentry)

## Phase 3: Update tests

- [ ] 3.1 Update `test/github-app-create-repo.test.ts` -- verify `createRepo` throws `GitHubApiError` with `statusCode: 422`
- [ ] 3.2 Update `test/create-route-error.test.ts` -- "name already exists" test expects HTTP 409 (not 500)
- [ ] 3.3 Add test: verify `Sentry.captureException` is NOT called for 422/409 errors
- [ ] 3.4 Add test: verify 403 GitHub errors return HTTP 403
- [ ] 3.5 Keep existing test: generic errors still return 500 + Sentry

## Phase 4: Verify

- [ ] 4.1 Run test suite: `cd apps/web-platform && npx vitest run test/create-route-error.test.ts test/github-app-create-repo.test.ts`
- [ ] 4.2 Verify no regressions in other tests
