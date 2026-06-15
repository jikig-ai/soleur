/**
 * GoTrue rate-limit retry helper for the opt-in integration suites.
 *
 * The tenant-integration / workspace-fixture suites mass-create, sign in,
 * and delete synthetic GoTrue users. Run as a batch (or against the SHARED
 * dev project, which the README explicitly warns against for behavioral
 * suites), they trip GoTrue's per-IP/per-email rate limits and the opaque
 * 500-class "Database error deleting user" transient. That made the suite
 * non-deterministic — identical runs failed 7 vs 16 tests purely on
 * rate-limit timing, NOT on any code regression.
 *
 * `isRetryableGoTrueError` is the grounded predicate (auth-js@2.99.2:
 * `AuthError`/`AuthApiError` expose `.status` + `.code`); `withGoTrueRetry`
 * is a bounded exponential-backoff-with-jitter wrapper around any
 * supabase-js auth call that returns the `{ data, error }` shape (it also
 * tolerates auth-js paths that THROW the error). Non-rate-limit errors are
 * returned/rethrown immediately — the wrapper never masks a real failure,
 * which is the exact regression class tenant-integration exists to catch.
 *
 * The wrapper takes an injectable `sleep` so the unit test
 * (`gotrue-retry.test.ts`) runs with zero real elapsed time. Defaults keep
 * the worst-case cumulative wait well under the suites' 20-60s hookTimeout.
 */

export interface GoTrueErrorLike {
  status?: number;
  code?: string;
  message?: string;
}

const RATE_LIMIT_MESSAGE_RE = /rate limit|too many requests/i;
// Opaque 500-class transient GoTrue returns when a concurrent/locked
// auth.users DELETE briefly fails; safe to retry (the FK-reverse cascade
// is idempotent).
const TRANSIENT_DELETE_RE = /database error deleting user/i;
// over_request_rate_limit, over_email_send_rate_limit, over_sms_send_rate_limit, …
const OVER_RATE_LIMIT_CODE_RE = /^over_[a-z_]*rate_limit$/;

/**
 * True when `error` is a transient GoTrue condition worth retrying.
 * Returns false for null/undefined (the success path) and for genuine
 * client errors (422 user_already_exists, 400 invalid-login, …).
 */
export function isRetryableGoTrueError(
  error: GoTrueErrorLike | null | undefined,
): boolean {
  if (!error) return false;
  if (error.status === 429) return true;
  if (typeof error.code === "string" && OVER_RATE_LIMIT_CODE_RE.test(error.code))
    return true;
  const msg = error.message ?? "";
  if (RATE_LIMIT_MESSAGE_RE.test(msg)) return true;
  if (TRANSIENT_DELETE_RE.test(msg)) return true;
  return false;
}

export interface WithGoTrueRetryOpts {
  /** Max total attempts (including the first). Default 5. */
  maxAttempts?: number;
  /** Base backoff in ms; doubles per attempt, capped at 4000ms. Default 250. */
  baseDelayMs?: number;
  /** Injectable sleep (unit tests pass a no-op). Default real setTimeout. */
  sleep?: (ms: number) => Promise<void>;
  /** Injectable jitter in [0,1); defaults to Math.random. */
  jitter?: () => number;
}

function backoffMs(attempt: number, base: number, jitter: number): number {
  const exp = Math.min(4000, base * 2 ** (attempt - 1));
  return Math.round(exp + jitter * base);
}

/**
 * Wrap a supabase-js auth call (returns `{ data, error }`) with bounded
 * retry on rate-limit / transient errors. Returns the final result (which
 * may still carry a non-retryable or attempts-exhausted error — the caller
 * keeps its existing error handling). Rethrows a thrown error that is not
 * retryable, or that persists past `maxAttempts`.
 */
export async function withGoTrueRetry<
  T extends { error: GoTrueErrorLike | null },
>(label: string, fn: () => Promise<T>, opts: WithGoTrueRetryOpts = {}): Promise<T> {
  const maxAttempts = opts.maxAttempts ?? 5;
  const baseDelayMs = opts.baseDelayMs ?? 250;
  const sleep =
    opts.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  const jitter = opts.jitter ?? Math.random;

  let lastResult: T | undefined;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    let result: T;
    try {
      result = await fn();
    } catch (thrown) {
      if (
        isRetryableGoTrueError(thrown as GoTrueErrorLike) &&
        attempt < maxAttempts
      ) {
        await sleep(backoffMs(attempt, baseDelayMs, jitter()));
        continue;
      }
      throw thrown;
    }
    if (!isRetryableGoTrueError(result.error) || attempt === maxAttempts) {
      return result;
    }
    lastResult = result;
    // eslint-disable-next-line no-console
    console.warn(
      `withGoTrueRetry[${label}]: retryable error on attempt ${attempt}/${maxAttempts} ` +
        `(code=${result.error?.code ?? "?"} status=${result.error?.status ?? "?"})`,
    );
    await sleep(backoffMs(attempt, baseDelayMs, jitter()));
  }
  // Unreachable in practice (the attempt === maxAttempts branch returns),
  // but satisfies the type checker.
  return lastResult as T;
}
