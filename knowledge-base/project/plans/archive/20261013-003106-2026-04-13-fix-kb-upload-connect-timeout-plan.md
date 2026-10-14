---
title: "fix: add timeout and retry to GitHub API fetch calls in kb/upload"
type: fix
date: 2026-04-13
---

# fix: Add timeout and retry to GitHub API fetch calls in kb/upload

## Enhancement Summary

**Deepened on:** 2026-04-13
**Sections enhanced:** 5
**Research sources used:** Context7 undici docs, existing codebase patterns (service-tools.ts, kb-upload.test.ts, github-app-create-repo.test.ts), institutional learnings

### Key Improvements

1. Replaced custom `fetchWithRetry` wrapper with simpler `AbortSignal.timeout()` + single-retry approach -- undici's built-in retry interceptor exists but requires `setGlobalDispatcher` which would affect all fetch calls globally; scoped retry is safer
2. Added `isRetryableError` type guard that correctly handles undici's `UND_ERR_CONNECT_TIMEOUT` error code (not just string matching)
3. Added IPv6 autoselection consideration -- undici docs note `UND_ERR_CONNECT_TIMEOUT` can be caused by IPv6 resolution failures on servers without IPv6 connectivity
4. Added concrete test file location and patterns matching existing test infrastructure

### New Considerations Discovered

- Undici's `ConnectTimeoutError` uses error code `UND_ERR_CONNECT_TIMEOUT`, not the string `"ConnectTimeoutError"` in the message -- the `isRetryable` check must use `err.code` not `err.message.includes()`
- The `AbortSignal.timeout()` approach creates a new signal per fetch call, which is correct -- but when combined with retry, each retry attempt needs its own fresh signal (the original signal may already be aborted)
- Node.js 22 (used in Dockerfile) ships undici 7.x which has the `autoSelectFamily` option that can prevent IPv6-related connect timeouts
- The `github-app.ts` `githubFetch` wrapper is called by multiple functions (`getInstallationAccount`, `verifyInstallationOwnership`, `findInstallationForLogin`, `listInstallationRepos`, `createRepo`, `createPullRequest`) -- fixing it there provides broad coverage

## Overview

The `POST /api/kb/upload` route fails with `ConnectTimeoutError` when the underlying `fetch` call to `api.github.com:443` exceeds the default undici connect timeout of 10 seconds. This manifests as "Upload failed. Please try again." on CTO and CPO agent icon upload fields in the team settings UI, introduced by PR #2130 (agent identity badges and team icon customization).

Sentry error ID: `257bcd0e7edf435795e46c42c77639a5`

## Problem Statement

The `github-api.ts` module (`apps/web-platform/server/github-api.ts`) wraps all GitHub API calls for the platform. Its `fetch` calls use no explicit timeout or retry logic:

```typescript
// github-api.ts:29 — no signal, no retry
const response = await fetch(`${GITHUB_API}${path}`, {
  headers: { ... },
});
```

When the Node.js runtime cannot establish a TCP connection to `api.github.com:443` within undici's default 10-second connect timeout, a `ConnectTimeoutError` is thrown. This error is not caught by the `handleErrorResponse` function (which only handles HTTP-level errors from `response.ok`) and bubbles up as an unhandled exception.

The upload route has two sequential GitHub API calls that are vulnerable:

1. **`githubApiGet`** (line 187) -- checks if file already exists (duplicate detection)
2. **`githubApiPost`** (line 223) -- uploads the file via PUT to Contents API

Additionally, `generateInstallationToken` in `github-app.ts` also makes a `fetch` call to exchange a JWT for an installation token, which is equally vulnerable to the same connect timeout.

### Root Cause Analysis

The `ConnectTimeoutError` is a TCP-level failure (cannot establish connection within the timeout window), not an HTTP-level failure. Likely causes:

- **Transient DNS resolution delays** on the Hetzner server
- **GitHub API rate limiting at the TCP level** (connection throttling)
- **Network congestion** between the Hetzner datacenter and GitHub's CDN edge
- **IPv6 resolution failures** -- undici docs note that `UND_ERR_CONNECT_TIMEOUT` can be caused by local network/ISP limitations with IPv6 when servers resolve to IPv6 addresses (Node.js 18.3.0+ supports `autoSelectFamily` to mitigate)

