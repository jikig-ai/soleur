/**
 * Typed classification of an `AbortController.signal.reason` value for
 * the for-await abort branch in `agent-runner.ts:startAgentSession`.
 *
 * Background (feat-abort-conversation-web PR1, plan §1.9): the registry
 * fires `controller.abort(new SessionAbortError(kind))`. The custom
 * Error subclass carries the kind on a typed property so the for-await
 * branch can switch on it without parsing the Error message — string
 * `.includes()` against the `Session aborted: ...` text is a substring
 * oracle (any future kind whose name is a suffix of an existing one,
 * or any wrapped error rethrown through a logger that retains the
 * substring, would silently misroute). The class-based approach pins
 * the kind at construction time and survives any rethrow that
 * preserves identity.
 *
 * Backwards-compat: `classifyAbortReason` also accepts plain Errors
 * whose message starts with `Session aborted: <kind>` so a legacy
 * caller (or a third-party `controller.abort(new Error(...))` call
 * landed before this PR) still classifies correctly. The plain-Error
 * path is matched against the canonical `Session aborted: <kind>`
 * prefix with the colon-space delimiter — no proper-substring match.
 */

export type AbortKind =
  | "disconnected"
  | "superseded"
  | "user_requested_stop"
  | "account_deleted"
  | "server_shutdown";

const ABORT_KINDS: ReadonlySet<AbortKind> = new Set([
  "disconnected",
  "superseded",
  "user_requested_stop",
  "account_deleted",
  "server_shutdown",
]);

/** Custom Error subclass carrying a typed `kind` discriminator. The
 *  registry constructs one of these on every `controller.abort(...)`.
 *  Subclassing Error preserves stack-trace ergonomics for Sentry while
 *  giving the for-await branch a property-based switch surface. */
export class SessionAbortError extends Error {
  readonly kind: AbortKind;
  constructor(kind: AbortKind) {
    super(`Session aborted: ${kind}`);
    this.name = "SessionAbortError";
    this.kind = kind;
  }
}

export interface AbortReasonClassification {
  /** Discriminated kind. `"unknown"` covers any non-Error reason or a
   *  legacy Error with an unrecognized message — the abort branch
   *  treats it as a non-user disconnect (today's pre-PR1 behavior). */
  kind: AbortKind | "unknown";
  /** Convenience: `kind === "user_requested_stop"`. Kept for callers
   *  that only need to gate on the user-Stop terminus. */
  isUserRequested: boolean;
  /** Convenience: `kind === "superseded"`. Kept for parity with the
   *  prior inline `err.message.includes("superseded")` check the
   *  abort branch used; folded into the classifier so there is one
   *  decoding site. */
  isSuperseded: boolean;
}

function buildResult(kind: AbortKind | "unknown"): AbortReasonClassification {
  return {
    kind,
    isUserRequested: kind === "user_requested_stop",
    isSuperseded: kind === "superseded",
  };
}

/** Classify an `AbortController.signal.reason` value. Tolerant of
 *  non-Error and legacy-Error inputs; the unknown branch is the
 *  conservative default (treat as non-user disconnect). */
export function classifyAbortReason(reason: unknown): AbortReasonClassification {
  if (reason instanceof SessionAbortError) {
    return buildResult(reason.kind);
  }
  if (reason instanceof Error) {
    // Legacy / third-party path. The Error.message must START with
    // the canonical `Session aborted: <kind>` prefix — substring
    // anywhere does not qualify. This blocks the future-suffix
    // misroute (`user_requested_stop_by_admin`) the original
    // `.includes()` form was vulnerable to.
    const prefix = "Session aborted: ";
    if (reason.message.startsWith(prefix)) {
      const rest = reason.message.slice(prefix.length);
      // The kind is the leading token up to a space, end-of-string,
      // or a punctuation boundary. We accept exactly the known kinds
      // and reject everything else.
      const kindToken = rest.split(/[^a-z_]/, 1)[0] as AbortKind;
      if (ABORT_KINDS.has(kindToken)) {
        return buildResult(kindToken);
      }
    }
  }
  return buildResult("unknown");
}
