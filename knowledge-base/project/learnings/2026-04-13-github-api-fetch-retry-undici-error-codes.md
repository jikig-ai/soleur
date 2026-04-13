# Learning: GitHub API fetch retry with undici error code detection

## Problem

The `POST /api/kb/upload` route failed in production with `ConnectTimeoutError` when `fetch` to `api.github.com:443` exceeded undici's default 10s connect timeout. The error (Sentry ID: `257bcd0e7edf435795e46c42c77639a5`) was unhandled because the error handler only checked `error.message.includes("GitHub API")`, which does not match undici's `ConnectTimeoutError`.

## Solution

Added a `fetchWithRetry` wrapper to `github-api.ts` with:

- `AbortSignal.timeout(15_000)` on every fetch call (fresh signal per attempt)
- Retry on transient errors with exponential backoff (1s, 2s, max 3 attempts)
- Response body drain on 5xx retry to prevent socket keep-alive issues
- Separate timeout-only (no retry) at the `github-app.ts` layer to avoid N*M retry explosion

The upload route returns HTTP 504 with `code: "GITHUB_TIMEOUT"` when timeouts persist after retries.

## Key Insight

Undici's `ConnectTimeoutError` uses `err.code === 'UND_ERR_CONNECT_TIMEOUT'`, not a string in `err.message`. The `isRetryable` check must use `err.code` (part of the API contract) not `err.message.includes()` (unstable across versions). Additionally, `TypeError` from `fetch` must be narrowed to `err.message === "fetch failed"` — bare `TypeError` matching would silently retry programmer errors like invalid arguments.

When two GitHub API layers exist (low-level token exchange and high-level route wrappers), place retry at the high level only. Adding retry at both layers causes multiplicative attempt counts.

## Tags

category: runtime-errors
module: apps/web-platform/server/github-api