The 10-second default is reasonable for most scenarios, but the upload route chains multiple GitHub API calls (token exchange + duplicate check + file upload), so a single transient timeout fails the entire operation.

### Research Insights

**Undici error codes:** The `ConnectTimeoutError` thrown by undici uses `err.code === 'UND_ERR_CONNECT_TIMEOUT'`, not a string in the message property. The `isRetryable` check must inspect `err.code` for reliable detection.

**Undici built-in retry:** Undici 7.x (shipped with Node.js 22 per Dockerfile) provides a built-in `retry` interceptor via `interceptors.retry()` and a `RetryAgent` class. However, these operate at the dispatcher level and require `setGlobalDispatcher()` or creating a custom `Client`/`Agent` instance. Using them would affect all `fetch()` calls globally, which is undesirable -- other fetch calls in the codebase (Plausible, Supabase) have their own timeout/retry strategies. A scoped retry wrapper is the safer approach.

**Undici retryable error codes:** The built-in retry interceptor defaults to retrying on: `ECONNRESET`, `ECONNREFUSED`, `ENOTFOUND`, `ENETDOWN`, `EHOSTDOWN`, `UND_ERR_SOCKET`. Notably, `UND_ERR_CONNECT_TIMEOUT` is NOT in the default list -- it must be explicitly added.

## Proposed Solution

Add `AbortSignal.timeout()` and a retry-with-backoff wrapper to `github-api.ts`. This follows the existing pattern in `service-tools.ts` (Plausible API calls use `AbortSignal.timeout(5_000)`).

### Changes

#### 1. Add timeout to all fetch calls in `github-api.ts`

Add `signal: AbortSignal.timeout(GITHUB_FETCH_TIMEOUT_MS)` to every `fetch` call in `githubApiGet`, `githubApiGetText`, and `githubApiPost`. Use 15 seconds (generous for a single request but bounded).

```typescript
// apps/web-platform/server/github-api.ts
const GITHUB_FETCH_TIMEOUT_MS = 15_000;
```

#### 2. Add a retry wrapper for transient failures

Create a `fetchWithRetry` helper that retries on `ConnectTimeoutError`, `TypeError` (network error), and 5xx responses. Use exponential backoff (1s, 2s) with max 3 attempts. This is scoped to `github-api.ts` only -- not a global retry.

```typescript
// apps/web-platform/server/github-api.ts
const MAX_RETRIES = 2; // 3 total attempts
const BASE_DELAY_MS = 1_000;

async function fetchWithRetry(
  url: string,
  init: RequestInit,
): Promise<Response> {
  let lastError: Error | null = null;
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try {
      // Each attempt gets a fresh AbortSignal — a timed-out signal cannot be reused
      const response = await fetch(url, {
        ...init,
        signal: AbortSignal.timeout(GITHUB_FETCH_TIMEOUT_MS),
      });
      // Retry on 5xx (GitHub transient errors)
      if (response.status >= 500 && attempt < MAX_RETRIES) {
        lastError = new Error(`GitHub API ${response.status}`);
        await delay(BASE_DELAY_MS * 2 ** attempt);
        continue;
      }
      return response;
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));
      if (attempt < MAX_RETRIES && isRetryable(err)) {
        log.warn(
          { attempt: attempt + 1, err: lastError.message, url },
          "GitHub API fetch failed — retrying",
        );
        await delay(BASE_DELAY_MS * 2 ** attempt);
        continue;
      }
      throw lastError;
    }
  }
  throw lastError;
}

function isRetryable(err: unknown): boolean {
  // AbortSignal.timeout() fires a DOMException with name "TimeoutError"
  if (err instanceof DOMException && err.name === "TimeoutError") return true;
  // Network-level errors (DNS failure, connection refused)
  if (err instanceof TypeError) return true;
  // Undici-specific error codes (ConnectTimeoutError, SocketError, etc.)
  if (
    err instanceof Error &&
    "code" in err &&
    typeof (err as { code: unknown }).code === "string"
  ) {
    const code = (err as { code: string }).code;
    return [
      "UND_ERR_CONNECT_TIMEOUT",
      "UND_ERR_SOCKET",
      "ECONNRESET",
      "ECONNREFUSED",
      "ENOTFOUND",
      "ENETDOWN",
    ].includes(code);
  }
  return false;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
```

