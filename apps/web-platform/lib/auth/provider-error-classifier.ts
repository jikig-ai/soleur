/**
 * Maps the OAuth 2.0 `error` query parameter (forwarded verbatim by Supabase
 * from the upstream provider) to the coarse code rendered on /login?error=.
 *
 * Discriminator is `URLSearchParams.get("error")` — case-sensitive, exact
 * match. Do NOT normalize with `.toLowerCase()`, do NOT split on `[`, and do
 * NOT use substring matching: the `error` enum is closed (RFC 6749 §4.1.2.1
 * + OIDC §3.1.2.6) and substring matchers drift across provider versions.
 *
 * Source: Supabase forwards `error` + `error_description` to `redirect_to`
 * verbatim per `apps/docs/content/guides/auth/oauth-server/oauth-flows.mdx`
 * (user-deny path) and the `/v1/oauth/authorize` 302 example. The user-cancel
 * signal (`access_denied`) gets its own `oauth_cancelled` bucket so the
 * /login copy can distinguish "I changed my mind" from "the system broke".
 */

const PROVIDER_ERROR_TABLE: Record<
  string,
  "oauth_cancelled" | "oauth_failed"
> = {
  // User clicked Cancel at the provider's consent screen.
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

export type ProviderErrorBucket = "oauth_cancelled" | "oauth_failed";

export function classifyProviderError(
  searchParams: URLSearchParams,
): ProviderErrorBucket | null {
  const errorCode = searchParams.get("error");
  if (errorCode === null || errorCode === "") return null;

  const bucket = PROVIDER_ERROR_TABLE[errorCode];
  if (bucket) return bucket;

  // Unknown but non-empty `error` value — the OAuth 2.0 spec disallows this,
  // but defensive default to `oauth_failed` so we never silently fall through
  // to the existing `auth_failed` copy with the misleading "try email
  // instead" hint.
  return "oauth_failed";
}
