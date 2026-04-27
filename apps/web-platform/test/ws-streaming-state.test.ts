import { describe, test, expect } from "vitest";
import {
  applyStreamEvent,
  applyTimeout,
  type ChatMessage,
} from "../lib/chat-state-machine";
import type { MessageState, WSMessage } from "../lib/types";
import type { DomainLeaderId } from "../server/domain-leaders";

/**
 * Tests import `applyStreamEvent` from production (`lib/chat-state-machine.ts`)
 * so any behavior drift in the state machine surfaces here immediately —
 * previously a shadow copy of the logic lived in this file, which defeated
 * the purpose of the coverage (see #2124).
 */

type StreamEvent = Parameters<typeof applyStreamEvent>[2];

function processEvents(events: StreamEvent[]): ChatMessage[] {
  let messages: ChatMessage[] = [];
  let activeStreams = new Map<DomainLeaderId, number>();
  for (const evt of events) {
    const result = applyStreamEvent(messages, activeStreams, evt);
    messages = result.messages;
    activeStreams = result.activeStreams;
  }
  return messages;
}

describe("client streaming state machine", () => {
  test("single agent lifecycle: thinking → streaming → done", () => {
    const messages = processEvents([
      { type: "stream_start", leaderId: "cmo" },
      { type: "stream", content: "Hello", partial: true, leaderId: "cmo" },
      {
        type: "stream",
        content: "Hello world",
        partial: true,
        leaderId: "cmo",
      },
      { type: "stream_end", leaderId: "cmo" },
    ] as WSMessage[] as StreamEvent[]);

    expect(messages).toHaveLength(1);
    expect(messages[0].state).toBe("done");
    expect(messages[0].content).toBe("Hello world");
  });

  test("lifecycle with tool_use: thinking → tool_use → streaming → done", () => {
    const messages = processEvents([
      { type: "stream_start", leaderId: "cto" },
      { type: "tool_use", leaderId: "cto", label: "Reading file..." },
      { type: "tool_use", leaderId: "cto", label: "Running command..." },
      {
        type: "stream",
        content: "Result text",
        partial: true,
        leaderId: "cto",
      },
      { type: "stream_end", leaderId: "cto" },
    ] as WSMessage[] as StreamEvent[]);

    expect(messages).toHaveLength(1);
    expect(messages[0].state).toBe("done");
    expect(messages[0].content).toBe("Result text");
    // toolsUsed now stores human-readable labels (not raw SDK tool names) — see #2138
    expect(messages[0].toolsUsed).toEqual([
      "Reading file...",
      "Running command...",
    ]);
  });

  test("replace semantics: 3 cumulative partials = final text, not 3x", () => {
    const messages = processEvents([
      { type: "stream_start", leaderId: "cmo" },
      { type: "stream", content: "A", partial: true, leaderId: "cmo" },
      { type: "stream", content: "AB", partial: true, leaderId: "cmo" },
      { type: "stream", content: "ABC", partial: true, leaderId: "cmo" },
      { type: "stream_end", leaderId: "cmo" },
    ] as WSMessage[] as StreamEvent[]);

    expect(messages[0].content).toBe("ABC");
    expect(messages[0].content).not.toBe("AABABC");
  });

  test("state transitions are one-directional", () => {
    const events: StreamEvent[] = [
      { type: "stream_start", leaderId: "cmo" },
      { type: "tool_use", leaderId: "cmo", label: "Reading file..." },
      { type: "stream", content: "text", partial: true, leaderId: "cmo" },
      { type: "stream_end", leaderId: "cmo" },
    ] as WSMessage[] as StreamEvent[];

    const states: MessageState[] = [];
    let messages: ChatMessage[] = [];
    let activeStreams = new Map<DomainLeaderId, number>();
    for (const evt of events) {
      const result = applyStreamEvent(messages, activeStreams, evt);
      messages = result.messages;
      activeStreams = result.activeStreams;
      // After stream_end the map no longer has the leader; peek at the last message.
      const state = messages[messages.length - 1]?.state;
      if (state) states.push(state);
    }

    expect(states).toEqual(["thinking", "tool_use", "streaming", "done"]);
  });

  test("multi-agent: independent state machines per leaderId", () => {
    const messages = processEvents([
      { type: "stream_start", leaderId: "cmo" },
      { type: "stream_start", leaderId: "cto" },
      {
        type: "stream",
        content: "CMO says hello",
        partial: true,
        leaderId: "cmo",
      },
      {
        type: "stream",
        content: "CTO says world",
        partial: true,
        leaderId: "cto",
      },
      { type: "stream_end", leaderId: "cmo" },
      { type: "stream_end", leaderId: "cto" },
    ] as WSMessage[] as StreamEvent[]);

    expect(messages).toHaveLength(2);
    expect(messages[0].content).toBe("CMO says hello");
    expect(messages[0].leaderId).toBe("cmo");
    expect(messages[0].state).toBe("done");

    expect(messages[1].content).toBe("CTO says world");
    expect(messages[1].leaderId).toBe("cto");
    expect(messages[1].state).toBe("done");
  });

  test("no duplicate bubbles: stream_start + stream = 1 bubble", () => {
    const messages = processEvents([
      { type: "stream_start", leaderId: "cmo" },
      { type: "stream", content: "Hello", partial: true, leaderId: "cmo" },
      { type: "stream_end", leaderId: "cmo" },
    ] as WSMessage[] as StreamEvent[]);

    expect(messages).toHaveLength(1);
  });

  test("multiple sequential tool_use events: all labels recorded", () => {
    const messages = processEvents([
      { type: "stream_start", leaderId: "cto" },
      { type: "tool_use", leaderId: "cto", label: "Reading file..." },
      { type: "tool_use", leaderId: "cto", label: "Searching code..." },
      { type: "tool_use", leaderId: "cto", label: "Running command..." },
      { type: "stream", content: "Done", partial: true, leaderId: "cto" },
      { type: "stream_end", leaderId: "cto" },
    ] as WSMessage[] as StreamEvent[]);

    expect(messages[0].toolsUsed).toEqual([
      "Reading file...",
      "Searching code...",
      "Running command...",
    ]);
    expect(messages[0].state).toBe("done");
  });

  test("message IDs use UUID format", () => {
    const messages = processEvents([
      { type: "stream_start", leaderId: "cmo" },
      { type: "stream_end", leaderId: "cmo" },
    ] as WSMessage[] as StreamEvent[]);

    const uuidPattern =
      /^stream-cmo-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
    expect(messages[0].id).toMatch(uuidPattern);
  });

  test("empty DONE state: tools used but no text content", () => {
    const messages = processEvents([
      { type: "stream_start", leaderId: "cto" },
      { type: "tool_use", leaderId: "cto", label: "Reading file..." },
      { type: "tool_use", leaderId: "cto", label: "Running command..." },
      { type: "stream_end", leaderId: "cto" },
    ] as WSMessage[] as StreamEvent[]);

    expect(messages[0].state).toBe("done");
    expect(messages[0].content).toBe("");
    expect(messages[0].toolsUsed).toEqual([
      "Reading file...",
      "Running command...",
    ]);
  });

  test("timerAction is returned on every state-transition event", () => {
    const start = applyStreamEvent(
      [],
      new Map<DomainLeaderId, number>(),
      { type: "stream_start", leaderId: "cmo" } as StreamEvent,
    );
    expect(start.timerAction).toEqual({ type: "reset", leaderId: "cmo" });

    const end = applyStreamEvent(
      start.messages,
      start.activeStreams,
      { type: "stream_end", leaderId: "cmo" } as StreamEvent,
    );
    expect(end.timerAction).toEqual({ type: "clear", leaderId: "cmo" });
  });
});

