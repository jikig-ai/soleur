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
