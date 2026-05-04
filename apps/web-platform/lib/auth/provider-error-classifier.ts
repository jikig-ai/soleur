/**
 * Maps the OAuth 2.0 `error` query parameter (forwarded verbatim by Supabase
 * from the upstream provider) to the coarse code rendered on /login?error=.
 *
 * Discriminator is `URLSearchParams.get("error")` — case-sensitive, exact
 * match. Do NOT normalize with `.toLowerCase()`, do NOT split on `[`, and do
 * NOT use substring matching: the `error` enum is closed (RFC 6749 §4.1.2.1
 * + OIDC §3.1.2.6) and substring matchers drift across provider versions.
 *
 * Return-value semantics:
 * - `null` — no `error` query param (or empty value). Caller falls through.
 * - `"oauth_cancelled"` — user clicked Cancel at the provider consent screen.
 * - `"oauth_failed"` — provider-side server-class failure OR an `error` value
 *   that is not in the closed table (defensive default — never silently
 *   fall through to the misleading `auth_failed` "try email instead" copy).
 */

export type ProviderErrorBucket = "oauth_cancelled" | "oauth_failed";

const PROVIDER_ERROR_TABLE: Record<string, ProviderErrorBucket> = {
  access_denied: "oauth_cancelled",

  // Provider-side server-class failures. Map all of these to the same
  // user-facing copy ("temporary problem, try again") because the recovery
  // action is identical.
  server_error: "oauth_failed",
  temporarily_unavailable: "oauth_failed",
  invalid_request: "oauth_failed",
  invalid_scope: "oauth_failed",
  unauthorized_client: "oauth_failed",
  unsupported_response_type: "oauth_failed",
};

export function classifyProviderError(
  searchParams: URLSearchParams,
): ProviderErrorBucket | null {
  const errorCode = searchParams.get("error");
  if (errorCode === null || errorCode === "") return null;

  // Object.hasOwn — prevents prototype-chain hits like `?error=toString`
  // or `?error=__proto__` from masquerading as table entries.
  if (Object.hasOwn(PROVIDER_ERROR_TABLE, errorCode)) {
    return PROVIDER_ERROR_TABLE[errorCode];
  }
  return "oauth_failed";
}

/**
 * True when `errorCode` is a known table key. Use at the call site to decide
 * whether the raw value is safe to forward to telemetry (Sentry tag
 * cardinality / log-injection discipline).
 */
export function isKnownProviderErrorCode(errorCode: string): boolean {
  return Object.hasOwn(PROVIDER_ERROR_TABLE, errorCode);
}