describe("timeout guard (#2136)", () => {
  test("timeout does not clobber a bubble in 'streaming' state", () => {
    // Seed: thinking → streaming (via a stream event); then fire timeout.
    let messages: ChatMessage[] = [];
    let activeStreams = new Map<DomainLeaderId, number>();
    const s1 = applyStreamEvent(messages, activeStreams, {
      type: "stream_start",
      leaderId: "cmo",
    } as StreamEvent);
    messages = s1.messages;
    activeStreams = s1.activeStreams;
    const s2 = applyStreamEvent(messages, activeStreams, {
      type: "stream",
      content: "partial",
      partial: true,
      leaderId: "cmo",
    } as StreamEvent);
    messages = s2.messages;
    activeStreams = s2.activeStreams;
    expect(messages[0].state).toBe("streaming");

    const timedOut = applyTimeout(messages, activeStreams, "cmo");
    // Still streaming — timeout is stale, must not overwrite.
    expect(timedOut.messages[0].state).toBe("streaming");
  });

  test("timeout does not clobber a bubble in 'done' state", () => {
    let messages: ChatMessage[] = [];
    let activeStreams = new Map<DomainLeaderId, number>();
    const s1 = applyStreamEvent(messages, activeStreams, {
      type: "stream_start",
      leaderId: "cmo",
    } as StreamEvent);
    messages = s1.messages;
    activeStreams = s1.activeStreams;
    const s2 = applyStreamEvent(messages, activeStreams, {
      type: "stream_end",
      leaderId: "cmo",
    } as StreamEvent);
    messages = s2.messages;
    activeStreams = s2.activeStreams;

    const timedOut = applyTimeout(messages, activeStreams, "cmo");
    expect(timedOut.messages[0].state).toBe("done");
  });

  test("first timeout on stuck 'thinking' bubble flags retrying; second transitions to 'error' (FR5 #2861)", () => {
    const s1 = applyStreamEvent(
      [],
      new Map<DomainLeaderId, number>(),
      { type: "stream_start", leaderId: "cmo" } as StreamEvent,
    );
    expect(s1.messages[0].state).toBe("thinking");

    const firstTimeout = applyTimeout(s1.messages, s1.activeStreams, "cmo");
    expect(firstTimeout.messages[0].state).toBe("thinking");
    expect(firstTimeout.messages[0].retrying).toBe(true);
    expect(firstTimeout.activeStreams.has("cmo")).toBe(true);

    const secondTimeout = applyTimeout(
      firstTimeout.messages,
      firstTimeout.activeStreams,
      "cmo",
    );
    expect(secondTimeout.messages[0].state).toBe("error");
    expect(secondTimeout.messages[0].retrying).toBeUndefined();
    expect(secondTimeout.activeStreams.has("cmo")).toBe(false);
  });

  test("first timeout on stuck 'tool_use' bubble flags retrying; second transitions to 'error' (FR5 #2861)", () => {
    let messages: ChatMessage[] = [];
    let activeStreams = new Map<DomainLeaderId, number>();
    const s1 = applyStreamEvent(messages, activeStreams, {
      type: "stream_start",
      leaderId: "cmo",
    } as StreamEvent);
    messages = s1.messages;
    activeStreams = s1.activeStreams;
    const s2 = applyStreamEvent(messages, activeStreams, {
      type: "tool_use",
      leaderId: "cmo",
      label: "Reading file...",
    } as StreamEvent);
    messages = s2.messages;
    activeStreams = s2.activeStreams;

    const firstTimeout = applyTimeout(messages, activeStreams, "cmo");
    expect(firstTimeout.messages[0].state).toBe("tool_use");
    expect(firstTimeout.messages[0].retrying).toBe(true);

    const secondTimeout = applyTimeout(
      firstTimeout.messages,
      firstTimeout.activeStreams,
      "cmo",
    );
    expect(secondTimeout.messages[0].state).toBe("error");
    expect(secondTimeout.messages[0].toolLabel).toBe("Reading file...");
  });
});

