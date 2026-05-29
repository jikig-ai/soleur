export const DEFAULT_ERROR_MESSAGE = "Something went wrong. Please try again.";

export const CALLBACK_ERRORS: Record<string, string> = {
  auth_failed:
    "Sign-in failed. If you have an existing account, try signing in with email instead.",
  code_verifier_missing: "Session expired. Please try signing in again.",
  provider_disabled:
    "This sign-in provider is not enabled. Please use a different method.",
  oauth_cancelled:
    "Sign-in cancelled. Click your sign-in option to try again.",
  oauth_failed:
    "The sign-in service had a temporary problem. Please try again.",
};

export const NO_ACCOUNT_PATTERN = /signups? not allowed for otp/i;

export const SIGNUP_REASON_NO_ACCOUNT = "no_account";

// Shared copy constant: referenced both by the freetext regex table (for the
// legacy `token … expired` message) and the structured `otp_expired` code path.
export const EXPIRED_CODE_MESSAGE =
  "Your sign-in code has expired. Please request a new one.";

// Per-request token-verification ceiling (GoTrue `over_request_rate_limit` /
// HTTP 429). Intentionally distinct from the email-SEND rate-limit copy below —
// a different limit with a different recovery (wait, do not request a new code).
export const RATE_LIMIT_MESSAGE =
  "Too many attempts right now. Please wait a minute and try again.";

// GoTrue 5xx, incl. a raising Custom Access Token Hook and
// AuthRetryableFetchError (status 503).
export const TEMPORARILY_UNAVAILABLE_MESSAGE =
  "Sign-in is temporarily unavailable. Please try again in a moment.";

// Transport failure: a status-less throw (bare TypeError / fetch reject, or an
// AuthRetryableFetchError that surfaced without a status).
export const CONNECTION_FAILURE_MESSAGE =
  "Couldn't reach the sign-in service. Check your connection and try again.";

// Email-SEND ceiling copy (freetext `email rate limit exceeded`). Exported so
// the divergence guard in the test suite can reference it by name rather than
// hard-coding the literal (which would silently desync on a copy edit).
export const EMAIL_SEND_RATE_LIMIT_MESSAGE =
  "Too many sign-in attempts. Please wait a few minutes and try again.";

/**
 * Structural shape of a Supabase `AuthError` (or a transport throw — a bare
 * `TypeError` / fetch reject that is NOT an `AuthError`). Read-only inspection:
 * `code`/`status` are enums/ints (no PII); `message` is only consulted by the
 * freetext fallback and is never forwarded to Sentry's `extra`. Canonical home
 * for the shape consumed by {@link mapSupabaseAuthError} and the auth call
 * sites (login-form, signup, oauth-buttons).
 */
export type AuthErrorLike = {
  code?: string;
  status?: number;
  name?: string;
  message?: string;
};

const SUPABASE_ERROR_PATTERNS: [RegExp, string][] = [
  [
    NO_ACCOUNT_PATTERN,
    "No Soleur account found for this email. Sign up instead.",
  ],
  [/email rate limit exceeded/i, EMAIL_SEND_RATE_LIMIT_MESSAGE],
  [
    /invalid otp/i,
    "That code is incorrect or has expired. Please request a new one.",
  ],
  [/token.*expired/i, EXPIRED_CODE_MESSAGE],
];

function mapFreetextMessage(message: string): string {
  for (const [pattern, friendly] of SUPABASE_ERROR_PATTERNS) {
    if (pattern.test(message)) return friendly;
  }
  return DEFAULT_ERROR_MESSAGE;
}

/**
 * Back-compat shim: maps a raw GoTrue error *message* to friendly copy via the
 * freetext regex table. Prefer {@link mapSupabaseAuthError} for any call site
 * that holds the structured `AuthError` object — `error.message` is version-
 * unstable and embeds the email on OTP errors.
 */
export function mapSupabaseError(message: string): string {
  return mapFreetextMessage(message);
}

/**
 * Maps a Supabase `AuthError` (or any `{ code?, status?, name?, message? }`
 * shape) to friendly, recoverable copy. Inspects the structured `code`/`status`
 * fields FIRST (version-stable, no PII), then falls back to the freetext regex
 * table for back-compat. Mirrors the code-first discrimination precedent in
 * `lib/supabase/tenant.ts` (`over_request_rate_limit`).
 *
 * Returns recoverable copy for the operationally-likely failures that the
 * freetext-only mapper dead-ended into the generic message: per-request rate
 * limit (429), expired code, server 5xx (incl. a raising Custom Access Token
 * Hook), and transport failures.
 */
export function mapSupabaseAuthError(
  error: AuthErrorLike | null | undefined,
): string {
  if (!error) return DEFAULT_ERROR_MESSAGE;

  const { code, status, name, message } = error;

  // Code-first: structured, version-stable, never PII.
  if (code === "over_request_rate_limit") return RATE_LIMIT_MESSAGE;
  if (code === "otp_expired") return EXPIRED_CODE_MESSAGE;

  // Status-based: 429 = rate limit; 5xx = server/hook failure (incl. 503
  // AuthRetryableFetchError when it surfaces with a status).
  if (status === 429) return RATE_LIMIT_MESSAGE;
  if (typeof status === "number" && status >= 500) {
    return TEMPORARILY_UNAVAILABLE_MESSAGE;
  }

  // Transport throw with no status: bare TypeError (fetch reject) or a
  // status-less AuthRetryableFetchError.
  if (
    status === undefined &&
    (name === "AuthRetryableFetchError" || name === "TypeError")
  ) {
    return CONNECTION_FAILURE_MESSAGE;
  }

  // Back-compat: fall through to the freetext regex table.
  return mapFreetextMessage(message ?? "");
}

export function isNoAccountError(error: {
  code?: string;
  message: string;
}): boolean {
  if (error.code === "otp_disabled") return true;
  return NO_ACCOUNT_PATTERN.test(error.message);
}
