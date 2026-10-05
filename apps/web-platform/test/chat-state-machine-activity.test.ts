import { describe, test, expect } from "vitest";
import {
  applyStreamEvent,
  foldNarrationIntoTrail,
  sweepTransitional,
  pushActivity,
  MAX_ACTIVITY_ENTRIES,
  type ChatMessage,
} from "../lib/chat-state-machine";
import type { DomainLeaderId } from "../server/domain-leaders";

const CC = "cc_router" as DomainLeaderId;

// feat-concierge-activity-trail (#9515) — the in-turn activity trail:
// prior steps accumulate on the bubble (session-only), the current step is
// toolLabel/liveNarration, and reconnect-interrupted bubbles REBIND instead
// of stacking a second Working box.

function chip(label: string, at = 1000): ChatMessage {
  return {
    id: `chip-${label}`,
    role: "assistant",
    content: "",
    type: "tool_use_chip",
    toolName: label,
    toolLabel: label,
    leaderId: "cc_router",
    at,
  } as ChatMessage;
}

function liveBubble(leaderId: DomainLeaderId = CC, extra: Partial<ChatMessage> = {}): ChatMessage {
  return {
    id: `stream-${leaderId}-1`,
    role: "assistant",
    content: "partial",
    type: "text",
    leaderId,
    state: "tool_use",
    toolLabel: "Reading a file",
    toolsUsed: ["Reading a file"],
    ...extra,
  } as ChatMessage;
}

const streams = (entries: [DomainLeaderId, string][]): Map<DomainLeaderId, string> =>
  new Map(entries);

describe("activity trail — superseded-step append", () => {
  test("tool_use pushes the prior toolLabel into activity with tool kind", () => {
    const prev = [liveBubble()];
    const r = applyStreamEvent(prev, streams([[CC, "stream-cc_router-1"]]), {
      type: "tool_use",
      leaderId: CC,
      label: "Searching the web",
    } as any);
    const m = r.messages[0] as any;
    expect(m.toolLabel).toBe("Searching the web");
    expect(m.activity).toHaveLength(1);
    expect(m.activity[0]).toMatchObject({ label: "Reading a file", kind: "tool" });
    expect(m.currentActivityStartedAt).toBeTypeOf("number");
  });

  test("first tool_use on a label-less bubble pushes nothing", () => {
    const prev = [liveBubble(CC, { toolLabel: undefined })];
    const r = applyStreamEvent(prev, streams([[CC, "stream-cc_router-1"]]), {
      type: "tool_use",
      leaderId: CC,
      label: "First step",
    } as any);
    expect((r.messages[0] as any).activity).toBeUndefined();
    expect((r.messages[0] as any).toolLabel).toBe("First step");
  });

  test("consecutive identical labels dedup (pushActivity)", () => {
    const list = pushActivity(undefined, { label: "Same", kind: "tool", startedAt: 1 });
    const again = pushActivity(list, { label: "Same", kind: "tool", startedAt: 2 });
    expect(again).toHaveLength(1);
    expect(again[0].startedAt).toBe(1); // original kept
    const different = pushActivity(again, { label: "Other", kind: "tool", startedAt: 3 });
    expect(different).toHaveLength(2);
  });

  test("activity is bounded at MAX_ACTIVITY_ENTRIES", () => {
    let list = undefined;
    for (let i = 0; i < MAX_ACTIVITY_ENTRIES + 5; i++) {
      list = pushActivity(list, { label: `step-${i}`, kind: "tool", startedAt: i });
    }
    expect(list).toHaveLength(MAX_ACTIVITY_ENTRIES);
    expect(list![list!.length - 1].label).toBe(`step-${MAX_ACTIVITY_ENTRIES + 4}`);
    expect(list![0].label).toBe(`step-5`); // oldest evicted
  });

  test("stream_end folds the final toolLabel into activity", () => {
    const prev = [liveBubble()];
    const r = applyStreamEvent(prev, streams([[CC, "stream-cc_router-1"]]), {
      type: "stream_end",
      leaderId: CC,
    } as any);
    const m = r.messages[0] as any;
    expect(m.state).toBe("done");
    expect(m.toolLabel).toBeUndefined();
    expect(m.activity).toHaveLength(1);
    expect(m.activity[0].label).toBe("Reading a file");
  });
});

