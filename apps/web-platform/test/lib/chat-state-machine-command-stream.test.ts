/**
 * AC5 — reducer append for the `command_stream` event sequence.
 *
 * A Bash tool-use produces an ordered `command_stream` sequence
 * (start → output → output → end) that the reducer APPENDS into the active
 * cc_router text bubble as `commandBlocks` (output APPENDS to the matching
 * block; it does NOT REPLACE bubble text). Interleaving with `stream` text
 * preserves order. Mirrors the cc_router special-casing of `stream`/
 * `stream_end` (chat-state-machine.ts).
 */
import { describe, test, expect } from "vitest";
import {
  applyStreamEvent,
  type ChatMessage,
  type StreamEvent,
} from "../../lib/chat-state-machine";
import type { DomainLeaderId } from "../../server/domain-leaders";

const CC: DomainLeaderId = "cc_router";

function startBubble(): {
  messages: ChatMessage[];
  activeStreams: Map<DomainLeaderId, number>;
} {
  const r = applyStreamEvent([], new Map(), {
    type: "stream_start",
    leaderId: CC,
  } as StreamEvent);
  return { messages: r.messages, activeStreams: r.activeStreams };
}

describe("command_stream reducer (AC5)", () => {
  test("start → output → end appends a single command block to the cc_router bubble", () => {
    let { messages, activeStreams } = startBubble();

    const seq: StreamEvent[] = [
      { type: "command_stream", leaderId: CC, phase: "start", command: "git status" },
      { type: "command_stream", leaderId: CC, phase: "output", output: "On branch main\n" },
      { type: "command_stream", leaderId: CC, phase: "output", output: "nothing to commit\n" },
      { type: "command_stream", leaderId: CC, phase: "end" },
    ];
    for (const ev of seq) {
      const r = applyStreamEvent(messages, activeStreams, ev);
      messages = r.messages;
      activeStreams = r.activeStreams;
    }

    const bubble = messages.find((m) => m.type === "text" && m.leaderId === CC);
    expect(bubble).toBeDefined();
    if (bubble?.type !== "text") throw new Error("expected text bubble");
    expect(bubble.commandBlocks).toHaveLength(1);
    expect(bubble.commandBlocks?.[0].command).toBe("git status");
    // Output APPENDED in order, not replaced.
    expect(bubble.commandBlocks?.[0].output).toBe("On branch main\nnothing to commit\n");
  });

  test("two commands produce two ordered blocks", () => {
    let { messages, activeStreams } = startBubble();
    const seq: StreamEvent[] = [
      { type: "command_stream", leaderId: CC, phase: "start", command: "ls" },
      { type: "command_stream", leaderId: CC, phase: "output", output: "a.txt\n" },
      { type: "command_stream", leaderId: CC, phase: "end" },
      { type: "command_stream", leaderId: CC, phase: "start", command: "pwd" },
      { type: "command_stream", leaderId: CC, phase: "output", output: "/tmp\n" },
      { type: "command_stream", leaderId: CC, phase: "end" },
    ];
    for (const ev of seq) {
      const r = applyStreamEvent(messages, activeStreams, ev);
      messages = r.messages;
      activeStreams = r.activeStreams;
    }
    const bubble = messages.find((m) => m.type === "text" && m.leaderId === CC);
    if (bubble?.type !== "text") throw new Error("expected text bubble");
    expect(bubble.commandBlocks?.map((b) => b.command)).toEqual(["ls", "pwd"]);
    expect(bubble.commandBlocks?.[1].output).toBe("/tmp\n");
  });

  test("truncated flag propagates from an output chunk", () => {
    let { messages, activeStreams } = startBubble();
    const seq: StreamEvent[] = [
      { type: "command_stream", leaderId: CC, phase: "start", command: "cat big" },
      { type: "command_stream", leaderId: CC, phase: "output", output: "x".repeat(10), truncated: true },
      { type: "command_stream", leaderId: CC, phase: "end" },
    ];
    for (const ev of seq) {
      const r = applyStreamEvent(messages, activeStreams, ev);
      messages = r.messages;
      activeStreams = r.activeStreams;
    }
    const bubble = messages.find((m) => m.type === "text" && m.leaderId === CC);
    if (bubble?.type !== "text") throw new Error("expected text bubble");
    expect(bubble.commandBlocks?.[0].truncated).toBe(true);
  });

  test("interleaving with `stream` text preserves both surfaces on the same bubble", () => {
    let { messages, activeStreams } = startBubble();
    const seq: StreamEvent[] = [
      { type: "command_stream", leaderId: CC, phase: "start", command: "echo hi" },
      { type: "stream", leaderId: CC, content: "Running a command…", partial: true },
      { type: "command_stream", leaderId: CC, phase: "output", output: "hi\n" },
      { type: "command_stream", leaderId: CC, phase: "end" },
    ];
    for (const ev of seq) {
      const r = applyStreamEvent(messages, activeStreams, ev);
      messages = r.messages;
      activeStreams = r.activeStreams;
    }
    const bubble = messages.find((m) => m.type === "text" && m.leaderId === CC);
    if (bubble?.type !== "text") throw new Error("expected text bubble");
    // Bubble text reflects the `stream` snapshot; the command block coexists.
    expect(bubble.content).toBe("Running a command…");
    expect(bubble.commandBlocks?.[0].command).toBe("echo hi");
    expect(bubble.commandBlocks?.[0].output).toBe("hi\n");
  });

  test("command_stream with no prior stream bubble creates a bubble (no missed start)", () => {
    const r = applyStreamEvent([], new Map(), {
      type: "command_stream",
      leaderId: CC,
      phase: "start",
      command: "git status",
    } as StreamEvent);
    const bubble = r.messages.find((m) => m.type === "text" && m.leaderId === CC);
    expect(bubble).toBeDefined();
    if (bubble?.type !== "text") throw new Error("expected text bubble");
    expect(bubble.commandBlocks?.[0].command).toBe("git status");
  });
});

