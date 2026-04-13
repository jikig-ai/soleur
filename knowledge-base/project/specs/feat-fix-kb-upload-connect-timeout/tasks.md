# Tasks: fix-kb-upload-connect-timeout

## Phase 1: Core Implementation

- [ ] 1.1 Add `fetchWithRetry` wrapper to `apps/web-platform/server/github-api.ts`
  - [ ] 1.1.1 Add `GITHUB_FETCH_TIMEOUT_MS = 15_000` constant
  - [ ] 1.1.2 Add `MAX_RETRIES = 2` and `BASE_DELAY_MS = 1_000` constants
  - [ ] 1.1.3 Implement `isRetryable(err)` helper using `err.code` for undici errors (`UND_ERR_CONNECT_TIMEOUT`, `UND_ERR_SOCKET`, `ECONNRESET`, `ECONNREFUSED`, `ENOTFOUND`, `ENETDOWN`) plus `DOMException` TimeoutError and `TypeError`
  - [ ] 1.1.4 Implement `delay(ms)` helper
  - [ ] 1.1.5 Implement `fetchWithRetry(url, init)` with exponential backoff, warn logging, and fresh `AbortSignal.timeout()` per attempt
  - [ ] 1.1.6 Add 5xx retry body drain (`response.text().catch(() => {})`) before retry to prevent socket keep-alive issues
  - [ ] 1.1.7 Replace `fetch` in `githubApiGet` with `fetchWithRetry`
  - [ ] 1.1.8 Replace `fetch` in `githubApiGetText` with `fetchWithRetry`
  - [ ] 1.1.9 Replace `fetch` in `githubApiPost` with `fetchWithRetry`

- [ ] 1.2 Add timeout to `apps/web-platform/server/github-app.ts`
  - [ ] 1.2.1 Add `AbortSignal.timeout(15_000)` to the `githubFetch` helper (timeout only, no retry -- retry is at the github-api.ts layer)

- [ ] 1.3 Improve error handling in `apps/web-platform/app/api/kb/upload/route.ts`
  - [ ] 1.3.1 Add `DOMException` TimeoutError check in catch block returning 504 with `GITHUB_TIMEOUT` code
  - [ ] 1.3.2 Add undici `UND_ERR_CONNECT_TIMEOUT` error code check returning 504 with `GITHUB_TIMEOUT` code

## Phase 2: Testing

- [ ] 2.1 Write unit tests in `apps/web-platform/test/github-api-retry.test.ts`
  - [ ] 2.1.1 Test: succeeds on first attempt with no retry
  - [ ] 2.1.2 Test: retries on DOMException TimeoutError and succeeds on second attempt
  - [ ] 2.1.3 Test: retries on UND_ERR_CONNECT_TIMEOUT and succeeds on second attempt
  - [ ] 2.1.4 Test: retries on ECONNRESET and succeeds on second attempt
  - [ ] 2.1.5 Test: retries on 5xx and succeeds on second attempt
  - [ ] 2.1.6 Test: does not retry on 4xx (404, 403)
  - [ ] 2.1.7 Test: throws after max retries exhausted (3 attempts total)
  - [ ] 2.1.8 Test: logs warn on each retry attempt with attempt number and URL

- [ ] 2.2 Run existing test suite
  - [ ] 2.2.1 Verify `kb-upload.test.ts` passes (mocks github-api, transparent to retry)
  - [ ] 2.2.2 Verify `github-app-create-repo.test.ts` passes (mocks globalThis.fetch)
  - [ ] 2.2.3 Verify all other existing tests pass with no modifications

## Phase 3: Validation

- [ ] 3.1 Run markdownlint on changed `.md` files
- [ ] 3.2 Verify no TypeScript compilation errors
- [ ] 3.3 Verify vitest runs via `node node_modules/vitest/vitest.mjs run` (worktree-safe)
