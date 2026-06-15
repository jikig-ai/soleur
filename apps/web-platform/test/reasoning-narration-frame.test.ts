import { describe, test, expect } from "vitest";
import { chatReducer, type ChatState } from "../lib/ws-client";
import type { ChatMessage } from "../lib/chat-state-machine";
import {
  BUFFERED_FRAME_TYPES,
  isBufferedFrame,
} from "../server/stream-replay-buffer";

// feat-reasoning-chat-boxes (#5370) — `reasoning_narration` is the TRANSIENT
// live status line. It is live-only (mirrors `debug_event`): NEVER buffered,
// NEVER replayed; the ws-client reducer owns its teardown on every turn-end arm
// because abort/timeout/disconnect emit NO StreamEvent.

function baseState(over: Partial<ChatState> = {}): ChatState {
  return {
    messages: [],
    activeStreams: new Map(),
    workflow: { state: "idle" },
    spawnIndex: new Map(),
    streamState: "idle",
    connection: { phase: "live" },
    liveNarration: "Looking into your billing settings…",
    ...over,
  };
}

describe("reasoning_narration — buffer exclusion (never replays)", () => {
  test("reasoning_narration is NOT a buffered frame type", () => {
    expect(BUFFERED_FRAME_TYPES.has("reasoning_narration")).toBe(false);
    expect(isBufferedFrame({ type: "reasoning_narration", message: "x" })).toBe(false);
  });

  test("turn_summary IS a buffered frame type (opposite membership)", () => {
    expect(BUFFERED_FRAME_TYPES.has("turn_summary")).toBe(true);
  });
});

describe("ws-client reducer — liveNarration teardown (one arm each)", () => {
  test("set_live_narration sets the single slot", () => {
    const next = chatReducer(baseState({ liveNarration: null }), {
      type: "set_live_narration",
      message: "Drafting the reply…",
    });
    expect(next.liveNarration).toBe("Drafting the reply…");
  });

  test("clear_streams clears liveNarration (session_ended / socket remount / abort)", () => {
    const next = chatReducer(baseState(), { type: "clear_streams" });
    expect(next.liveNarration).toBeNull();
  });

  test("enter_stopping clears liveNarration (user Stop)", () => {
    const next = chatReducer(baseState({ streamState: "streaming" }), {
      type: "enter_stopping",
    });
    expect(next.liveNarration).toBeNull();
  });

  test("connection_change to a non-live phase clears liveNarration (onclose/disconnect)", () => {
    const next = chatReducer(baseState(), {
      type: "connection_change",
      phase: "unrecoverable",
    });
    expect(next.liveNarration).toBeNull();
  });

  test("timeout that escalates the last leader to error clears liveNarration", () => {
    // Single in-flight leader bubble, already retrying → a second timeout with
    // no sibling active escalates it to error and empties activeStreams, which
    // is the turn-end signal the arm tears down on.
    const bubble = {
      id: "b0",
      role: "assistant",
      content: "",
      type: "text",
      state: "thinking",
      retrying: true,
      leaderId: "cpo",
    } as unknown as ChatMessage;
    const state = baseState({
      messages: [bubble],
      activeStreams: new Map([["cpo", 0]]) as ChatState["activeStreams"],
      streamState: "streaming",
    });
    const next = chatReducer(state, { type: "timeout", leaderId: "cpo" });
    expect(next.activeStreams.size).toBe(0);
    expect(next.liveNarration).toBeNull();
  });
});
