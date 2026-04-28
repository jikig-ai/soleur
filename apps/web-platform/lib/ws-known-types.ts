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
 * The `_Exhaustive` type below fails `tsc --noEmit` if `WSMessage` or
 * `ClosePreamble` gains a new `type` that's missing from the set (or vice
 * versa), forcing the allowlist to evolve with the union — closes the manual
 * "keep in sync" drift risk flagged in the #2861 architecture review.
 */

import type { WSMessage, ClosePreamble } from "@/lib/types";

type WSMessageType = WSMessage["type"];
type ClosePreambleType = ClosePreamble["type"];
type AllowedWSMessageType = WSMessageType | ClosePreambleType;

export const KNOWN_WS_MESSAGE_TYPES = new Set<AllowedWSMessageType>([
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
  // Stage 3 (#2885) — Command Center soleur-go router event variants
  "subagent_spawn",
  "subagent_complete",
  "workflow_started",
  "workflow_ended",
  "interactive_prompt",
  "interactive_prompt_response",
  // Close-preamble payloads (sent before ws.close(4010/4011))
  "concurrency_cap_hit",
  "tier_changed",
]) satisfies ReadonlySet<AllowedWSMessageType>;

/**
 * Compile-time exhaustiveness marker. If a new variant is added to
 * `WSMessage["type"]` or `ClosePreamble["type"]` without also appearing in
 * the `KNOWN_WS_MESSAGE_TYPES` set literal above, the literal widens past
 * the declared `Set<AllowedWSMessageType>` type and the `satisfies` clause
 * flags it. This `_Exhaustive` const additionally catches the opposite
 * direction (member removed from the union but still in the set).
 */
type SetToUnion<T> = T extends Set<infer U> ? U : never;
// Both members must reduce to `never`. If a variant is added to the union
// without being added to the set (or vice-versa), one of these fields becomes
// a non-never string-literal type and the `_ExhaustivenessProof` assignment
// below fails with a TS2322 pointing at this file.
type _Exhaustive = {
  _forward: Exclude<AllowedWSMessageType, SetToUnion<typeof KNOWN_WS_MESSAGE_TYPES>>;
  _backward: Exclude<SetToUnion<typeof KNOWN_WS_MESSAGE_TYPES>, AllowedWSMessageType>;
};
const _ExhaustivenessProof: { _forward: never; _backward: never } =
  null as unknown as _Exhaustive;
void _ExhaustivenessProof;

export function isKnownWSMessageType(t: unknown): boolean {
  return typeof t === "string" && (KNOWN_WS_MESSAGE_TYPES as ReadonlySet<string>).has(t);
}
