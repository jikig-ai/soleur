/**
 * Maps a Supabase auth error to the coarse code rendered on /login?error=.
 *
 * Discriminator is the typed `error.code` field, NOT the drift-prone
 * `error.message` string. The five codes that map to `code_verifier_missing`
 * all have the same recovery action ("re-initiate the OAuth round-trip"),
 * so they share the user-facing copy in `lib/auth/error-messages.ts`.
 *
 * Source of truth: @supabase/auth-js error-codes.d.ts (installed v2.49.0).
 * Re-grep that file when bumping the dependency for new *_verifier / *_state
 * codes.
 */

const VERIFIER_CLASS_CODES = new Set<string>([
  "bad_code_verifier",
  "flow_state_not_found",
  "flow_state_expired",
  "bad_oauth_state",
  "bad_oauth_callback",
]);

export type CallbackErrorCode = "code_verifier_missing" | "auth_failed";

export function classifyCallbackError(err: unknown): CallbackErrorCode {
  if (typeof err !== "object" || err === null) return "auth_failed";
  const code = (err as { code?: unknown }).code;
  if (typeof code === "string" && VERIFIER_CLASS_CODES.has(code)) {
    return "code_verifier_missing";
  }
  return "auth_failed";
}
