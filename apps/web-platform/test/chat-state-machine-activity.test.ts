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
    const { messages: out, folded } = foldNarrationIntoTrail(
      msgs,
      streams([[CC, "stream-cc_router-1"]]),
      "Routing to drain-prs — this is triage of open pull requests",
      1234,
    );
    expect(folded).toBe(true);
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
    const { messages: out, folded } = foldNarrationIntoTrail(
      msgs,
      new Map(),
      null,
      null,
    );
    expect(out).toBe(msgs);
    expect(folded).toBe(false);
  });

  test("turn-end fold lands on the just-terminalized bubble (final step kept)", () => {
    const done: ChatMessage[] = [
      liveBubble(CC, { state: "done" }),
    ];
    const { messages: out, folded } = foldNarrationIntoTrail(
      done,
      new Map(),
      "final narration",
      null,
    );
    expect(folded).toBe(true);
    expect((out[0] as any).activity[0].label).toBe("final narration");
  });
});

// ─────────────────────────────────────────────────────────────────────────
// #9515 review fixes — stop-semantics + turn-boundary barriers.
// The panel's convergent P1s: (a) `enter_stopping` left the leader registered
// AND rebindable, so frames racing in behind the abort resurrected a
// contradictory Working+Interrupted box; (b) the rebind scan crossed user
// messages, so the NEXT turn's first frame resumed a dead bubble above the
// question that prompted it.
// ─────────────────────────────────────────────────────────────────────────

describe("stop semantics — no Working resurrection (review P1)", () => {
  test("enter_stopping marks bubbles stopped (non-rebindable) + clears the map", () => {
    // enter_stopping lives in ws-client's reducer; assert the SWEEP contract:
    // `stopped` is the non-rebindable variant of interrupted.
    const swept = sweepTransitional(
      [liveBubble(CC, { state: "streaming" })],
      { stopped: true },
    );
    const m = swept[0] as any;
    expect(m.interrupted).toBe(true);
    expect(m.stopped).toBe(true);
    expect(m.state).toBeUndefined();
  });

  test("a stopped bubble is NOT a rebind target — late tool_use goes to the chip path", () => {
    const swept = sweepTransitional([liveBubble()], { stopped: true });
    const r = applyStreamEvent(swept, new Map(), {
      type: "tool_use",
      leaderId: CC,
      label: "Late step",
    } as any);
    // The old bubble stays stopped…
    expect((r.messages[0] as any).stopped).toBe(true);
    expect((r.messages[0] as any).state).toBeUndefined();
    // …and the late frame lands as a chip, never resurrecting the box.
    expect(
      r.messages.some((m) => m.type === "tool_use_chip"),
    ).toBe(true);
  });

  test("a stopped bubble is NOT a rebind target — late stream opens a fresh box", () => {
    const swept = sweepTransitional([liveBubble()], { stopped: true });
    const r = applyStreamEvent(swept, new Map(), {
      type: "stream",
      leaderId: CC,
      content: "resuming text",
      partial: true,
    } as any);
    const texts = r.messages.filter((m) => m.type === "text");
    expect(texts).toHaveLength(2);
    expect((texts[0] as any).stopped).toBe(true);
    expect((texts[1] as any).state).toBe("streaming");
  });
});

describe("turn-boundary barrier — rebind never crosses a user message", () => {
  test("interrupted bubble + user message + resuming frame → new bubble, no rebind", () => {
    const swept = sweepTransitional([liveBubble()]); // rebindable interrupted
    const withUser = [
      ...swept,
      {
        id: "user-2",
        role: "user",
        content: "next question",
        type: "text",
      } as ChatMessage,
    ];
    const r = applyStreamEvent(withUser, new Map(), {
      type: "stream",
      leaderId: CC,
      content: "answer",
      partial: true,
    } as any);
    // The swept bubble stays interrupted (NOT rebound above the question).
    expect((r.messages[0] as any).interrupted).toBe(true);
    expect((r.messages[0] as any).state).toBeUndefined();
    // The new turn's output lands in a NEW bubble AFTER the user message.
    const texts = r.messages.filter((m) => m.type === "text" && m.role === "assistant");
    expect(texts).toHaveLength(2);
    expect((texts[1] as any).state).toBe("streaming");
    expect((texts[1] as any).content).toBe("answer");
  });

  test("foldNarrationIntoTrail never folds across a user message", () => {
    const swept = sweepTransitional([liveBubble()]);
    const withUser = [
      ...swept,
      {
        id: "user-2",
        role: "user",
        content: "next question",
        type: "text",
      } as ChatMessage,
    ];
    const { folded, messages } = foldNarrationIntoTrail(
      withUser,
      new Map(),
      "late narration",
      null,
    );
    expect(folded).toBe(false);
    expect((messages[0] as any).activity?.some((e: any) => e.kind === "narration")).toBeFalsy();
  });

  test("findRecoverableErrorBubble also stops at a user message", () => {
    const prev = [
      liveBubble(CC, { state: "error" }),
      {
        id: "user-2",
        role: "user",
        content: "next question",
        type: "text",
      } as ChatMessage,
    ];
    const r = applyStreamEvent(prev, new Map(), {
      type: "stream",
      leaderId: CC,
      content: "answer",
      partial: true,
    } as any);
    const texts = r.messages.filter((m) => m.type === "text" && m.role === "assistant");
    // The error bubble keeps its banner; the answer lands in a NEW bubble.
    expect((texts[0] as any).state).toBe("error");
    expect((texts[1] as any).state).toBe("streaming");
  });
});

