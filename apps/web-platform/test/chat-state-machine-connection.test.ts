import { describe, test, expect } from "vitest";
import {
  chatReducer,
  type ChatState,
  type ConnectionPhase,
} from "../lib/ws-client";
import { deriveReconnectView } from "../lib/chat-state-machine";

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

describe("connection slice — connection_change (AC4 latest-wins)", () => {
  test("initial state is live", () => {
    expect(emptyState().connection.phase).toBe("live");
  });

  test("flap live→reconnecting→live→reconnecting leaves phase=reconnecting (latest wins)", () => {
    let state = emptyState();
    for (const phase of ["reconnecting", "live", "reconnecting"] as ConnectionPhase[]) {
      state = chatReducer(state, { type: "connection_change", phase });
    }
    expect(state.connection.phase).toBe("reconnecting");
  });

  test("connection_change does not mutate the prior state (immutability)", () => {
    const state = emptyState();
    const next = chatReducer(state, { type: "connection_change", phase: "reconnecting" });
    expect(state.connection.phase).toBe("live"); // input unchanged
    expect(next.connection.phase).toBe("reconnecting");
  });

  test("connection_change leaves other slices untouched", () => {
    const state = { ...emptyState(), streamState: "streaming" as const };
    const next = chatReducer(state, { type: "connection_change", phase: "reconnecting" });
    expect(next.streamState).toBe("streaming");
    expect(next.messages).toBe(state.messages);
  });
});

describe("connection slice — sticky unrecoverable (AC5 / AC11 no 3→4 flip)", () => {
  test("once unrecoverable, connection_change to live is a no-op (sticky guard)", () => {
    let state = chatReducer(emptyState(), { type: "connection_change", phase: "unrecoverable" });
    expect(state.connection.phase).toBe("unrecoverable");
    state = chatReducer(state, { type: "connection_change", phase: "live" });
    expect(state.connection.phase).toBe("unrecoverable");
    state = chatReducer(state, { type: "connection_change", phase: "reconnecting" });
    expect(state.connection.phase).toBe("unrecoverable");
  });

  test("unrecoverable survives clear_streams (which carries connection through unchanged)", () => {
    // clear_streams spreads `...state` and never touches `connection`; since it
    // fires on every reconnect, this carry-through is what keeps the sticky
    // guard intact. Regression guard against a future connection reset here.
    let state = chatReducer(emptyState(), { type: "connection_change", phase: "unrecoverable" });
    state = chatReducer(state, { type: "clear_streams" });
    expect(state.connection.phase).toBe("unrecoverable");
  });

  test("reset_connection is the ONLY escape from unrecoverable → live (new turn)", () => {
    let state = chatReducer(emptyState(), { type: "connection_change", phase: "unrecoverable" });
    state = chatReducer(state, { type: "reset_connection" });
    expect(state.connection.phase).toBe("live");
  });

  test("reset_connection from live is idempotent (stays live)", () => {
    const state = chatReducer(emptyState(), { type: "reset_connection" });
    expect(state.connection.phase).toBe("live");
  });

  test("connection_change to unrecoverable CLEARS a stale resumedAt (2nd no-3→4 layer)", () => {
    // A reattach set resumedAt (State 4 pending), then the resume turned out
    // incomplete → unrecoverable. The slice must drop resumedAt so the render
    // layer cannot show State 4 even before the sticky guard engages.
    const withResumed: ChatState = {
      ...emptyState(),
      connection: { phase: "live", resumedAt: 1_000 },
    };
    const next = chatReducer(withResumed, { type: "connection_change", phase: "unrecoverable" });
    expect(next.connection.phase).toBe("unrecoverable");
    expect(next.connection.resumedAt).toBeUndefined();
  });

  test("connection_change to reconnecting clears a stale resumedAt", () => {
    const withResumed: ChatState = {
      ...emptyState(),
      connection: { phase: "live", resumedAt: 1_000 },
    };
    const next = chatReducer(withResumed, { type: "connection_change", phase: "reconnecting" });
    expect(next.connection.resumedAt).toBeUndefined();
  });
});

describe("deriveReconnectView — precedence (AC6 / AC12)", () => {
  test("reconnecting → connection_lost regardless of hasRetryingBubble", () => {
    expect(deriveReconnectView({ phase: "reconnecting", hasRetryingBubble: false }).kind).toBe(
      "connection_lost",
    );
    expect(deriveReconnectView({ phase: "reconnecting", hasRetryingBubble: true }).kind).toBe(
      "connection_lost",
    );
  });

  test("live + retrying bubble → no_activity (State 2)", () => {
    expect(deriveReconnectView({ phase: "live", hasRetryingBubble: true }).kind).toBe("no_activity");
  });

  test("live + no retrying bubble → none", () => {
    expect(deriveReconnectView({ phase: "live", hasRetryingBubble: false }).kind).toBe("none");
  });

  test("unrecoverable does NOT participate in the State1-vs-State2 precedence union", () => {
    // unrecoverable is a separate render branch (State 3); the precedence union
    // covers only connection_lost (State 1) vs no_activity (State 2).
    expect(deriveReconnectView({ phase: "unrecoverable", hasRetryingBubble: true }).kind).toBe(
      "none",
    );
    expect(deriveReconnectView({ phase: "unrecoverable", hasRetryingBubble: false }).kind).toBe(
      "none",
    );
  });

  test("connection_lost ⟹ ¬no_activity (mutual exclusion, full truth table)", () => {
    const phases: ConnectionPhase[] = ["live", "reconnecting", "unrecoverable"];
    for (const phase of phases) {
      for (const hasRetryingBubble of [true, false]) {
        const view = deriveReconnectView({ phase, hasRetryingBubble });
        if (view.kind === "connection_lost") {
          expect(view.kind).not.toBe("no_activity");
        }
      }
    }
  });
});
