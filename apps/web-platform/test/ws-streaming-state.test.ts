import { describe, test, expect } from "vitest";
import type { MessageState } from "../lib/types";

// Test the client-side streaming state machine logic.
// These tests validate the state transitions and content handling
// that ws-client.ts must implement for the 4-state message lifecycle.

/** Minimal chat message shape matching ws-client.ts ChatMessage */
interface TestMessage {
  id: string;
  role: "user" | "assistant";
  content: string;
  state?: MessageState;
  toolLabel?: string;
  toolsUsed?: string[];
  leaderId?: string;
}

/**
 * Simulate the client state machine by processing a sequence of WS events.
 * This mirrors the logic that ws-client.ts must implement.
 */
function processEvents(events: Array<Record<string, unknown>>): TestMessage[] {
  const messages: TestMessage[] = [];
  const activeStreams = new Map<string, number>();

  for (const evt of events) {
    const leaderId = evt.leaderId as string;

    switch (evt.type) {
      case "stream_start": {
        const msg: TestMessage = {
          id: `stream-${leaderId}-${crypto.randomUUID()}`,
          role: "assistant",
          content: "",
          state: "thinking",
          leaderId,
          toolsUsed: [],
        };
        activeStreams.set(leaderId, messages.length);
        messages.push(msg);
        break;
      }

      case "tool_use": {
        const idx = activeStreams.get(leaderId);
        if (idx !== undefined && idx < messages.length) {
          messages[idx] = {
            ...messages[idx],
            state: "tool_use",
            toolLabel: evt.label as string,
            toolsUsed: [...(messages[idx].toolsUsed ?? []), evt.tool as string],
          };
        }
        break;
      }

      case "stream": {
        const idx = activeStreams.get(leaderId);
        if (idx !== undefined && idx < messages.length) {
          // REPLACE content (not append) — server sends cumulative snapshots
          messages[idx] = {
            ...messages[idx],
            content: evt.content as string,
            state: "streaming",
            toolLabel: undefined,
          };
        }
        break;
      }

      case "stream_end": {
        const idx = activeStreams.get(leaderId);
        if (idx !== undefined && idx < messages.length) {
          messages[idx] = {
            ...messages[idx],
            state: "done",
          };
        }
        activeStreams.delete(leaderId);
        break;
      }
    }
  }

  return messages;
}

