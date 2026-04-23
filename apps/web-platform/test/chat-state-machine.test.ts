import { describe, test, expect } from "vitest";
import { applyStreamEvent, applyTimeout } from "../lib/chat-state-machine";
import type { ChatMessage } from "../lib/chat-state-machine";

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

  test("applyTimeout transitions thinking bubble to error", () => {
    const prev: ChatMessage[] = [thinkingMessage("cpo")];
    const streams = new Map([["cpo", 0]]);

    const result = applyTimeout(prev, streams, "cpo");

    expect(result.messages[0].state).toBe("error");
    expect(result.activeStreams.has("cpo")).toBe(false);
  });

  test("applyTimeout transitions tool_use bubble to error", () => {
    const msg: ChatMessage = { ...thinkingMessage("cpo"), state: "tool_use" };
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

  test("review_gate transitions a thinking peer bubble to done", () => {
    const prev: ChatMessage[] = [thinkingMessage("cpo"), thinkingMessage("cto")];
    const streams = new Map([["cpo", 0], ["cto", 1]]);

    const result = applyStreamEvent(prev, streams, {
      type: "review_gate",
      gateId: "g1",
      question: "Proceed?",
      options: ["yes", "no"],
    } as any);

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

    const result = applyStreamEvent(prev, streams, {
      type: "review_gate",
      gateId: "g2",
      question: "Continue?",
      options: ["yes", "no"],
    } as any);

    expect(result.messages[0].state).toBe("done");
    expect(result.messages[1].state).toBe("done");
  });

  test("review_gate leaves already-done bubbles untouched", () => {
    const doneBubble: ChatMessage = { ...thinkingMessage("cpo"), state: "done", content: "Final answer" };
    const prev: ChatMessage[] = [doneBubble];
    // Empty activeStreams — done bubble already transitioned out
    const streams = new Map<string, number>();

    const result = applyStreamEvent(prev, streams, {
      type: "review_gate",
      gateId: "g3",
      question: "OK?",
      options: ["yes", "no"],
    } as any);

    expect(result.messages[0].state).toBe("done");
    expect(result.messages[0].content).toBe("Final answer");
  });

  test("stream_end on single leader transitions to done (regression sentinel)", () => {
    const prev: ChatMessage[] = [thinkingMessage("cpo")];
    const streams = new Map([["cpo", 0]]);

    const result = applyStreamEvent(prev, streams, {
      type: "stream_end",
      leaderId: "cpo" as any,
    } as any);

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

    const result = applyStreamEvent(prev, streams, {
      type: "stream_end",
      leaderId: "cpo" as any,
    } as any);

    expect(result.messages[0].state).toBe("done");
    expect(result.messages[1].state).toBe("tool_use");
    expect(result.activeStreams.has("cpo")).toBe(false);
    expect(result.activeStreams.has("cto")).toBe(true);
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
