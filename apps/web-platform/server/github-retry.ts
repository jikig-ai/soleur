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