describe("activity trail — chip seeding", () => {
  test("first stream prunes chips AND seeds their labels into the new bubble", () => {
    const prev: ChatMessage[] = [
      { id: "u1", role: "user", content: "hi", type: "text" } as ChatMessage,
      chip("Triage open pull requests", 1000),
      chip("Check CI status", 2000),
    ];
    const r = applyStreamEvent(prev, new Map(), {
      type: "stream",
      leaderId: CC,
      content: "Here is the triage…",
    } as any);
    expect(r.messages.filter((m) => m.type === "tool_use_chip")).toHaveLength(0);
    const bubble = r.messages[r.messages.length - 1] as any;
    expect(bubble.type).toBe("text");
    expect(bubble.activity).toHaveLength(2);
    expect(bubble.activity[0]).toMatchObject({
      label: "Triage open pull requests",
      kind: "tool",
      startedAt: 1000,
    });
    expect(bubble.activity[1].label).toBe("Check CI status");
  });

  test("command_stream creation seeds chips the same way", () => {
    const prev: ChatMessage[] = [chip("Running a check", 500)];
    const r = applyStreamEvent(prev, new Map(), {
      type: "command_stream",
      leaderId: CC,
      phase: "start",
      command: "echo hi",
    } as any);
    const bubble = r.messages[r.messages.length - 1] as any;
    expect(bubble.activity).toHaveLength(1);
    expect(bubble.activity[0].label).toBe("Running a check");
  });
});

describe("interrupted sweep + rebind", () => {
  test("sweepTransitional marks live bubbles interrupted and folds the current step", () => {
    const next = sweepTransitional([liveBubble()]);
    const m = next[0] as any;
    expect(m.state).toBeUndefined();
    expect(m.interrupted).toBe(true);
    expect(m.retrying).toBeUndefined();
    expect(m.activity).toHaveLength(1);
    expect(m.activity[0].label).toBe("Reading a file");
    expect(m.toolLabel).toBeUndefined();
  });

  test("sweep leaves done/user/non-text messages untouched", () => {
    const prev: ChatMessage[] = [
      { id: "u1", role: "user", content: "hi", type: "text" } as ChatMessage,
      liveBubble(CC, { state: "done" }),
      chip("x"),
    ];
    const next = sweepTransitional(prev);
    expect((next[0] as any).interrupted).toBeUndefined();
    expect((next[1] as any).state).toBe("done");
    expect((next[2] as any).interrupted).toBeUndefined();
  });

  test("resuming tool_use rebinds the interrupted bubble — ONE box, no chip", () => {
    const swept = sweepTransitional([liveBubble()]);
    const r = applyStreamEvent(swept, new Map(), {
      type: "tool_use",
      leaderId: CC,
      label: "Checking CI",
    } as any);
    expect(r.messages).toHaveLength(1); // no new bubble, no chip
    const m = r.messages[0] as any;
    expect(m.interrupted).toBeUndefined();
    expect(m.state).toBe("tool_use");
    expect(m.toolLabel).toBe("Checking CI");
    // trail continued: swept step + nothing lost
    expect(m.activity.map((a: any) => a.label)).toEqual(["Reading a file"]);
    expect(r.activeStreams.get(CC)).toBe(m.id);
  });

  test("resuming stream rebinds the same bubble (id preserved)", () => {
    const swept = sweepTransitional([liveBubble(CC, { state: "streaming", toolLabel: undefined })]);
    const r = applyStreamEvent(swept, new Map(), {
      type: "stream",
      leaderId: CC,
      content: "resumed content",
    } as any);
    const m = r.messages[0] as any;
    expect(r.messages).toHaveLength(1);
    expect(m.id).toBe("stream-cc_router-1");
    expect(m.state).toBe("streaming");
    expect(m.content).toBe("resumed content");
    expect(m.interrupted).toBeUndefined();
  });

  test("stream_end on an interrupted bubble terminalizes honestly (done, no Working)", () => {
    const swept = sweepTransitional([liveBubble()]);
    const r = applyStreamEvent(swept, new Map(), {
      type: "stream_end",
      leaderId: CC,
    } as any);
    const m = r.messages[0] as any;
    expect(m.state).toBe("done");
    expect(m.interrupted).toBeUndefined();
    // swept step stays — toolLabel was already folded+cleared by the sweep,
    // so stream_end has nothing left to push (no duplicate entry).
    expect(m.activity).toHaveLength(1);
    expect(m.activity[0].label).toBe("Reading a file");
  });

  test("hydrated rows (state:undefined, NO interrupted flag) are never rebound", () => {
    const hydrated: ChatMessage[] = [
      { id: "db-1", role: "assistant", content: "old answer", type: "text", leaderId: CC } as ChatMessage,
    ];
    const r = applyStreamEvent(hydrated, new Map(), {
      type: "stream",
      leaderId: CC,
      content: "new stream",
    } as any);
    // Fresh bubble appended — the hydrated row is untouched, one Working box only
    expect(r.messages).toHaveLength(2);
    expect((r.messages[0] as any).content).toBe("old answer");
    expect((r.messages[0] as any).state).toBeUndefined();
    expect((r.messages[1] as any).content).toBe("new stream");
  });
});

