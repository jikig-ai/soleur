/**
 * Boundary-level allowlist for WS message types.
 *
 * The client reducer is exhaustive over a TS discriminated union (see
 * `applyStreamEvent` in `chat-state-machine.ts`). At build time TS enforces
 * exhaustiveness; at runtime an unknown event simply does not match any
 * `case` and drops inertly. That's safe but invisible — a server/client
 * version skew produces no observable signal.
 *
 * This set + `isKnownWSMessageType` guard is the 3-line substitute for a full
 * zod schema at the `onmessage` site. The caller wraps the guard with
 * `reportSilentFallback` so we get a Sentry breadcrumb on skew.
 *
 * Keep in sync with `WSMessage` in `lib/types.ts` plus the close-preamble
 * types (`concurrency_cap_hit`, `tier_changed`) that are sent in-band.
 * See FR4 (#2861).
 */
export const KNOWN_WS_MESSAGE_TYPES: ReadonlySet<string> = new Set([
  // Auth + session lifecycle
  "auth",
  "auth_ok",
  "chat",
  "start_session",
  "resume_session",
  "close_conversation",
  "review_gate_response",
  "session_started",
  "session_resumed",
  "session_ended",
  // Stream lifecycle
  "stream",
  "stream_start",
  "stream_end",
  "tool_use",
  "tool_progress",
  "review_gate",
  // Usage + meta
  "usage_update",
  "fanout_truncated",
  "upgrade_pending",
  "error",
  // Close-preamble payloads (sent before ws.close(4010/4011))
  "concurrency_cap_hit",
  "tier_changed",
]);

export function isKnownWSMessageType(t: unknown): boolean {
  return typeof t === "string" && KNOWN_WS_MESSAGE_TYPES.has(t);
}