describe("command_stream toolUseId correlation (FIX 2 — concurrent Bash)", () => {
  // When one assistant turn emits TWO Bash tool-uses (start A, start B, then
  // interleaved results), output keyed to A must land on block A and output
  // keyed to B on block B — NOT both on the last block. Mirrors the
  // subagent_complete id-lookup precedent.
  test("start A → start B → output A → output B routes output to the correct block", () => {
    let { messages, activeStreams } = startBubble();
    const seq: StreamEvent[] = [
      { type: "command_stream", leaderId: CC, phase: "start", command: "cmd-A", toolUseId: "a" },
      { type: "command_stream", leaderId: CC, phase: "start", command: "cmd-B", toolUseId: "b" },
      { type: "command_stream", leaderId: CC, phase: "output", output: "OUTPUT-A\n", toolUseId: "a" },
      { type: "command_stream", leaderId: CC, phase: "output", output: "OUTPUT-B\n", toolUseId: "b" },
      { type: "command_stream", leaderId: CC, phase: "end", toolUseId: "a" },
      { type: "command_stream", leaderId: CC, phase: "end", toolUseId: "b" },
    ];
    for (const ev of seq) {
      const r = applyStreamEvent(messages, activeStreams, ev);
      messages = r.messages;
      activeStreams = r.activeStreams;
    }
    const bubble = messages.find((m) => m.type === "text" && m.leaderId === CC);
    if (bubble?.type !== "text") throw new Error("expected text bubble");
    const blockA = bubble.commandBlocks?.find((b) => b.command === "cmd-A");
    const blockB = bubble.commandBlocks?.find((b) => b.command === "cmd-B");
    expect(blockA?.output).toBe("OUTPUT-A\n");
    expect(blockB?.output).toBe("OUTPUT-B\n");
  });

  test("absent toolUseId falls back to last-block append (back-compat)", () => {
    let { messages, activeStreams } = startBubble();
    const seq: StreamEvent[] = [
      { type: "command_stream", leaderId: CC, phase: "start", command: "no-id" },
      { type: "command_stream", leaderId: CC, phase: "output", output: "tail\n" },
    ];
    for (const ev of seq) {
      const r = applyStreamEvent(messages, activeStreams, ev);
      messages = r.messages;
      activeStreams = r.activeStreams;
    }
    const bubble = messages.find((m) => m.type === "text" && m.leaderId === CC);
    if (bubble?.type !== "text") throw new Error("expected text bubble");
    expect(bubble.commandBlocks?.[0].output).toBe("tail\n");
  });
});

describe("command_stream block cap (FIX 3)", () => {
  test("commandBlocks is capped with a leading truncation marker when exceeded", () => {
    let { messages, activeStreams } = startBubble();
    // Push well over the cap (100) of start blocks.
    for (let i = 0; i < 130; i++) {
      const r = applyStreamEvent(messages, activeStreams, {
        type: "command_stream",
        leaderId: CC,
        phase: "start",
        command: `cmd-${i}`,
        toolUseId: `t-${i}`,
      } as StreamEvent);
      messages = r.messages;
      activeStreams = r.activeStreams;
    }
    const bubble = messages.find((m) => m.type === "text" && m.leaderId === CC);
    if (bubble?.type !== "text") throw new Error("expected text bubble");
    expect(bubble.commandBlocks!.length).toBeLessThanOrEqual(100);
    // Oldest dropped, newest retained.
    expect(bubble.commandBlocks?.[0].command).toContain("truncated");
    expect(
      bubble.commandBlocks?.[bubble.commandBlocks!.length - 1].command,
    ).toBe("cmd-129");
  });
});