describe("tool_use timer reset (#2430)", () => {
  test("tool_use event returns timerAction 'reset' to restart stuck-state timer", () => {
    const s1 = applyStreamEvent(
      [],
      new Map<DomainLeaderId, number>(),
      { type: "stream_start", leaderId: "cmo" } as StreamEvent,
    );

    const s2 = applyStreamEvent(
      s1.messages,
      s1.activeStreams,
      { type: "tool_use", leaderId: "cmo", label: "Reading file..." } as StreamEvent,
    );

    expect(s2.timerAction).toEqual({ type: "reset", leaderId: "cmo" });
  });

  test("each successive tool_use resets the timer", () => {
    let messages: ChatMessage[] = [];
    let activeStreams = new Map<DomainLeaderId, number>();

    const s1 = applyStreamEvent(messages, activeStreams, {
      type: "stream_start",
      leaderId: "cto",
    } as StreamEvent);
    messages = s1.messages;
    activeStreams = s1.activeStreams;

    const s2 = applyStreamEvent(messages, activeStreams, {
      type: "tool_use",
      leaderId: "cto",
      label: "Reading file...",
    } as StreamEvent);
    expect(s2.timerAction).toEqual({ type: "reset", leaderId: "cto" });

    const s3 = applyStreamEvent(s2.messages, s2.activeStreams, {
      type: "tool_use",
      leaderId: "cto",
      label: "Searching code...",
    } as StreamEvent);
    expect(s3.timerAction).toEqual({ type: "reset", leaderId: "cto" });
  });
});