describe("idx-path interrupted strip (review F2 belt)", () => {
  test("a streaming write onto an interrupted-flag bubble clears the flag", () => {
    // Construct the unreachable-but-defended shape: interrupted bubble that
    // is STILL registered in activeStreams (pre-fix enter_stopping left it).
    const bub = liveBubble(CC, { interrupted: true });
    const r = applyStreamEvent([bub], streams([[CC, "stream-cc_router-1"]]), {
      type: "stream",
      leaderId: CC,
      content: "more",
      partial: true,
    } as any);
    expect((r.messages[0] as any).state).toBe("streaming");
    expect((r.messages[0] as any).interrupted).toBe(false);
  });
});

// ─────────────────────────────────────────────────────────────────────────
// Reasoning accumulation — a `stream` event REPLACES the bubble content per
// text block (W8). When the new content is NOT a continuation of the old, the
// prior block's first line folds into the trail so reasoning ADDS UP instead
// of being silently overwritten (the debug stream was append-only; the box
// was replace-only). Operator report 2026-10-05.
// ─────────────────────────────────────────────────────────────────────────

describe("reasoning blocks fold into the trail on replace", () => {
  test("a new (non-prefix) text block folds the old first line into activity", () => {
    const prev = [
      liveBubble(CC, {
        state: "streaming",
        content: "Workspace is ready. Routing to one-shot…",
      }),
    ];
    const r = applyStreamEvent(prev, streams([[CC, "stream-cc_router-1"]]), {
      type: "stream",
      leaderId: CC,
      content: "Checking the two surfaces now.",
      partial: true,
    } as any);
    const m = r.messages[0] as any;
    expect(m.content).toBe("Checking the two surfaces now.");
    expect(
      m.activity?.some(
        (e: any) =>
          e.kind === "narration" &&
          e.label === "Workspace is ready. Routing to one-shot…",
      ),
    ).toBe(true);
  });

  test("a cumulative partial (prefix) does NOT fold — still the same block", () => {
    const prev = [
      liveBubble(CC, { state: "streaming", content: "Workspace is ready" }),
    ];
    const r = applyStreamEvent(prev, streams([[CC, "stream-cc_router-1"]]), {
      type: "stream",
      leaderId: CC,
      content: "Workspace is ready. Routing to one-shot…",
      partial: true,
    } as any);
    const m = r.messages[0] as any;
    expect(m.content).toContain("Routing to one-shot");
    expect(m.activity?.some((e: any) => e.kind === "narration")).toBeFalsy();
  });

  test("multi-line blocks fold only the first non-empty line", () => {
    const prev = [
      liveBubble(CC, {
        state: "streaming",
        content: "\n\nTriaged the open PRs and changed nothing.\nDetails follow…",
      }),
    ];
    const r = applyStreamEvent(prev, streams([[CC, "stream-cc_router-1"]]), {
      type: "stream",
      leaderId: CC,
      content: "New block",
      partial: true,
    } as any);
    const m = r.messages[0] as any;
    expect(m.activity?.[m.activity.length - 1]?.label).toBe(
      "Triaged the open PRs and changed nothing.",
    );
  });

  test("empty prior content folds nothing", () => {
    const prev = [liveBubble(CC, { state: "streaming", content: "" })];
    const r = applyStreamEvent(prev, streams([[CC, "stream-cc_router-1"]]), {
      type: "stream",
      leaderId: CC,
      content: "First real block",
      partial: true,
    } as any);
    // The fixture's toolLabel still folds (tool kind) — only the empty TEXT
    // block must produce nothing.
    const acts = (r.messages[0] as any).activity ?? [];
    expect(acts.filter((e: any) => e.kind === "narration")).toHaveLength(0);
  });
});
