/**
 * Runtime auth/data-access typed error classes for PR-B §1.6 / §1.7.
 *
 * Four distinct domains, each with a `cause` discriminant. The split
 * follows type-design F4 — auth, BYOK, data-access, and audit-write
 * have different client-facing routing, different Sentry tagging, and
 * different remediation paths. Conflating them recreates the
 * silent-failure class the plan exists to prevent.
 *
 *   - `RuntimeAuthError`   — JWT mint / rotation / denied-jti
 *     (defined in `lib/supabase/tenant.ts` so it lives next to the
 *     mint path that throws it; re-exported here for the mapper)
 *   - `ByokLeaseError`     — fetch / decrypt / scope-escape
 *     (defined in `server/byok-lease.ts` for the same reason)
 *   - `RlsDenyError`       — explicit RLS deny / 42501 / PGRST301
 *     (defined here — multiple call sites need to throw it)
 *   - `AuditWriteError`    — failed audit-row insert (integrity-domain,
 *     `reportSilentFallback`-mirrored, no user-facing degradation)
 *
 * Mapper (`mapRuntimeError`) lives in `error-messages.ts`.
 */

/**
 * Thrown when a data-access call hits an explicit RLS deny (Postgres
 * error code 42501 or PostgREST `PGRST301`). NOT thrown on silent
 * RLS filter (the empty-rowset case) — that's expected behavior, and
 * the probe in §1.5.8 distinguishes the two via prior auth-state check.
 */
export class RlsDenyError extends Error {
  public readonly cause: "explicit_deny" | "auth_probe_fail";

  constructor(cause: "explicit_deny" | "auth_probe_fail", message: string) {
    super(message);
    this.name = "RlsDenyError";
    this.cause = cause;
  }
}

/**
 * Integrity-domain error: an audit-row insert failed. NOT a session-
 * blocking error — `reportSilentFallback`-mirrored to Sentry; the
 * caller continues. Failed audit is an operations problem, not a
 * session problem (per type-design F4).
 */
export class AuditWriteError extends Error {
  public readonly table:
    | "audit_byok_use"
    | "audit_log"
    | "denied_jti"
    | "mint_rate_window";

  constructor(
    table:
      | "audit_byok_use"
      | "audit_log"
      | "denied_jti"
      | "mint_rate_window",
    message: string,
  ) {
    super(message);
    this.name = "AuditWriteError";
    this.table = table;
  }
}
