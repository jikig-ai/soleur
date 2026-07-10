// Build the `request.jwt.claims` JSON that a Supabase authenticated request
// carries at the DB layer. RLS keys on `auth.uid()` = the `sub` claim; the
// prod JWT hook (mig 060) additionally injects `app_metadata.current_organization_id`.
// The attacker dimension is `sub` (a user who is NOT a member of the target
// workspace) — NOT the org/workspace claim, which no RLS policy reads.

export interface AuthenticatedClaims {
  /** The user id — becomes auth.uid(). The load-bearing attacker dimension. */
  sub: string;
  /** Mirrors the prod hook (mig 060). Present for shape-parity; not read by RLS. */
  organizationId?: string;
  /** JWT id — read by is_jti_denied_from_jwt() (mig 068) for the revoked-jti dimension. */
  jti?: string;
}

/** Serialize claims to the exact JSON shape `set_config('request.jwt.claims', …)` expects. */
export function buildAuthenticatedClaims(c: AuthenticatedClaims): string {
  const claims: Record<string, unknown> = {
    sub: c.sub,
    role: "authenticated",
  };
  if (c.jti !== undefined) claims.jti = c.jti;
  if (c.organizationId !== undefined) {
    claims.app_metadata = { current_organization_id: c.organizationId };
  }
  return JSON.stringify(claims);
}

/** The anon (unauthenticated) claim shape — role only, no sub. */
export function buildAnonClaims(): string {
  return JSON.stringify({ role: "anon" });
}
