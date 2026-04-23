import { describe, test, expect } from "vitest";
import { applyStreamEvent, applyTimeout } from "../lib/chat-state-machine";
import type { ChatMessage } from "../lib/chat-state-machine";
import type { DomainLeaderId } from "../server/domain-leaders";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function thinkingMessage(leaderId: string): ChatMessage {
  return {
    id: `stream-${leaderId}-1`,
    role: "assistant",
    content: "",
    type: "text",
    leaderId: leaderId as any,
    state: "thinking",
    toolsUsed: [],
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("chat-state-machine timeout behavior", () => {
  test("tool_use event resets the timer (#2430)", () => {
    const prev: ChatMessage[] = [thinkingMessage("cpo")];
    const streams = new Map([["cpo", 0]]);

    const result = applyStreamEvent(prev, streams, {
      type: "tool_use",
      leaderId: "cpo" as any,
      label: "Read",
    } as any);

    // tool_use resets the timer — long-running tools should not trigger
    // "Agent stopped responding" while the agent is actively working.
    expect(result.timerAction).toEqual({ type: "reset", leaderId: "cpo" });
  });

  test("stream event resets the timer", () => {
    const prev: ChatMessage[] = [thinkingMessage("cpo")];
    const streams = new Map([["cpo", 0]]);

    const result = applyStreamEvent(prev, streams, {
      type: "stream",
      leaderId: "cpo" as any,
      content: "Hello",
    } as any);

    expect(result.timerAction).toEqual({ type: "reset", leaderId: "cpo" });
  });

  test("stream_start event resets the timer", () => {
    const result = applyStreamEvent([], new Map(), {
      type: "stream_start",
      leaderId: "cpo" as any,
    } as any);

    expect(result.timerAction).toEqual({ type: "reset", leaderId: "cpo" });
  });

  test("applyTimeout: second consecutive timeout on thinking bubble transitions to error", () => {
    // FR5: first timeout flags retrying, second consecutive timeout transitions
    // to error. Simulate the "second" timeout by seeding retrying: true.
    const msg: ChatMessage = { ...thinkingMessage("cpo"), retrying: true };
    const prev: ChatMessage[] = [msg];
    const streams = new Map([["cpo", 0]]);

    const result = applyTimeout(prev, streams, "cpo");

    expect(result.messages[0].state).toBe("error");
    expect(result.activeStreams.has("cpo")).toBe(false);
  });

  test("applyTimeout: second consecutive timeout on tool_use bubble transitions to error", () => {
    const msg: ChatMessage = { ...thinkingMessage("cpo"), state: "tool_use", retrying: true };
    const prev: ChatMessage[] = [msg];
    const streams = new Map([["cpo", 0]]);

    const result = applyTimeout(prev, streams, "cpo");

    expect(result.messages[0].state).toBe("error");
  });

  test("applyTimeout does NOT affect streaming bubble", () => {
    const msg: ChatMessage = { ...thinkingMessage("cpo"), state: "streaming" };
    const prev: ChatMessage[] = [msg];
    const streams = new Map([["cpo", 0]]);

    const result = applyTimeout(prev, streams, "cpo");

    expect(result.messages[0].state).toBe("streaming");
  });
});

describe("chat-state-machine review_gate terminal transitions (#2843)", () => {
  // Regression: when a review_gate event fires mid-turn with one or more
  // active streams, the gate branch previously cleared `activeStreams` via
  // `new Map()` without transitioning the bubbles' state. That leaked
  // "thinking"/"tool_use"/"streaming" into a stuck "Working" badge the client
  // could not clear. The fix transitions every active bubble to "done" BEFORE
  // clearing the map.

  // Typed event builders — avoid `as any` so that widening the StreamEvent
  // union forces these tests to update rather than silently accepting.
  const reviewGateEvent = (gateId: string, question = "Proceed?"): {
    type: "review_gate";
    gateId: string;
    question: string;
    options: string[];
  } => ({
    type: "review_gate",
    gateId,
    question,
    options: ["yes", "no"],
  });

  const streamEndEvent = (leaderId: DomainLeaderId): {
    type: "stream_end";
    leaderId: DomainLeaderId;
  } => ({ type: "stream_end", leaderId });

  test("review_gate transitions a thinking peer bubble to done", () => {
    const prev: ChatMessage[] = [thinkingMessage("cpo"), thinkingMessage("cto")];
    const streams = new Map([["cpo", 0], ["cto", 1]]);

    const result = applyStreamEvent(prev, streams, reviewGateEvent("g1"));

    // Both leader bubbles should be transitioned to "done", not left stuck
    // at "thinking". The gate message is appended after them.
    expect(result.messages[0].state).toBe("done");
    expect(result.messages[1].state).toBe("done");
    expect(result.messages[2].type).toBe("review_gate");
    expect(result.activeStreams.size).toBe(0);
    expect(result.timerAction).toEqual({ type: "clear_all" });
  });

  test("review_gate transitions a tool_use peer bubble to done", () => {
    const toolBubble: ChatMessage = { ...thinkingMessage("cpo"), state: "tool_use", toolLabel: "Read foo.md" };
    const streamingBubble: ChatMessage = { ...thinkingMessage("cto"), state: "streaming", content: "Working on..." };
    const prev: ChatMessage[] = [toolBubble, streamingBubble];
    const streams = new Map([["cpo", 0], ["cto", 1]]);

    const result = applyStreamEvent(prev, streams, reviewGateEvent("g2", "Continue?"));

    expect(result.messages[0].state).toBe("done");
    expect(result.messages[1].state).toBe("done");
  });

  test("review_gate leaves already-done bubbles untouched", () => {
    const doneBubble: ChatMessage = { ...thinkingMessage("cpo"), state: "done", content: "Final answer" };
    const prev: ChatMessage[] = [doneBubble];
    // Empty activeStreams — done bubble already transitioned out
    const streams = new Map<string, number>();

    const result = applyStreamEvent(prev, streams, reviewGateEvent("g3", "OK?"));

    expect(result.messages[0].state).toBe("done");
    expect(result.messages[0].content).toBe("Final answer");
  });

  test("review_gate preserves unrelated messages between active streams", () => {
    // Sparse activeStreams: bubbles at indices 0 and 3 with a user message
    // and a prior done bubble in between. Only indices 0 and 3 transition;
    // the middle messages must survive untouched.
    const prev: ChatMessage[] = [
      { ...thinkingMessage("cpo"), state: "tool_use" },
      { id: "user-1", role: "user", content: "hi", type: "text", state: "done" },
      { ...thinkingMessage("cto"), state: "done", content: "Prior answer" },
      { ...thinkingMessage("coo"), state: "streaming", content: "streaming..." },
    ];
    const streams = new Map<string, number>([["cpo", 0], ["coo", 3]]);

    const result = applyStreamEvent(prev, streams, reviewGateEvent("g4"));

    expect(result.messages[0].state).toBe("done");
    expect(result.messages[1].state).toBe("done");
    expect(result.messages[1].content).toBe("hi");
    expect(result.messages[2].content).toBe("Prior answer");
    expect(result.messages[3].state).toBe("done");
    expect(result.messages[4].type).toBe("review_gate");
  });

  test("review_gate is a no-op on stale activeStreams entries pointing past prev.length", () => {
    // If the map references an index that no longer exists in prev (malformed
    // upstream state), the OOB guard at `if (idx >= updated.length) continue`
    // must skip silently rather than throw.
    const prev: ChatMessage[] = [thinkingMessage("cpo")];
    const streams = new Map<string, number>([["cpo", 0], ["ghost", 42]]);

    const result = applyStreamEvent(prev, streams, reviewGateEvent("g5"));

    expect(result.messages[0].state).toBe("done");
    expect(result.messages[1].type).toBe("review_gate");
    expect(result.activeStreams.size).toBe(0);
  });

  test("stream_end on single leader transitions to done (regression sentinel)", () => {
    const prev: ChatMessage[] = [thinkingMessage("cpo")];
    const streams = new Map([["cpo", 0]]);

    const result = applyStreamEvent(prev, streams, streamEndEvent("cpo"));

    expect(result.messages[0].state).toBe("done");
    expect(result.activeStreams.has("cpo")).toBe(false);
  });

  test("stream_end on one leader preserves peer leaders (regression sentinel)", () => {
    // Parallel dispatch: CPO finishes first, CTO still working.
    // CPO bubble should reach "done"; CTO bubble should keep its tool_use state.
    const cpoBubble: ChatMessage = { ...thinkingMessage("cpo"), state: "tool_use" };
    const ctoBubble: ChatMessage = { ...thinkingMessage("cto"), state: "tool_use" };
    const prev: ChatMessage[] = [cpoBubble, ctoBubble];
    const streams = new Map([["cpo", 0], ["cto", 1]]);

    const result = applyStreamEvent(prev, streams, streamEndEvent("cpo"));

    expect(result.messages[0].state).toBe("done");
    expect(result.messages[1].state).toBe("tool_use");
    expect(result.activeStreams.has("cpo")).toBe(false);
    expect(result.activeStreams.has("cto")).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// FR4: tool_progress event (#2861)
// ---------------------------------------------------------------------------

describe("chat-state-machine tool_progress event (FR4 #2861)", () => {
  const toolProgressEvent = (leaderId: DomainLeaderId): {
    type: "tool_progress";
    leaderId: DomainLeaderId;
    toolUseId: string;
    toolName: string;
    elapsedSeconds: number;
  } => ({
    type: "tool_progress",
    leaderId,
    toolUseId: "tool-use-1",
    toolName: "Bash",
    elapsedSeconds: 30,
  });

  test("tool_progress on tool_use bubble resets watchdog without mutating messages", () => {
    const toolBubble: ChatMessage = { ...thinkingMessage("cpo"), state: "tool_use", toolLabel: "Searching code" };
    const prev: ChatMessage[] = [toolBubble];
    const streams = new Map([["cpo", 0]]);

    const result = applyStreamEvent(prev, streams, toolProgressEvent("cpo" as any) as any);

    // Messages array reference is preserved (no mutation in the hot path).
    expect(result.messages).toBe(prev);
    expect(result.timerAction).toEqual({ type: "reset", leaderId: "cpo" });
  });

  test("tool_progress for unknown leader is an inert no-op", () => {
    const prev: ChatMessage[] = [thinkingMessage("cpo")];
    const streams = new Map([["cpo", 0]]);

    const result = applyStreamEvent(prev, streams, toolProgressEvent("cto" as any) as any);

    expect(result.messages).toBe(prev);
    expect(result.activeStreams).toBe(streams);
    expect(result.timerAction).toBeUndefined();
  });

  test("tool_progress on a retrying bubble transitions back to tool_use and clears retrying", () => {
    const retryingBubble: ChatMessage = {
      ...thinkingMessage("cpo"),
      state: "tool_use",
      toolLabel: "Searching code",
      retrying: true,
    };
    const prev: ChatMessage[] = [retryingBubble];
    const streams = new Map([["cpo", 0]]);

    const result = applyStreamEvent(prev, streams, toolProgressEvent("cpo" as any) as any);

    expect(result.messages[0].state).toBe("tool_use");
    expect(result.messages[0].retrying).toBeUndefined();
    expect(result.timerAction).toEqual({ type: "reset", leaderId: "cpo" });
  });
});

// ---------------------------------------------------------------------------
// FR5: retry lifecycle (#2861)
// ---------------------------------------------------------------------------

describe("chat-state-machine applyTimeout retry lifecycle (FR5 #2861)", () => {
  test("first applyTimeout on tool_use bubble flags retrying (no state transition)", () => {
    const msg: ChatMessage = { ...thinkingMessage("cpo"), state: "tool_use", toolLabel: "Searching code" };
    const prev: ChatMessage[] = [msg];
    const streams = new Map([["cpo", 0]]);

    const result = applyTimeout(prev, streams, "cpo");

    expect(result.messages[0].state).toBe("tool_use");
    expect(result.messages[0].retrying).toBe(true);
    expect(result.messages[0].toolLabel).toBe("Searching code");
    // Leader stays in the active-streams map so the watchdog reset is valid.
    expect(result.activeStreams.has("cpo")).toBe(true);
    expect(result.timerAction).toEqual({ type: "reset", leaderId: "cpo" });
  });

  test("second applyTimeout transitions retrying bubble to error with label preserved", () => {
    const msg: ChatMessage = {
      ...thinkingMessage("cpo"),
      state: "tool_use",
      toolLabel: "Searching code",
      retrying: true,
    };
    const prev: ChatMessage[] = [msg];
    const streams = new Map([["cpo", 0]]);

    const result = applyTimeout(prev, streams, "cpo");

    expect(result.messages[0].state).toBe("error");
    expect(result.messages[0].retrying).toBeUndefined();
    expect(result.messages[0].toolLabel).toBe("Searching code");
    expect(result.activeStreams.has("cpo")).toBe(false);
    expect(result.timerAction).toEqual({ type: "clear", leaderId: "cpo" });
  });

  test("first applyTimeout on thinking bubble (no toolLabel) also flags retrying", () => {
    const prev: ChatMessage[] = [thinkingMessage("cpo")];
    const streams = new Map([["cpo", 0]]);

    const result = applyTimeout(prev, streams, "cpo");

    expect(result.messages[0].state).toBe("thinking");
    expect(result.messages[0].retrying).toBe(true);
  });

  test("narrowness invariant: timeout-gate does NOT fire on already-error bubbles", () => {
    // If a server-emitted `error` event has already transitioned the bubble
    // to `"error"` (handled by the ws-client `error` case that clears
    // activeStreams), a late-arriving applyTimeout for that leader must be a
    // stale-timer no-op — never revive a terminal bubble into retrying.
    const errorBubble: ChatMessage = {
      ...thinkingMessage("cpo"),
      state: "error",
    };
    // activeStreams already cleared by the `error` branch in ws-client.
    const streams = new Map<string, number>();

    const result = applyTimeout([errorBubble], streams, "cpo");

    expect(result.messages[0].state).toBe("error");
    expect(result.messages[0].retrying).toBeUndefined();
  });
});

describe("chat-state-machine STUCK_TIMEOUT_MS constant", () => {
  test("timeout constant is 45000ms", async () => {
    // The constant lives in ws-client.ts — import it to verify the value
    // We use a targeted grep-style assertion since ws-client has React hooks
    // that can't be imported in a node test environment.
    const fs = await import("fs");
    const path = await import("path");
    const wsClientPath = path.join(__dirname, "..", "lib", "ws-client.ts");
    const content = fs.readFileSync(wsClientPath, "utf-8");

    expect(content).toContain("STUCK_TIMEOUT_MS = 45_000");
    expect(content).not.toContain("STUCK_TIMEOUT_MS = 30_000");
  });
});
