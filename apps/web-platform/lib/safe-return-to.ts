/**
 * Same-origin relative paths a post-auth / post-setup redirect is allowed to
 * land on. Add a prefix here (not a new validator) when a new internal
 * destination needs to survive a redirect round-trip.
 *
 * - `/dashboard` — the original post-setup destination (connect-repo).
 * - `/invite/`   — workspace invite acceptance; an invited user signing in or
 *   signing up must be returned to `/invite/<token>` so they never have to
 *   re-request an OTP (the forced double-send that trips GoTrue's 60s per-user
 *   email rate limit — see the fix-invited-user-signin-otp-rate-limit plan).
 */
const ALLOWED_PREFIXES = ["/dashboard", "/invite/"] as const;

/**
 * Validates a redirect/return_to param to prevent open-redirect attacks.
 *
 * Returns the param iff it is a same-origin relative path under an allowed
 * prefix; otherwise `null` so each caller can pick its own fallback (login →
 * `/dashboard`, signup → `/accept-terms`).
 *
 * The reject guards (`//`, `\\`, `..` substrings + a leading `/` requirement)
 * are the verified precedent shape and are deliberately retained:
 * - an absolute URL (`https://evil`) fails `startsWith("/")`;
 * - a protocol-relative URL (`//evil`) fails `includes("//")`;
 * - a backslash bypass (`/\evil`) fails `includes("\\")`;
 * - path traversal (`/dashboard/../x`) fails `includes("..")`.
 */
export function safeReturnTo(param: string | null): string | null {
  if (!param) return null;
  if (
    !param.startsWith("/") ||
    param.includes("//") ||
    param.includes("\\") ||
    param.includes("..")
  ) {
    return null;
  }
  if (!ALLOWED_PREFIXES.some((prefix) => param.startsWith(prefix))) return null;
  return param;
}