### Research Insights -- Retry Implementation

**Fresh signal per attempt:** Each retry attempt creates a new `AbortSignal.timeout()`. A timed-out signal is permanently aborted and cannot be reused. The original plan already had this correct via the `fetch` call inside the loop, but it is worth calling out explicitly.

**Error code detection:** The `isRetryable` function uses `err.code` (undici convention) rather than `err.message.includes()`. This is more reliable because error messages can be localized or change between versions, while error codes are part of the API contract.

**Retry scope matches undici defaults:** The error code list (`ECONNRESET`, `ECONNREFUSED`, `ENOTFOUND`, `ENETDOWN`) matches undici's built-in retry interceptor defaults, plus `UND_ERR_CONNECT_TIMEOUT` (which undici does NOT retry by default).

**No jitter needed:** At the concurrency level of this endpoint (one upload per user session), collision risk is negligible. Jitter would add complexity without benefit.

#### 3. Add timeout to `github-app.ts` fetch calls

The `githubFetch` helper in `github-app.ts` (line 190-203) also lacks a timeout. Add `AbortSignal.timeout(15_000)` to the `githubFetch` helper. This covers all callers: `getInstallationAccount`, `verifyInstallationOwnership`, `findInstallationForLogin`, `listInstallationRepos`, `createRepo`, `createPullRequest`, and `generateInstallationToken`.

```typescript
// apps/web-platform/server/github-app.ts — githubFetch helper
async function githubFetch(
  url: string,
  options: RequestInit = {},
): Promise<Response> {
  const response = await fetch(url, {
    ...options,
    signal: AbortSignal.timeout(15_000),
    headers: {
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      ...options.headers,
    },
  });
  return response;
}
```

**Note:** The `githubFetch` in `github-app.ts` does NOT get retry logic -- only the timeout. Retry is scoped to `github-api.ts` (the high-level wrapper used by route handlers). The `github-app.ts` functions are lower-level and called by `github-api.ts` which already retries at a higher level. Adding retry at both layers would cause multiplicative retry counts.

### Research Insights -- Timeout Placement

**Two layers, one retry:** The architecture has two GitHub fetch layers:

1. `github-app.ts` -- low-level (token exchange, installation lookups)
2. `github-api.ts` -- high-level (wraps `github-app.ts` for route handlers)

Timeouts go on both layers (defense-in-depth). Retry goes on `github-api.ts` only (the caller-facing layer). This avoids the N*M retry explosion (e.g., 3 retries at high level* 3 retries at low level = 9 total attempts).

**Signal conflict avoidance:** When `githubApiGet`/`githubApiPost` call `generateInstallationToken` (which calls `githubFetch`), the token exchange has its own 15s timeout independent of the outer `fetchWithRetry` timeout. If the token exchange times out, `fetchWithRetry` catches it as a retryable error and retries the entire operation (including a fresh token exchange). This is correct behavior.

#### 4. Improve error handling in the upload route

The catch block in `route.ts` (line 285-310) checks for `error.message.includes("GitHub API")` but `ConnectTimeoutError` does not contain that string. Add a check for timeout/network errors to return a more descriptive 504 Gateway Timeout:

```typescript
// apps/web-platform/app/api/kb/upload/route.ts — in the catch block, BEFORE the GitHub API check
if (error instanceof DOMException && error.name === "TimeoutError") {
  logger.error(
    { err: error, userId: user.id, path: filePath },
    "kb/upload: GitHub API connect timeout",
  );
  return NextResponse.json(
    { error: "GitHub API timed out. Please try again.", code: "GITHUB_TIMEOUT" },
    { status: 504 },
  );
}

// Also catch undici-specific connect timeout (may not be a DOMException)
if (
  error instanceof Error &&
  "code" in error &&
  (error as { code: string }).code === "UND_ERR_CONNECT_TIMEOUT"
) {
  logger.error(
    { err: error, userId: user.id, path: filePath },
    "kb/upload: GitHub API connect timeout (undici)",
  );
  return NextResponse.json(
    { error: "GitHub API timed out. Please try again.", code: "GITHUB_TIMEOUT" },
    { status: 504 },
  );
}
```

### Research Insights -- Error Handling

**Two timeout error types:** After retries are exhausted, the error reaching the route handler can be either:

