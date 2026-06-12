// ---------------------------------------------------------------------------
// Shared GitHub-API transient-retry primitives
//
// Dependency-free leaf module so BOTH github-api.ts (fetchWithRetry) and
// github-app.ts (probeOrgMembership) reuse the SAME transient classification +
// backoff without a circular import. `isRetryable` lived in github-api.ts and
// github-app.ts already depends on github-api.ts for token minting, so importing
// isRetryable back into github-app.ts closed a cycle — extracting it here breaks
// that cycle (both modules now point DOWN to this leaf).
// ---------------------------------------------------------------------------

/**
 * Classify a thrown fetch error as transient (worth retrying). Covers the
 * AbortSignal.timeout DOMException and undici network-level error codes.
 */
export function isRetryable(err: unknown): boolean {
  // AbortSignal.timeout() fires a DOMException with name "TimeoutError"
  if (err instanceof DOMException && err.name === "TimeoutError") return true;
  // Network-level fetch failure (undici throws TypeError with "fetch failed")
  if (err instanceof TypeError && err.message === "fetch failed") return true;
  // Undici-specific error codes
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

export function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------------
// Shared transient-retry budget — single source of truth.
//
// 3 total attempts with exponential backoff (1 s, 2 s). Hoisted here so
// fetchWithRetry (github-api.ts), createProbeOctokit's 401 path, and
// withGithubRetry all share ONE budget definition.
// ---------------------------------------------------------------------------
export const MAX_RETRIES = 2; // 3 total attempts
export const BASE_DELAY_MS = 1_000;

/**
 * Cause-chain-aware transient classifier. octokit.request() wraps a connect
 * timeout in a RequestError (name "HttpError", status 500) whose `.cause` is
 * the raw `TypeError: fetch failed`, whose own `.cause` carries
 * `{ code: "UND_ERR_CONNECT_TIMEOUT" }`. Top-level `isRetryable` MISSES that
 * wrapper (not a TypeError, no top-level `.code`, a non-retryable-looking
 * status of 500). Walk the cause chain so the undici code / "fetch failed" is
 * found wherever octokit buried it. Bounded depth (5) guards against a
 * self-referential cause cycle.
 *
 * NOTE: do NOT add a "status >= 500" arm — octokit ALSO surfaces genuine
 * GitHub 5xx as RequestError with the real status, so a status-based arm would
 * over-retry real server errors. The cause-chain walk is precise: it retries
 * only when a real undici/timeout code (or "fetch failed" TypeError) is present
 * in the chain.
 */
export function isRetryableGithubError(err: unknown): boolean {
  let cur: unknown = err;
  for (let depth = 0; depth < 5 && cur != null; depth++) {
    if (isRetryable(cur)) return true;
    cur = (cur as { cause?: unknown }).cause;
  }
  return false;
}

/**
 * Run `fn`, retrying ONLY on transient network errors (isRetryableGithubError)
 * with exponential backoff (reuses the canonical MAX_RETRIES / BASE_DELAY_MS
 * budget). Non-retryable errors (4xx auth, shape, a genuine GitHub 5xx with no
 * transient cause) and the final attempt's error rethrow immediately. Wrap
 * octokit.request() calls in crons so a single api.github.com connect-timeout
 * does not escalate to Sentry.
 *
 * Logger-free by design: callers own observability via their existing catch +
 * reportSilentFallback. This preserves the leaf's no-dependency / no-cycle
 * property.
 */
export async function withGithubRetry<T>(fn: () => Promise<T>): Promise<T> {
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try {
      return await fn();
    } catch (err) {
      if (attempt < MAX_RETRIES && isRetryableGithubError(err)) {
        await delay(BASE_DELAY_MS * 2 ** attempt);
        continue;
      }
      throw err;
    }
  }
  // TypeScript exhaustiveness guard — loop always returns or rethrows above.
  throw new Error("withGithubRetry: unreachable");
}