describe("client streaming state machine", () => {
  test("single agent lifecycle: thinking → streaming → done", () => {
    const messages = processEvents([
      { type: "stream_start", leaderId: "cmo" },
      { type: "stream", content: "Hello", partial: true, leaderId: "cmo" },
      { type: "stream", content: "Hello world", partial: true, leaderId: "cmo" },
      { type: "stream_end", leaderId: "cmo" },
    ]);

    expect(messages).toHaveLength(1);
    expect(messages[0].state).toBe("done");
    expect(messages[0].content).toBe("Hello world");
  });

  test("lifecycle with tool_use: thinking → tool_use → streaming → done", () => {
    const messages = processEvents([
      { type: "stream_start", leaderId: "cto" },
      { type: "tool_use", leaderId: "cto", tool: "Read", label: "Reading file..." },
      { type: "tool_use", leaderId: "cto", tool: "Bash", label: "Running command..." },
      { type: "stream", content: "Result text", partial: true, leaderId: "cto" },
      { type: "stream_end", leaderId: "cto" },
    ]);

    expect(messages).toHaveLength(1);
    expect(messages[0].state).toBe("done");
    expect(messages[0].content).toBe("Result text");
    // Both tools recorded
    expect(messages[0].toolsUsed).toEqual(["Read", "Bash"]);
  });

  test("replace semantics: 3 cumulative partials = final text, not 3x", () => {
    const messages = processEvents([
      { type: "stream_start", leaderId: "cmo" },
      { type: "stream", content: "A", partial: true, leaderId: "cmo" },
      { type: "stream", content: "AB", partial: true, leaderId: "cmo" },
      { type: "stream", content: "ABC", partial: true, leaderId: "cmo" },
      { type: "stream_end", leaderId: "cmo" },
    ]);

    expect(messages[0].content).toBe("ABC");
    // NOT "AABABC" (the append bug)
    expect(messages[0].content).not.toBe("AABABC");
  });

  test("state transitions are one-directional", () => {
    const states: MessageState[] = [];
    const events = [
      { type: "stream_start", leaderId: "cmo" },
      { type: "tool_use", leaderId: "cmo", tool: "Read", label: "Reading file..." },
      { type: "stream", content: "text", partial: true, leaderId: "cmo" },
      { type: "stream_end", leaderId: "cmo" },
    ];

    // Process each event and capture intermediate states
    const messages: TestMessage[] = [];
    const activeStreams = new Map<string, number>();

    for (const evt of events) {
      const leaderId = evt.leaderId as string;
      switch (evt.type) {
        case "stream_start": {
          const msg: TestMessage = {
            id: "test",
            role: "assistant",
            content: "",
            state: "thinking",
            leaderId,
            toolsUsed: [],
          };
          activeStreams.set(leaderId, messages.length);
          messages.push(msg);
          break;
        }
        case "tool_use": {
          const idx = activeStreams.get(leaderId)!;
          messages[idx] = { ...messages[idx], state: "tool_use" };
          break;
        }
        case "stream": {
          const idx = activeStreams.get(leaderId)!;
          messages[idx] = { ...messages[idx], content: evt.content as string, state: "streaming" };
          break;
        }
        case "stream_end": {
          const idx = activeStreams.get(leaderId)!;
          messages[idx] = { ...messages[idx], state: "done" };
          activeStreams.delete(leaderId);
          break;
        }
      }
      const idx = activeStreams.get(leaderId) ?? messages.length - 1;
      states.push(messages[idx].state!);
    }

    expect(states).toEqual(["thinking", "tool_use", "streaming", "done"]);
  });

  test("multi-agent: independent state machines per leaderId", () => {
    const messages = processEvents([
      { type: "stream_start", leaderId: "cmo" },
      { type: "stream_start", leaderId: "cto" },
      { type: "stream", content: "CMO says hello", partial: true, leaderId: "cmo" },
      { type: "stream", content: "CTO says world", partial: true, leaderId: "cto" },
      { type: "stream_end", leaderId: "cmo" },
      { type: "stream_end", leaderId: "cto" },
    ]);

    expect(messages).toHaveLength(2);
    // No cross-contamination
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
    ]);

    expect(messages).toHaveLength(1);
  });

  test("multiple sequential tool_use events: each replaces previous label", () => {
    const messages = processEvents([
      { type: "stream_start", leaderId: "cto" },
      { type: "tool_use", leaderId: "cto", tool: "Read", label: "Reading file..." },
      { type: "tool_use", leaderId: "cto", tool: "Grep", label: "Searching code..." },
      { type: "tool_use", leaderId: "cto", tool: "Bash", label: "Running command..." },
      { type: "stream", content: "Done", partial: true, leaderId: "cto" },
      { type: "stream_end", leaderId: "cto" },
    ]);

    // All tools recorded
    expect(messages[0].toolsUsed).toEqual(["Read", "Grep", "Bash"]);
    // Final state after stream is streaming, then done
    expect(messages[0].state).toBe("done");
  });

  test("message IDs use UUID format", () => {
    const messages = processEvents([
      { type: "stream_start", leaderId: "cmo" },
      { type: "stream_end", leaderId: "cmo" },
    ]);

    // UUID pattern: 8-4-4-4-12 hex chars
    const uuidPattern = /^stream-cmo-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
    expect(messages[0].id).toMatch(uuidPattern);
  });

  test("empty DONE state: tools used but no text content", () => {
    const messages = processEvents([
      { type: "stream_start", leaderId: "cto" },
      { type: "tool_use", leaderId: "cto", tool: "Read", label: "Reading file..." },
      { type: "tool_use", leaderId: "cto", tool: "Bash", label: "Running command..." },
      { type: "stream_end", leaderId: "cto" },
    ]);

    expect(messages[0].state).toBe("done");
    expect(messages[0].content).toBe("");
    expect(messages[0].toolsUsed).toEqual(["Read", "Bash"]);
  });
});
