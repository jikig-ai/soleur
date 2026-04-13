# Tasks: fix-kb-upload-connect-timeout

## Phase 1: Core Implementation

- [ ] 1.1 Add `fetchWithRetry` wrapper to `apps/web-platform/server/github-api.ts`
  - [ ] 1.1.1 Add `GITHUB_FETCH_TIMEOUT_MS = 15_000` constant
  - [ ] 1.1.2 Add `MAX_RETRIES = 2` and `BASE_DELAY_MS = 1_000` constants
  - [ ] 1.1.3 Implement `isRetryable(err)` helper (ConnectTimeoutError, TimeoutError, TypeError)
  - [ ] 1.1.4 Implement `delay(ms)` helper
  - [ ] 1.1.5 Implement `fetchWithRetry(url, init)` with exponential backoff and warn logging
  - [ ] 1.1.6 Replace `fetch` in `githubApiGet` with `fetchWithRetry`
  - [ ] 1.1.7 Replace `fetch` in `githubApiGetText` with `fetchWithRetry`
  - [ ] 1.1.8 Replace `fetch` in `githubApiPost` with `fetchWithRetry`

- [ ] 1.2 Add timeout to `apps/web-platform/server/github-app.ts`
  - [ ] 1.2.1 Add `AbortSignal.timeout(15_000)` to the `githubFetch` helper

- [ ] 1.3 Improve error handling in `apps/web-platform/app/api/kb/upload/route.ts`
  - [ ] 1.3.1 Add timeout/network error check in catch block returning 504 with `GITHUB_TIMEOUT` code

## Phase 2: Testing

- [ ] 2.1 Write unit tests for `fetchWithRetry`
  - [ ] 2.1.1 Test: succeeds on first attempt with no retry
  - [ ] 2.1.2 Test: retries on ConnectTimeoutError and succeeds
  - [ ] 2.1.3 Test: retries on 5xx and succeeds
  - [ ] 2.1.4 Test: does not retry on 4xx (404, 403)
  - [ ] 2.1.5 Test: throws after max retries exhausted
  - [ ] 2.1.6 Test: exponential backoff timing

- [ ] 2.2 Run existing test suite
  - [ ] 2.2.1 Verify all existing tests pass with no modifications

## Phase 3: Validation

- [ ] 3.1 Run markdownlint on changed `.md` files
- [ ] 3.2 Verify no TypeScript compilation errors
