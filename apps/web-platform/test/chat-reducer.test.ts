import { describe, test, expect } from "vitest";
import { chatReducer, type ChatState, type ChatAction } from "../lib/ws-client";
import type { ChatMessage } from "../lib/chat-state-machine";

function emptyState(): ChatState {
  return {
    messages: [],
    activeStreams: new Map(),
    workflow: { state: "idle" },
    spawnIndex: new Map(),
    streamState: "idle",
    connection: { phase: "live" },
    liveNarration: null,
  };
}

function textMessage(id: string, content = ""): ChatMessage {
  return { id, role: "assistant", content, type: "text" };
}

function gateMessage(gateId: string, opts: Partial<ChatMessage> = {}): ChatMessage {
  return {
    id: `gate-${gateId}`,
    role: "assistant",
    content: "",
    type: "review_gate",
    gateId,
    question: "Pick one",
    options: ["a", "b"],
    ...opts,
  } as ChatMessage;
}

describe("chatReducer", () => {
  test("add_message appends without mutating prior state", () => {
    const state = { ...emptyState(), messages: [textMessage("a")] };
    const next = chatReducer(state, { type: "add_message", message: textMessage("b") });

    expect(next.messages.map(m => m.id)).toEqual(["a", "b"]);
    expect(state.messages).toHaveLength(1); // input unchanged
  });

  test("filter_prepend deduplicates by id and preserves order", () => {
    const existing = [textMessage("x"), textMessage("y")];
    const incoming = [textMessage("a"), textMessage("x"), textMessage("b")];
    const state = { ...emptyState(), messages: existing };

    const next = chatReducer(state, { type: "filter_prepend", messages: incoming });

    expect(next.messages.map(m => m.id)).toEqual(["a", "b", "x", "y"]);
  });

  test("clear_streams empties activeStreams and clears pendingTimerAction", () => {
    const state: ChatState = {
      messages: [],
      activeStreams: new Map([["cpo", 0]]),
      workflow: { state: "idle" },
      spawnIndex: new Map(),
      streamState: "idle",
      connection: { phase: "unrecoverable" },
      liveNarration: null,
      pendingTimerAction: { type: "reset", leaderId: "cpo" },
    };

    const next = chatReducer(state, { type: "clear_streams" });

    expect(next.activeStreams.size).toBe(0);
    expect(next.pendingTimerAction).toBeUndefined();
    // #5282 AC11: the clear_streams arm spreads `...state` and never mentions
    // `connection`, so it carries the slice through unchanged. This is a
    // regression guard against a future edit adding a connection reset here —
    // clear_streams fires on every reconnect, so resetting connection here would
    // defeat the sticky guard (only `reset_connection` may escape unrecoverable).
    expect(next.connection.phase).toBe("unrecoverable");
  });

  test("clear_streams also resets workflow slice and spawnIndex (review F1 #2886)", () => {
    // Pre-condition: a prior workflow_started + subagent_spawn populated the
    // ambient slice + spawnIndex. clear_streams (fired on key_invalid /
    // session_ended / socket remount) MUST reset both — otherwise the
    // lifecycle bar still renders the old workflow's `state: "active"` and
    // stale subagent indices linger.
    const state: ChatState = {
      messages: [],
      activeStreams: new Map([["cpo", 0]]),
      workflow: { state: "active", workflow: "brainstorm" },
      spawnIndex: new Map([
        ["s-1", { messageIdx: 0, childIdx: 0 }],
      ]),
      streamState: "idle",
      connection: { phase: "live" },
      liveNarration: null,
      pendingTimerAction: { type: "reset", leaderId: "cpo" },
    };

    const next = chatReducer(state, { type: "clear_streams" });

    expect(next.activeStreams.size).toBe(0);
    expect(next.workflow).toEqual({ state: "idle" });
    expect(next.spawnIndex.size).toBe(0);
    expect(next.pendingTimerAction).toBeUndefined();
  });

  test("ack_timer_action clears pendingTimerAction", () => {
    const state: ChatState = {
      ...emptyState(),
      liveNarration: null,
      pendingTimerAction: { type: "reset", leaderId: "cpo" },
    };

    const next = chatReducer(state, { type: "ack_timer_action" });

    expect(next.pendingTimerAction).toBeUndefined();
  });

  test("ack_timer_action returns same state reference when nothing pending", () => {
    const state = emptyState();
    const next = chatReducer(state, { type: "ack_timer_action" });
    expect(next).toBe(state);
  });

  test("timeout clears pendingTimerAction so stale intent cannot leak forward", () => {
    // Pre-condition: a prior stream_event left a reset action pending and the
    // timeout fired before the useEffect consumed it. The reducer must drop
    // the pending action to avoid resetting a timer that just fired.
    const state: ChatState = {
      messages: [],
      activeStreams: new Map([["cpo", 0]]),
      workflow: { state: "idle" },
      spawnIndex: new Map(),
      streamState: "idle",
      connection: { phase: "live" },
      liveNarration: null,
      pendingTimerAction: { type: "reset", leaderId: "cpo" },
    };

    const next = chatReducer(state, { type: "timeout", leaderId: "cpo" });

    expect(next.pendingTimerAction).toBeUndefined();
  });

  test("add_message preserves pendingTimerAction reference (no spurious useEffect re-fire)", () => {
    const ta = { type: "reset" as const, leaderId: "cpo" };
    const state: ChatState = { ...emptyState(), pendingTimerAction: ta };

    const next = chatReducer(state, { type: "add_message", message: textMessage("x") });

    // Same reference → useEffect dep array sees no change, doesn't double-reset.
    expect(next.pendingTimerAction).toBe(ta);
  });

  test("gate_error sets gateError and resets resolved/selectedOption on the targeted gate only", () => {
    const state = {
      ...emptyState(),
      messages: [
        gateMessage("g1", { resolved: true, selectedOption: "a" }),
        gateMessage("g2", { resolved: true, selectedOption: "b" }),
      ],
    };

    const next = chatReducer(state, { type: "gate_error", gateId: "g1", message: "Try again" });

    const g1 = next.messages.find(m => m.type === "review_gate" && m.gateId === "g1");
    const g2 = next.messages.find(m => m.type === "review_gate" && m.gateId === "g2");
    expect(g1).toMatchObject({ gateError: "Try again", resolved: false, selectedOption: undefined });
    // g2 untouched: still resolved with original selection, no gateError introduced.
    expect(g2).toBe(state.messages[1]);
  });

  test("resolve_gate marks gate resolved, clears gateError, sets selection on the targeted gate only", () => {
    const state = {
      ...emptyState(),
      messages: [
        gateMessage("g1", { gateError: "stale" }),
        gateMessage("g2"),
      ],
    };

    const next = chatReducer(state, { type: "resolve_gate", gateId: "g1", selection: "a" });

    const g1 = next.messages.find(m => m.type === "review_gate" && m.gateId === "g1");
    const g2 = next.messages.find(m => m.type === "review_gate" && m.gateId === "g2");
    expect(g1).toMatchObject({ resolved: true, selectedOption: "a", gateError: undefined });
    // g2 untouched (same reference).
    expect(g2).toBe(state.messages[1]);
  });

  test("stream_event delegates to applyStreamEvent and propagates timerAction", () => {
    const state = emptyState();
    const action: ChatAction = {
      type: "stream_event",
      msg: { type: "stream_start", leaderId: "cpo" } as any,
    };

    const next = chatReducer(state, action);

    expect(next.activeStreams.get("cpo")).toBeDefined();
    expect(next.pendingTimerAction).toEqual({ type: "reset", leaderId: "cpo" });
  });

  describe("cc turn end: stream_end for the cc router returns streamState to idle", () => {
    const streamMsg = (leaderId: string, content = "hi") =>
      ({ type: "stream", leaderId, content, partial: true }) as never;
    const streamEnd = (leaderId: string) => ({ type: "stream_end", leaderId }) as never;

    test("cc_router stream + stream_end -> idle", () => {
      let s = emptyState();
      s = chatReducer(s, { type: "stream_event", msg: streamMsg("cc_router") });
      expect(s.streamState).toBe("streaming");
      s = chatReducer(s, { type: "stream_event", msg: streamEnd("cc_router") });
      expect(s.activeStreams.size).toBe(0);
      expect(s.streamState).toBe("idle");
    });

    test("stopping is preserved (only session_ended:user_aborted releases it)", () => {
      let s = emptyState();
      s = chatReducer(s, { type: "stream_event", msg: streamMsg("cc_router") });
      s = chatReducer(s, { type: "enter_stopping" });
      expect(s.streamState).toBe("stopping");
      s = chatReducer(s, { type: "stream_event", msg: streamEnd("cc_router") });
      expect(s.streamState).toBe("stopping");
    });

    test("legacy leader stream_end with another leader still streaming stays streaming", () => {
      let s = emptyState();
      s = chatReducer(s, { type: "stream_event", msg: streamMsg("cpo") });
      s = chatReducer(s, { type: "stream_event", msg: streamMsg("cto") });
      s = chatReducer(s, { type: "stream_event", msg: streamEnd("cpo") });
      expect(s.activeStreams.size).toBe(1);
      expect(s.streamState).toBe("streaming");
    });

    test("workflow and spawnIndex are untouched (this is not clear_streams)", () => {
      let s = emptyState();
      const workflow = { state: "active", workflow: "brainstorm" } as never;
      s = { ...s, workflow };
      s = chatReducer(s, { type: "stream_event", msg: streamMsg("cc_router") });
      const before = { workflow: s.workflow, spawnIndex: s.spawnIndex };
      s = chatReducer(s, { type: "stream_event", msg: streamEnd("cc_router") });
      expect(s.streamState).toBe("idle");
      expect(s.workflow).toBe(before.workflow);
      expect(s.spawnIndex).toBe(before.spawnIndex);
    });

    test("a review_gate earlier in the turn does not break the transition", () => {
      let s = { ...emptyState(), messages: [gateMessage("g1")] };
      s = chatReducer(s, { type: "stream_event", msg: streamMsg("cc_router") });
      s = chatReducer(s, { type: "stream_event", msg: streamEnd("cc_router") });
      expect(s.streamState).toBe("idle");
    });

    test("stream_end before any stream (nothing to end) stays idle", () => {
      const s = chatReducer(emptyState(), { type: "stream_event", msg: streamEnd("cc_router") });
      expect(s.streamState).toBe("idle");
    });
  });

  test("exhaustive: all action discriminants are handled (TypeScript guarantees, runtime sanity)", () => {
    const actions: ChatAction["type"][] = [
      "stream_event",
      "timeout",
      "clear_streams",
      "ack_timer_action",
      "add_message",
      "filter_prepend",
      "gate_error",
      "resolve_gate",
      "resolve_interactive_prompt",
    ];
    expect(actions).toHaveLength(9);
  });
});
