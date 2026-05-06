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

const SUPABASE_ERROR_PATTERNS: [RegExp, string][] = [
  [
    NO_ACCOUNT_PATTERN,
    "No Soleur account found for this email. Sign up instead.",
  ],
  [
    /email rate limit exceeded/i,
    "Too many sign-in attempts. Please wait a few minutes and try again.",
  ],
  [
    /invalid otp/i,
    "That code is incorrect or has expired. Please request a new one.",
  ],
  [
    /token.*expired/i,
    "Your sign-in code has expired. Please request a new one.",
  ],
];

export function mapSupabaseError(message: string): string {
  for (const [pattern, friendly] of SUPABASE_ERROR_PATTERNS) {
    if (pattern.test(message)) return friendly;
  }
  return DEFAULT_ERROR_MESSAGE;
}

export function isNoAccountError(error: {
  code?: string;
  message: string;
}): boolean {
  if (error.code === "otp_disabled") return true;
  return NO_ACCOUNT_PATTERN.test(error.message);
}

/**
 * Map a runtime auth/data-access typed error to a sanitized client
 * string (per `2026-03-20-websocket-error-sanitization-cwe-209`).
 *
 * Discriminates on `error.name` rather than `instanceof` to avoid the
 * lib→server import that would otherwise pull `byok-lease.ts` (and its
 * pino dependency) into client bundles via `cq-client-bundle-server-imports`.
 *
 * Names handled (per PR-B §1.6 / type-design F4):
 *   - "RuntimeAuthError"  → JWT mint / rotation / denied-jti
 *   - "ByokLeaseError"    → BYOK fetch / decrypt / scope-escape
 *   - "RlsDenyError"      → explicit data-access deny
 *   - "AuditWriteError"   → integrity-domain (no user degradation)
 *
 * Per `cq-union-widening-grep-three-patterns`: every new class must
 * land here in the same edit cycle. New names without a mapper entry
 * fall through to DEFAULT_ERROR_MESSAGE, which is operationally safe
 * but loses the typed routing — flag at code review.
 */
export function mapRuntimeError(err: unknown): string {
  if (!(err instanceof Error)) return DEFAULT_ERROR_MESSAGE;
  switch (err.name) {
    case "RuntimeAuthError":
    case "ByokLeaseError":
      return "Authentication unavailable; retry shortly.";
    case "RlsDenyError":
      return "Access denied.";
    case "AuditWriteError":
      // Integrity-domain. Not user-facing — Sentry mirror is the load-
      // bearing surface. Returning DEFAULT keeps the session alive.
      return DEFAULT_ERROR_MESSAGE;
    default:
      return DEFAULT_ERROR_MESSAGE;
  }
}