describe("id-keyed activeStreams — corruption regressions", () => {
  test("filter_prepend-style shift cannot corrupt a stream's target bubble", () => {
    const live = liveBubble(CC, { state: "streaming" });
    const prev: ChatMessage[] = [
      { id: "old-1", role: "user", content: "older", type: "text" } as ChatMessage,
      { id: "old-2", role: "assistant", content: "older", type: "text" } as ChatMessage,
      live,
    ];
    // activeStreams stores the bubble's ID — the prepended rows don't shift it.
    const r = applyStreamEvent(prev, streams([[CC, live.id]]), {
      type: "stream",
      leaderId: CC,
      content: "current",
    } as any);
    expect((r.messages[2] as any).content).toBe("current");
    expect((r.messages[0] as any).content).toBe("older");
    expect((r.messages[1] as any).content).toBe("older");
  });

  test("chip prune for leader A cannot stamp leader B's frame onto a shifted row", () => {
    // The verified cross-leader corruption: A's chips get pruned while B
    // streams; an index-keyed map would land B's content on the WRONG row.
    const bubbleB = liveBubble("cpo" as DomainLeaderId, { state: "streaming" });
    const prev: ChatMessage[] = [
      chip("A chip", 100), // index 0 — pruned for leader A
      bubbleB,             // was index 1 → becomes index 0 after prune
    ];
    // B's stream arrives carrying B's content while A's chip is still listed.
    const r = applyStreamEvent(prev, streams([["cpo" as DomainLeaderId, bubbleB.id]]), {
      type: "stream",
      leaderId: "cpo" as DomainLeaderId,
      content: "B says this",
    } as any);
    const b = r.messages.find((m) => m.id === bubbleB.id) as any;
    expect(b.content).toBe("B says this");
    // A's chip untouched (prune is per-leader).
    expect(r.messages.some((m) => m.type === "tool_use_chip")).toBe(true);
  });
});

describe("foldNarrationIntoTrail", () => {
  test("narration folds into the sole active stream's bubble", () => {
    const msgs = [liveBubble()];
    const out = foldNarrationIntoTrail(
      msgs,
      streams([[CC, "stream-cc_router-1"]]),
      "Routing to drain-prs — this is triage of open pull requests",
      1234,
    );
    const m = out[0] as any;
    expect(m.activity).toHaveLength(1);
    expect(m.activity[0]).toMatchObject({
      label: "Routing to drain-prs — this is triage of open pull requests",
      kind: "narration",
      startedAt: 1234,
    });
  });

  test("null narration returns messages unchanged", () => {
    const msgs = [liveBubble()];
    expect(foldNarrationIntoTrail(msgs, new Map(), null, null)).toBe(msgs);
  });

  test("no live-ish bubble → narration dropped (never a finished record)", () => {
    const done: ChatMessage[] = [
      liveBubble(CC, { state: "done" }),
    ];
    const out = foldNarrationIntoTrail(done, new Map(), "late narration", null);
    expect((out[0] as any).activity).toBeUndefined();
  });
});
