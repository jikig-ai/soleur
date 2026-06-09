// ---------------------------------------------------------------------------
// Supabase-Storage transient-retry primitives (leaf, like ./github-retry).
// Single consumer today (workspace-logo upload); leaf shape so future Storage
// call sites share one classification without an import cycle.
//
// Dependency-free (no imports from sibling server modules; structural typing
// instead of storage-js types).
//
// storage-js (2.x) file-API methods are RESULT-RETURNING: API errors AND
// network-level failures come back as { data, error } (StorageApiError carries
// a numeric `status`; StorageUnknownError — the network wrap rejected by the
// SDK's `handleError` path — has no status) — so the retry classifies the
// RETURNED error, never a caught exception. Non-StorageError throws
// (programming errors) propagate unchanged.
//
// Scope: the STORAGE namespace only. The vectors namespace emits
// "StorageVectorsUnknownError", which this classifier deliberately does not
// match — widen the name check if a vector-bucket caller ever adopts this.
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
  // Network-level wrap — always worth retrying.
  if (error.name === "StorageUnknownError") return true;
  // StorageApiError: HTTP status. 5xx + 429 are transient; 4xx are not.
  return typeof error.status === "number" && (error.status >= 500 || error.status === 429);
}

/**
 * Retry a result-returning Storage operation on transient errors with bounded
 * plain-exponential backoff (base * 2^attempt). The op MUST be a closure that
 * re-invokes the storage call — passing a captured promise retries nothing.
 *
 * Precondition: the op must be IDEMPOTENT (e.g. deterministic key + upsert).
 * A StorageUnknownError can wrap a 2xx-with-unparseable-body, so a retry may
 * re-run an op that already wrote — only safe when re-running converges.
 *
 * No jitter: callers are user-initiated, per-user rate-limited, and
 * uncorrelated, so lockstep re-bursts can't form (unlike tenant.ts's CI-burst
 * case). Revisit if a fan-out/batch caller adopts this.
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
    try {
      opts.onRetry?.(attempt + 1, result.error);
    } catch {
      // onRetry is diagnostic-only — a throwing observer must not abort the
      // remaining retries or convert a recoverable transient into a 500.
    }
    await sleep(baseDelayMs * 2 ** attempt);
    result = await op();
  }
  return result;
}
