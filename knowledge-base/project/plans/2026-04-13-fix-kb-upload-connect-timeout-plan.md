---
title: "fix: add timeout and retry to GitHub API fetch calls in kb/upload"
type: fix
date: 2026-04-13
---

# fix: Add timeout and retry to GitHub API fetch calls in kb/upload

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

The 10-second default is reasonable for most scenarios, but the upload route chains multiple GitHub API calls (token exchange + duplicate check + file upload), so a single transient timeout fails the entire operation.

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

Create a `fetchWithRetry` helper that retries on `ConnectTimeoutError`, `TypeError` (network error), and 5xx responses. Use exponential backoff (1s, 2s, 4s) with max 3 attempts. This is scoped to `github-api.ts` only -- not a global retry.

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
          { attempt: attempt + 1, err: lastError.message },
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
  if (err instanceof DOMException && err.name === "TimeoutError") return true;
  if (err instanceof TypeError) return true; // network error
  if (err instanceof Error && err.message.includes("ConnectTimeoutError")) return true;
  return false;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
```

#### 3. Add timeout to `github-app.ts` fetch calls

The `githubFetch` helper in `github-app.ts` (line 190-203) also lacks a timeout. Add the same `AbortSignal.timeout()` pattern. Since `github-app.ts` handles token exchange and installation lookup (lower volume, but still vulnerable), apply the same approach.

#### 4. Improve error handling in the upload route

The catch block in `route.ts` (line 285-310) checks for `error.message.includes("GitHub API")` but `ConnectTimeoutError` does not contain that string. Add a check for timeout/network errors to return a more descriptive 504 Gateway Timeout:

```typescript
if (error instanceof DOMException && error.name === "TimeoutError") {
  return NextResponse.json(
    { error: "GitHub API timed out. Please try again.", code: "GITHUB_TIMEOUT" },
    { status: 504 },
  );
}
```

## Technical Considerations

- **Architecture impact:** Minimal. Changes are scoped to the GitHub API fetch layer. All existing callers benefit from retry logic without changes.
- **Performance:** Worst case adds ~7 seconds (two retries with backoff) before failing. This is acceptable for an upload operation that already involves network round-trips.
- **Security:** No new attack surface. `AbortSignal.timeout()` is a standard Web API. Retry logic does not expose additional information.
- **Concurrency:** Retries are per-request, not queued. No risk of retry storms because upload is user-initiated (one at a time per user).

## Acceptance Criteria

- [ ] `githubApiGet`, `githubApiGetText`, and `githubApiPost` in `github-api.ts` include `AbortSignal.timeout(15_000)` on every fetch call
- [ ] A `fetchWithRetry` wrapper retries on `ConnectTimeoutError`, `TypeError`, `TimeoutError`, and 5xx responses with exponential backoff (max 3 attempts)
- [ ] `githubFetch` in `github-app.ts` includes `AbortSignal.timeout(15_000)` on every fetch call
- [ ] The upload route (`app/api/kb/upload/route.ts`) returns HTTP 504 with `{ code: "GITHUB_TIMEOUT" }` when GitHub API times out (after retries exhausted)
- [ ] Retry attempts are logged at `warn` level with attempt number and error message
- [ ] Existing tests pass without modification
- [ ] No changes to the client-side upload code (team-settings.tsx) -- the retry is server-side

## Test Scenarios

- Given a working GitHub API connection, when uploading a team icon, then the upload succeeds on the first attempt with no retry logging
- Given a transient connect timeout on the first attempt, when uploading a team icon, then the retry succeeds and the upload completes
- Given persistent connect timeouts (all 3 attempts), when uploading a team icon, then the route returns HTTP 504 with `code: "GITHUB_TIMEOUT"` and Sentry captures the error
- Given a GitHub 500 response on the first attempt, when making any GitHub API call, then the retry succeeds on the second attempt
- Given a GitHub 404 response (file not found during duplicate check), when uploading a new file, then no retry occurs (404 is not retryable) and upload proceeds normally
- Given a GitHub 403 response, when making any GitHub API call, then no retry occurs (permission errors are not transient)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling bug fix to existing upload API.

## Files to Modify

| File | Change |
|------|--------|
| `apps/web-platform/server/github-api.ts` | Add `GITHUB_FETCH_TIMEOUT_MS` constant, `fetchWithRetry` wrapper, `isRetryable` helper, `delay` helper. Replace bare `fetch` calls in `githubApiGet`, `githubApiGetText`, `githubApiPost` with `fetchWithRetry`. |
| `apps/web-platform/server/github-app.ts` | Add `AbortSignal.timeout(15_000)` to the `githubFetch` helper function. |
| `apps/web-platform/app/api/kb/upload/route.ts` | Add timeout/network error check in the catch block to return 504 with `GITHUB_TIMEOUT` code. |

## References

- Sentry error ID: `257bcd0e7edf435795e46c42c77639a5`
- PR #2130: agent identity badges and team icon customization (introduced the upload usage)
- PR #2134: middleware body clone limit fix (separate issue, already merged)
- Existing pattern: `apps/web-platform/server/service-tools.ts:49` (`AbortSignal.timeout`)
- Learning: `knowledge-base/project/learnings/2026-04-13-kb-upload-api-formdata-field-name-contract.md`
- Node.js undici docs: ConnectTimeoutError fires at 10s by default when TCP connection cannot be established
