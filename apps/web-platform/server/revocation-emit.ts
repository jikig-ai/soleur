// Shared revocation-notice emit helper (#4440 follow-up review).
//
// Three runner-surface catch sites (cc-dispatcher, agent-runner,
// soleur-go-runner) all collapse the same pattern after observing a
// `RuntimeAuthError` with `cause === "denied_jti"`:
//
//   1. Best-effort tenant-RPC lookup of the operator-supplied reason via
//      `getMyRevocationStatus(userId)` (fail-open: null when the lookup
//      itself fails — already Sentry-mirrored inside the helper).
//   2. Emit a discriminated `revocation_notice` frame so the client
//      replaces the generic "Something went wrong" with the operator
//      message, paired with whatever terminal envelope the caller's
//      transport requires (cc-dispatcher follows with `session_ended`,
//      soleur-go-runner with `WorkflowEnd{status:"session_revoked"}`).
//
// Centralizing the lookup + sanitization keeps the three sites byte-for-
// byte aligned and gives the prompt-injection / log-injection
// sanitization a single chokepoint (review FIX 8).
//
// `sendFrame` is the per-site frame-emit callback (sendToClient for the
// WS path; a runner-specific emit for the SDK-iterator path). The helper
// returns the looked-up status (or null) so the caller can decide the
// downstream envelope shape WITHOUT re-issuing the RPC.

import { getMyRevocationStatus, type MyRevocationStatus } from "@/lib/supabase/tenant";
import { reportSilentFallback } from "./observability";

/**
 * Sanitize an operator-supplied `denied_jti.reason` value before it
 * crosses the agent-prompt / WS-frame boundary.
 *
 * The operator IS trusted at write time (service-role-only revoke_jti
 * RPC) but the value flows downstream into:
 *
 *   - agent prompt context via the `auth_revocation_status` MCP tool
 *     (prompt-injection surface — strip control chars + cap length so a
 *     pathological reason can't smuggle directives into the model),
 *   - WS frames and pino logs (control-char log-injection surface —
 *     `\x1b` ANSI sequences and `\n`-embedded structured-log smuggling).
 *
 * Cheap defense-in-depth: strip ASCII control chars (0x00–0x1f plus
 * 0x7f) and Unicode line separators (U+2028 / U+2029, which JSON
 * accepts but Node's stream parsers and downstream terminal renderers
 * mishandle), then truncate at 256 chars with an ellipsis suffix.
 */
export function sanitizeReason(
  reason: string | null | undefined,
): string | null {
  if (reason === null || reason === undefined) return null;
  if (typeof reason !== "string") return null;
  // Strip ASCII control + DEL, plus U+2028 / U+2029 line separators.
  // Per cq-regex-unicode-separators-escape-only the separators are
  // expressed as `\u2028` / `\u2029` escape sequences rather than raw
  // chars (raw chars confuse the TS parser inside a character class).
  // eslint-disable-next-line no-control-regex -- intentional control-char sanitizer
  const stripped = reason.replace(/[\x00-\x1f\x7f\u2028\u2029]/g, "");
  if (stripped.length === 0) return null;
  const MAX = 256;
  if (stripped.length > MAX) {
    // Truncate, leaving room for the single-char ellipsis.
    return stripped.slice(0, MAX - 1) + "…";
  }
  return stripped;
}

/** Minimal shape of the `revocation_notice` frame the WS-emit sites use. */
export interface RevocationNoticeFrame {
  type: "revocation_notice";
  reason: string | null;
  deniedAt: string | null;
}

/**
 * Fail-open lookup of the caller's revocation status with reason
 * sanitization applied. Returns null when the lookup itself throws.
 *
 * Shared between the WS-emit sites (cc-dispatcher, agent-runner — via
 * `tryEmitRevocationNotice`) and the runner-WorkflowEnd site
 * (soleur-go-runner.consumeStream catch) which embeds `reason` /
 * `deniedAt` directly into the `WorkflowEnd{status:"session_revoked"}`
 * payload instead of emitting a separate frame.
 *
 * `getMyRevocationStatus` already swallows RPC errors internally; this
 * try/catch covers a genuinely unexpected throw (network teardown
 * mid-await, the tenant-mint helper itself bombing) and Sentry-mirrors
 * via `reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry`.
 */
export async function lookupRevocationStatusSafe(
  userId: string,
): Promise<MyRevocationStatus | null> {
  let status: MyRevocationStatus | null = null;
  try {
    status = await getMyRevocationStatus(userId);
  } catch (lookupErr) {
    reportSilentFallback(lookupErr, {
      feature: "revocation-emit",
      op: "lookupRevocationStatusSafe",
      extra: { userId },
    });
    return null;
  }
  if (!status) return null;
  return {
    revoked: status.revoked,
    deniedAt: status.deniedAt,
    reason: sanitizeReason(status.reason),
  };
}

/**
 * Look up the caller's revocation status and emit a discriminated
 * `revocation_notice` frame via the supplied `sendFrame` callback.
 *
 * Returns the looked-up status so the caller can branch its terminal
 * envelope (e.g. cc-dispatcher's follow-up `session_ended` frame)
 * without re-issuing the RPC.
 *
 * Fail-open: if `getMyRevocationStatus` throws the helper
 * Sentry-mirrors and returns null. The caller's surrounding catch must
 * still emit its own terminal frame — the helper only handles the
 * `revocation_notice` half.
 */
export async function tryEmitRevocationNotice(
  userId: string,
  sendFrame: (frame: RevocationNoticeFrame) => void,
): Promise<MyRevocationStatus | null> {
  const status = await lookupRevocationStatusSafe(userId);
  try {
    sendFrame({
      type: "revocation_notice",
      reason: status?.reason ?? null,
      deniedAt: status?.deniedAt ?? null,
    });
  } catch (emitErr) {
    // Same fail-open posture — a WS socket already torn down or a
    // runner-specific emit that rejects must not stomp the
    // surrounding catch's terminal-frame emit.
    reportSilentFallback(emitErr, {
      feature: "revocation-emit",
      op: "tryEmitRevocationNotice.emit",
      extra: { userId },
    });
  }
  return status;
}
