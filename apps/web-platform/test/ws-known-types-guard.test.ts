import { describe, test, expect } from "vitest";
import { KNOWN_WS_MESSAGE_TYPES, isKnownWSMessageType } from "../lib/ws-known-types";

// ---------------------------------------------------------------------------
// FR4 (#2861): boundary-level type guard at the WS onmessage site. The
// reducer is exhaustive over a TS discriminated union, so an unknown runtime
// event would simply drop inertly — but without instrumentation we can't
// detect server/client skew. This guard + reportSilentFallback is the 3-line
// substitute for a full zod schema.
// ---------------------------------------------------------------------------

describe("KNOWN_WS_MESSAGE_TYPES (FR4 #2861)", () => {
  test("exact set of expected WSMessage + ClosePreamble types", () => {
    // These types MUST stay in sync with types.ts WSMessage + ClosePreamble.
    // Exact-match (not superset) assertion so a silently-added/removed entry
    // fails the test. The compile-time `_Exhaustive` in ws-known-types.ts is
    // the primary defense; this test is the runtime backstop.
    const expected = [
      "auth",
      "auth_ok",
      "chat",
      "start_session",
      "resume_session",
      "close_conversation",
      "review_gate_response",
      "stream",
      "stream_start",
      "stream_end",
      "tool_use",
      "tool_progress", // FR4 (#2861)
      "review_gate",
      "session_started",
      "session_resumed",
      "session_ended",
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
      "concurrency_cap_hit",
      "tier_changed",
    ].sort();
    const actual = Array.from(
      KNOWN_WS_MESSAGE_TYPES as ReadonlySet<string>,
    ).sort();
    expect(actual).toEqual(expected);
  });

  test("isKnownWSMessageType returns true for known types", () => {
    expect(isKnownWSMessageType("tool_progress")).toBe(true);
    expect(isKnownWSMessageType("stream")).toBe(true);
    expect(isKnownWSMessageType("auth_ok")).toBe(true);
  });

  test("isKnownWSMessageType returns false for unknown types", () => {
    expect(isKnownWSMessageType("zz_does_not_exist")).toBe(false);
    expect(isKnownWSMessageType("")).toBe(false);
  });

  test("isKnownWSMessageType tolerates non-string input without throwing", () => {
    expect(isKnownWSMessageType(undefined)).toBe(false);
    expect(isKnownWSMessageType(null)).toBe(false);
    expect(isKnownWSMessageType(42 as any)).toBe(false);
  });
});
