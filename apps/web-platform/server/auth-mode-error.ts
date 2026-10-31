// Dependency-free leaf (no imports) so the lease, the binding resolver and the auto-sync trigger can share one
// error class and one reason classification without any of them pulling another's module graph. The closed reason
// set is the only text a caller may log or tag: never a row, a message from the database, or an id.

/** Reasons the conversation auth-mode resolver itself can throw. */
export const AUTH_MODE_ERROR_REASONS = ["unbound", "read_failed", "workspace_mismatch"] as const;
export type AuthModeErrorReason = (typeof AUTH_MODE_ERROR_REASONS)[number];

/** Every closed reason an unresolved auth mode can carry: the resolver's plus the ones the lease itself adds. */
export type AuthModeUnresolvedReason = AuthModeErrorReason | "no_resolver" | "resolver_failed" | "invalid_value";

/**
 * The reasons worth retrying: a read that failed for an infrastructure reason. EVERY other reason, including any
 * added later, is deterministic and is not auto-retried (fail-safe default).
 */
export const TRANSIENT_AUTH_MODE_REASONS: readonly string[] = ["read_failed", "resolver_failed"];

/** The lease-facing mode resolver. The optional argument is passed ONLY by the cross-owner pre-check (#11594). */
export type AuthModeResolverFn = (ctx?: { expectedWorkspaceId?: string }) => Promise<string>;

export type AuthModeUnresolvedCause = "auth_mode_unresolved" | "auth_mode_unavailable";

/** The lease cause for a closed reason: transient reasons are `auth_mode_unavailable`, everything else `auth_mode_unresolved`. */
export function classifyAuthModeReason(reason: string): AuthModeUnresolvedCause {
  return TRANSIENT_AUTH_MODE_REASONS.includes(reason) ? "auth_mode_unavailable" : "auth_mode_unresolved";
}

/** Thrown by the conversation auth-mode resolver; matched by `instanceof`, never by name. */
export class ConversationAuthModeError extends Error {
  public readonly reason: AuthModeErrorReason;

  constructor(reason: AuthModeErrorReason) {
    super(`conversation auth mode unresolved: ${reason}`);
    this.name = "ConversationAuthModeError";
    this.reason = reason;
  }
}
