// ---------------------------------------------------------------------------
// Shared Supabase-Storage transient-retry primitives
//
// Dependency-free leaf module (the ./github-retry shape — no imports from
// sibling server modules; structural typing instead of storage-js types).
//
// storage-js (2.99.2) file-API methods are RESULT-RETURNING: API errors AND
// network-level failures come back as { data, error } (StorageApiError carries
// a numeric `status`; StorageUnknownError wraps fetch-level failures and has
// no status) — so the retry classifies the RETURNED error, never a caught
// exception. Non-StorageError throws (programming errors) propagate unchanged.
// ---------------------------------------------------------------------------

/** Structural shape of a returned storage-js error (no storage-js import). */
export interface StorageErrorLike {
  name?: string;
  message: string;
  status?: number;
}

const DEFAULT_MAX_RETRIES = 2; // 3 total attempts — mirrors github-api.ts
const DEFAULT_BASE_DELAY_MS = 500; // worst added latency: 500 + 1000 = 1.5 s

/**
 * Classify a RETURNED storage-js error as transient (worth retrying).
 * Network-level wraps (StorageUnknownError) and 5xx/429 API errors are
 * transient; 4xx and unknown shapes fail fast, preserving single-attempt
 * behavior for permanent errors.
 */
export function isRetryableStorageError(error: StorageErrorLike | null): boolean {
  if (!error) return false;
  // Network-level wrap (storage-js dist/index.mjs:282) — always worth retrying.
  if (error.name === "StorageUnknownError") return true;
  // StorageApiError: HTTP status. 5xx + 429 are transient; 4xx are not.
  return typeof error.status === "number" && (error.status >= 500 || error.status === 429);
}

/**
 * Retry a result-returning Storage operation on transient errors with bounded
 * plain-exponential backoff (base * 2^attempt). The op MUST be a closure that
 * re-invokes the storage call — passing a captured promise retries nothing.
 */
export async function withStorageRetry<R extends { error: StorageErrorLike | null }>(
  op: () => Promise<R>,
  opts: {
    maxRetries?: number;
    baseDelayMs?: number;
    sleep?: (ms: number) => Promise<void>;
    onRetry?: (attempt: number, error: StorageErrorLike) => void;
  } = {},
): Promise<R> {
  const maxRetries = opts.maxRetries ?? DEFAULT_MAX_RETRIES;
  const baseDelayMs = opts.baseDelayMs ?? DEFAULT_BASE_DELAY_MS;
  const sleep = opts.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  let result = await op();
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    if (!result.error || !isRetryableStorageError(result.error)) return result;
    opts.onRetry?.(attempt + 1, result.error);
    await sleep(baseDelayMs * 2 ** attempt);
    result = await op();
  }
  return result;
}
