// Dependency-free leaf (no imports) so the lease and the binding resolver can share one error class
// without either pulling the other's module graph. The closed reason set is the only text a
// caller may log or tag: never a row, a message from the database, or an id.

export const AUTH_MODE_ERROR_REASONS = ["unbound", "read_failed"] as const;
export type AuthModeErrorReason = (typeof AUTH_MODE_ERROR_REASONS)[number];

/** Thrown by the conversation auth-mode resolver; matched by `instanceof`, never by name. */
export class ConversationAuthModeError extends Error {
  public readonly reason: AuthModeErrorReason;

  constructor(reason: AuthModeErrorReason) {
    super(`conversation auth mode unresolved: ${reason}`);
    this.name = "ConversationAuthModeError";
    this.reason = reason;
  }
}