1. A `DOMException` with `name === "TimeoutError"` (from `AbortSignal.timeout()`)
2. An undici `ConnectTimeoutError` with `code === "UND_ERR_CONNECT_TIMEOUT"` (from undici's internal connect timeout, which fires before the AbortSignal in some cases)

Both must be caught. The existing pattern in `service-tools.ts` only checks `DOMException` because it uses `AbortSignal.timeout(5_000)` which fires before undici's 10s default. With our 15s timeout, the undici connect timeout (10s) fires first in the connect-timeout scenario, so the undici error type takes precedence.

**Alternative approach considered:** Could set undici's connect timeout higher (e.g., 30s) via a custom dispatcher to ensure `AbortSignal.timeout()` always fires first. Rejected because it requires `setGlobalDispatcher` (global impact) or per-request dispatcher (complex). Catching both error types is simpler and more robust.

## Technical Considerations

- **Architecture impact:** Minimal. Changes are scoped to the GitHub API fetch layer. All existing callers benefit from retry logic without changes.
- **Performance:** Worst case adds ~3 seconds (two retries with 1s + 2s backoff) before failing. This is acceptable for an upload operation that already involves network round-trips.
- **Security:** No new attack surface. `AbortSignal.timeout()` is a standard Web API. Retry logic does not expose additional information.
- **Concurrency:** Retries are per-request, not queued. No risk of retry storms because upload is user-initiated (one at a time per user).
- **Existing callers:** All functions using `githubApiGet`, `githubApiGetText`, `githubApiPost` automatically get retry. All functions using `githubFetch` in `github-app.ts` automatically get the timeout. No caller changes needed.

### Edge Cases

- **Caller-supplied AbortSignal:** Currently none of the `github-api.ts` functions accept an external signal. If one is added in the future, it must be combined with the timeout signal via `AbortSignal.any([external, AbortSignal.timeout(N)])`. Not needed now.
- **5xx retry consuming response body:** When retrying on 5xx, the response body from the failed attempt is not consumed. In Node.js, unconsumed response bodies can cause socket keep-alive issues. The `fetchWithRetry` function should call `response.text().catch(() => {})` before retrying to drain the body. Add this.
- **Token cache invalidation on retry:** `generateInstallationToken` has an in-memory cache. If a token exchange fails mid-retry, the cache entry is not poisoned because the cache only stores successful responses. No issue here.
- **Rate limit headers:** GitHub returns `X-RateLimit-Remaining` and `Retry-After` headers on 429 responses. The current retry logic treats 429 as a 4xx (no retry). This is debatable but acceptable -- 429s from GitHub indicate the rate limit is exhausted and retrying immediately would fail again. A separate rate-limit-aware retry could be added later.

## Acceptance Criteria

- [x] `githubApiGet`, `githubApiGetText`, and `githubApiPost` in `github-api.ts` use `fetchWithRetry` which includes `AbortSignal.timeout(15_000)` on every fetch call
- [x] A `fetchWithRetry` wrapper retries on `UND_ERR_CONNECT_TIMEOUT`, `ECONNRESET`, `ECONNREFUSED`, `ENOTFOUND`, `ENETDOWN`, `UND_ERR_SOCKET`, `TypeError`, `TimeoutError`, and 5xx responses with exponential backoff (max 3 attempts)
- [x] `githubFetch` in `github-app.ts` includes `AbortSignal.timeout(15_000)` on every fetch call (timeout only, no retry at this layer)
- [x] The upload route (`app/api/kb/upload/route.ts`) returns HTTP 504 with `{ code: "GITHUB_TIMEOUT" }` when GitHub API times out (after retries exhausted)
- [x] Both `DOMException` timeout and undici `UND_ERR_CONNECT_TIMEOUT` are caught in the upload route error handler
- [x] Retry attempts are logged at `warn` level with attempt number, error message, and URL
- [x] 5xx retry drains the response body before retrying to prevent socket issues
- [x] Existing tests pass without modification
- [x] No changes to the client-side upload code (team-settings.tsx) -- the retry is server-side

## Test Scenarios

- Given a working GitHub API connection, when uploading a team icon, then the upload succeeds on the first attempt with no retry logging
- Given a transient connect timeout on the first attempt, when uploading a team icon, then the retry succeeds and the upload completes
- Given persistent connect timeouts (all 3 attempts), when uploading a team icon, then the route returns HTTP 504 with `code: "GITHUB_TIMEOUT"` and Sentry captures the error
- Given a GitHub 500 response on the first attempt, when making any GitHub API call, then the retry succeeds on the second attempt
- Given a GitHub 404 response (file not found during duplicate check), when uploading a new file, then no retry occurs (404 is not retryable) and upload proceeds normally
- Given a GitHub 403 response, when making any GitHub API call, then no retry occurs (permission errors are not transient)
- Given an `ECONNRESET` error on the first attempt, when making any GitHub API call, then the retry succeeds on the second attempt
- Given a DOMException TimeoutError (from AbortSignal.timeout), when retries are exhausted, then the upload route returns HTTP 504 with descriptive message
- Given an undici UND_ERR_CONNECT_TIMEOUT error, when retries are exhausted, then the upload route returns HTTP 504 with descriptive message

### Test Implementation Notes

**Test file:** `apps/web-platform/test/github-api-retry.test.ts` (new file)

**Pattern:** Follow the `service-tools.test.ts` pattern -- mock `globalThis.fetch` directly, test the retry wrapper in isolation:

```typescript
import { describe, test, expect, vi, afterEach } from "vitest";

// Mock fetch helpers matching service-tools.test.ts pattern
function mockFetchTimeout() {
  return vi.fn().mockRejectedValue(
    new DOMException("signal timed out", "TimeoutError"),
  );
}

function mockFetchConnectTimeout() {
  const err = new Error("connect ETIMEDOUT");
  (err as { code: string }).code = "UND_ERR_CONNECT_TIMEOUT";
  return vi.fn().mockRejectedValue(err);
}

function mockFetchSequence(...responses: Array<() => Promise<Response>>) {
  const fn = vi.fn();
  responses.forEach((r, i) => fn.mockImplementationOnce(r));
  return fn;
}
```

**Existing test impact:** The `kb-upload.test.ts` mocks `@/server/github-api` entirely, so the retry logic is transparent to those tests. No existing tests need modification.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling bug fix to existing upload API.

## Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/server/github-api.ts` | Add `GITHUB_FETCH_TIMEOUT_MS`, `MAX_RETRIES`, `BASE_DELAY_MS` constants. Add `fetchWithRetry`, `isRetryable`, `delay` helpers. Replace bare `fetch` calls in `githubApiGet`, `githubApiGetText`, `githubApiPost` with `fetchWithRetry`. |
| `apps/web-platform/server/github-app.ts` | Add `AbortSignal.timeout(15_000)` to the `githubFetch` helper function (line 194). |
| `apps/web-platform/app/api/kb/upload/route.ts` | Add timeout/network error checks (both DOMException and undici error code) in the catch block to return 504 with `GITHUB_TIMEOUT` code. |
| `apps/web-platform/test/github-api-retry.test.ts` | New test file for `fetchWithRetry` unit tests covering: success, retry on timeout, retry on 5xx, no retry on 4xx, max retries exhausted, exponential backoff. |

## References

- Sentry error ID: `257bcd0e7edf435795e46c42c77639a5`
- PR #2130: agent identity badges and team icon customization (introduced the upload usage)
- PR #2134: middleware body clone limit fix (separate issue, already merged)
- Existing pattern: `apps/web-platform/server/service-tools.ts:49` (`AbortSignal.timeout`)
- Existing test pattern: `apps/web-platform/test/service-tools.test.ts` (fetch mock + timeout test)
- Existing test pattern: `apps/web-platform/test/kb-upload.test.ts` (upload route handler tests)
- Learning: `knowledge-base/project/learnings/2026-04-13-kb-upload-api-formdata-field-name-contract.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-review-gate-promise-leak-abort-timeout.md` (AbortSignal patterns)
- Context7 undici docs: `UND_ERR_CONNECT_TIMEOUT` error code, `RetryAgent` defaults, `autoSelectFamily` option
- [Undici retry interceptor defaults](https://github.com/nodejs/undici/blob/main/docs/docs/api/RetryAgent.md): `statusCodes: [429, 500, 502, 503, 504]`, `errorCodes: ['ECONNRESET', 'ECONNREFUSED', 'ENOTFOUND', 'ENETDOWN', 'EHOSTDOWN', 'UND_ERR_SOCKET']`
