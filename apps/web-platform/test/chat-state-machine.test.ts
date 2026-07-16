import { describe, test, expect } from "vitest";
import { applyStreamEvent, applyTimeout, MAX_LIVENESS_REARMS } from "../lib/chat-state-machine";
import type { ChatMessage } from "../lib/chat-state-machine";
import type { DomainLeaderId } from "../server/domain-leaders";

// Helper: produce a `Map<DomainLeaderId, number>` from string-keyed test
// fixtures so individual tests don't need to spell the typed-Map ctor each
// time. Stage 3 (#2885) tightened `activeStreams` to `Map<DomainLeaderId,
// number>`; tests pass arbitrary opaque keys (incl. "ghost") that the
// reducer treats as inert no-ops.
function makeStreams(entries: [string, number][] = []): Map<DomainLeaderId, number> {
  return new Map(entries as [DomainLeaderId, number][]);
}

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
    const streams = makeStreams([["cpo", 0]]);

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
    const streams = makeStreams([["cpo", 0]]);

    const result = applyStreamEvent(prev, streams, {
      type: "stream",
      leaderId: "cpo" as any,
      content: "Hello",
    } as any);

    expect(result.timerAction).toEqual({ type: "reset", leaderId: "cpo" });
  });

  test("stream_start event resets the timer", () => {
    const result = applyStreamEvent([], makeStreams(), {
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
    const streams = makeStreams([["cpo", 0]]);

    const result = applyTimeout(prev, streams, "cpo");

    expect(result.messages[0].state).toBe("error");
    expect(result.activeStreams.has("cpo")).toBe(false);
  });

  test("applyTimeout: second consecutive timeout on tool_use bubble transitions to error", () => {
    const msg: ChatMessage = { ...thinkingMessage("cpo"), state: "tool_use", retrying: true };
    const prev: ChatMessage[] = [msg];
    const streams = makeStreams([["cpo", 0]]);

    const result = applyTimeout(prev, streams, "cpo");

    expect(result.messages[0].state).toBe("error");
  });

  test("applyTimeout does NOT affect streaming bubble", () => {
    const msg: ChatMessage = { ...thinkingMessage("cpo"), state: "streaming" };
    const prev: ChatMessage[] = [msg];
    const streams = makeStreams([["cpo", 0]]);

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
    const streams = makeStreams([["cpo", 0], ["cto", 1]]);

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
    const streams = makeStreams([["cpo", 0], ["cto", 1]]);

    const result = applyStreamEvent(prev, streams, reviewGateEvent("g2", "Continue?"));

    expect(result.messages[0].state).toBe("done");
    expect(result.messages[1].state).toBe("done");
  });

  test("review_gate leaves already-done bubbles untouched", () => {
    const doneBubble: ChatMessage = { ...thinkingMessage("cpo"), state: "done", content: "Final answer" };
    const prev: ChatMessage[] = [doneBubble];
    // Empty activeStreams — done bubble already transitioned out
    const streams = new Map<DomainLeaderId, number>();

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
    const streams = makeStreams([["cpo", 0], ["coo", 3]]);

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
    const streams = makeStreams([["cpo", 0], ["ghost", 42]]);

    const result = applyStreamEvent(prev, streams, reviewGateEvent("g5"));

    expect(result.messages[0].state).toBe("done");
    expect(result.messages[1].type).toBe("review_gate");
    expect(result.activeStreams.size).toBe(0);
  });

  test("stream_end on single leader transitions to done (regression sentinel)", () => {
    const prev: ChatMessage[] = [thinkingMessage("cpo")];
    const streams = makeStreams([["cpo", 0]]);

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
    const streams = makeStreams([["cpo", 0], ["cto", 1]]);

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
    const streams = makeStreams([["cpo", 0]]);

    const result = applyStreamEvent(prev, streams, toolProgressEvent("cpo" as any) as any);

    // Messages array reference is preserved (no mutation in the hot path).
    expect(result.messages).toBe(prev);
    expect(result.timerAction).toEqual({ type: "reset", leaderId: "cpo" });
  });

  test("tool_progress for unknown leader is an inert no-op", () => {
    const prev: ChatMessage[] = [thinkingMessage("cpo")];
    const streams = makeStreams([["cpo", 0]]);

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
    const streams = makeStreams([["cpo", 0]]);

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
    const streams = makeStreams([["cpo", 0]]);

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
    const streams = makeStreams([["cpo", 0]]);

    const result = applyTimeout(prev, streams, "cpo");

    expect(result.messages[0].state).toBe("error");
    expect(result.messages[0].retrying).toBeUndefined();
    expect(result.messages[0].toolLabel).toBe("Searching code");
    expect(result.activeStreams.has("cpo")).toBe(false);
    expect(result.timerAction).toEqual({ type: "clear", leaderId: "cpo" });
  });

  test("first applyTimeout on thinking bubble (no toolLabel) also flags retrying", () => {
    const prev: ChatMessage[] = [thinkingMessage("cpo")];
    const streams = makeStreams([["cpo", 0]]);

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
    const streams = new Map<DomainLeaderId, number>();

    const result = applyTimeout([errorBubble], streams, "cpo");

    expect(result.messages[0].state).toBe("error");
    expect(result.messages[0].retrying).toBeUndefined();
  });
});

describe("chat-state-machine STUCK_TIMEOUT_MS constant", () => {
  // Review F19 (#2886): the constant was extracted to `lib/ws-constants.ts`
  // (a leaf module without React imports), so the test now imports it
  // directly instead of grepping the source file with `fs`.
  test("timeout constant is 45000ms", async () => {
    const { STUCK_TIMEOUT_MS } = await import("../lib/ws-constants");
    expect(STUCK_TIMEOUT_MS).toBe(45_000);
  });
});

// ---------------------------------------------------------------------------
// Stage 4 (#2886): the new event types now produce real ChatMessage variants.
// Stage 3 had them as inert pass-throughs; Stage 4 materializes them.
// ---------------------------------------------------------------------------

describe("Stage 4 — new ChatMessage variants from /soleur:go events", () => {
  function makeContext() {
    const prev: ChatMessage[] = [thinkingMessage("cmo")];
    const streams = new Map<DomainLeaderId, number>([["cmo" as DomainLeaderId, 0]]);
    return { prev, streams };
  }

  test("subagent_spawn (no matching parentId) starts a new subagent_group message", () => {
    const { prev, streams } = makeContext();
    const result = applyStreamEvent(prev, streams, {
      type: "subagent_spawn",
      parentId: "p-1",
      leaderId: "cto" as any,
      spawnId: "s-1",
      task: "Audit performance",
    } as any);
    // Original message preserved; new subagent_group appended.
    expect(result.messages.length).toBe(prev.length + 1);
    const group = result.messages[result.messages.length - 1];
    expect(group.type).toBe("subagent_group");
    if (group.type === "subagent_group") {
      expect(group.parentSpawnId).toBe("p-1");
      expect(group.parentLeaderId).toBe("cto");
      expect(group.children.length).toBe(1);
      expect(group.children[0].spawnId).toBe("s-1");
      expect(group.children[0].leaderId).toBe("cto");
      expect(group.children[0].task).toBe("Audit performance");
      expect(group.children[0].status).toBeUndefined();
    }
    // spawnIndex should now know about s-1.
    expect(result.spawnIndex.get("s-1")).toEqual({
      messageIdx: prev.length,
      childIdx: 0,
    });
  });

  test("second subagent_spawn with matching parentId appends to existing group", () => {
    const { prev, streams } = makeContext();
    const r1 = applyStreamEvent(prev, streams, {
      type: "subagent_spawn",
      parentId: "p-1",
      leaderId: "cto" as any,
      spawnId: "s-1",
      task: "Audit performance",
    } as any);
    const r2 = applyStreamEvent(r1.messages, r1.activeStreams, {
      type: "subagent_spawn",
      parentId: "p-1",
      leaderId: "cmo" as any,
      spawnId: "s-2",
      task: "Audit copy",
    } as any, r1.spawnIndex);
    const group = r2.messages[r2.messages.length - 1];
    expect(group.type).toBe("subagent_group");
    if (group.type === "subagent_group") {
      expect(group.children.length).toBe(2);
      expect(group.children[1].spawnId).toBe("s-2");
      expect(group.children[1].leaderId).toBe("cmo");
    }
    expect(r2.spawnIndex.get("s-2")).toEqual({
      messageIdx: prev.length,
      childIdx: 1,
    });
  });

  test("subagent_complete reverse-looks up via spawnIndex and mutates only the matching child", () => {
    const { prev, streams } = makeContext();
    const r1 = applyStreamEvent(prev, streams, {
      type: "subagent_spawn",
      parentId: "p-1",
      leaderId: "cto" as any,
      spawnId: "s-1",
    } as any);
    const r2 = applyStreamEvent(r1.messages, r1.activeStreams, {
      type: "subagent_spawn",
      parentId: "p-1",
      leaderId: "cmo" as any,
      spawnId: "s-2",
    } as any, r1.spawnIndex);
    const r3 = applyStreamEvent(r2.messages, r2.activeStreams, {
      type: "subagent_spawn",
      parentId: "p-1",
      leaderId: "cfo" as any,
      spawnId: "s-3",
    } as any, r2.spawnIndex);

    // Complete the second spawn only.
    const r4 = applyStreamEvent(r3.messages, r3.activeStreams, {
      type: "subagent_complete",
      spawnId: "s-2",
      status: "success",
    } as any, r3.spawnIndex);
    const group = r4.messages[r4.messages.length - 1];
    expect(group.type).toBe("subagent_group");
    if (group.type === "subagent_group") {
      expect(group.children[0].status).toBeUndefined();
      expect(group.children[1].status).toBe("success");
      expect(group.children[2].status).toBeUndefined();
    }
  });

  test("interactive_prompt pushes a ChatInteractivePromptMessage keyed by (promptId, conversationId)", () => {
    const { prev, streams } = makeContext();
    const result = applyStreamEvent(prev, streams, {
      type: "interactive_prompt",
      promptId: "pr-1",
      conversationId: "c-1",
      kind: "ask_user",
      payload: { question: "Q?", options: ["a", "b"], multiSelect: false },
    } as any);
    expect(result.messages.length).toBe(prev.length + 1);
    const card = result.messages[result.messages.length - 1];
    expect(card.type).toBe("interactive_prompt");
    if (card.type === "interactive_prompt") {
      expect(card.promptId).toBe("pr-1");
      expect(card.conversationId).toBe("c-1");
      expect(card.promptKind).toBe("ask_user");
      expect(card.resolved).toBeUndefined();
    }
  });

  test("workflow_started sets ambient workflow slice but creates NO message", () => {
    const { prev, streams } = makeContext();
    const result = applyStreamEvent(prev, streams, {
      type: "workflow_started",
      workflow: "brainstorm",
      conversationId: "c-1",
    } as any);
    // No new message.
    expect(result.messages.length).toBe(prev.length);
    expect(result.workflow.state).toBe("active");
    if (result.workflow.state === "active") {
      expect(result.workflow.workflow).toBe("brainstorm");
    }
  });

  test("workflow_ended sets ambient slice AND pushes a ChatWorkflowEndedMessage", () => {
    const { prev, streams } = makeContext();
    const result = applyStreamEvent(prev, streams, {
      type: "workflow_ended",
      workflow: "plan",
      status: "completed",
      summary: "Plan finalized",
    } as any);
    expect(result.workflow.state).toBe("ended");
    expect(result.messages.length).toBe(prev.length + 1);
    const ended = result.messages[result.messages.length - 1];
    expect(ended.type).toBe("workflow_ended");
    if (ended.type === "workflow_ended") {
      expect(ended.workflow).toBe("plan");
      expect(ended.status).toBe("completed");
      expect(ended.summary).toBe("Plan finalized");
    }
  });

  test("tool_use with leaderId cc_router emits a ChatToolUseChipMessage chip", () => {
    const result = applyStreamEvent([], new Map(), {
      type: "tool_use",
      leaderId: "cc_router" as any,
      label: "Routing via /soleur:go",
    } as any);
    expect(result.messages.length).toBe(1);
    const chip = result.messages[0];
    expect(chip.type).toBe("tool_use_chip");
    if (chip.type === "tool_use_chip") {
      expect(chip.toolLabel).toBe("Routing via /soleur:go");
      expect(chip.leaderId).toBe("cc_router");
    }
  });

  test("tool_use with leaderId system emits a ChatToolUseChipMessage chip", () => {
    const result = applyStreamEvent([], new Map(), {
      type: "tool_use",
      leaderId: "system" as any,
      label: "System dispatch",
    } as any);
    const chip = result.messages[0];
    expect(chip.type).toBe("tool_use_chip");
  });

  test("tool_progress does NOT create a chip (regression test for heartbeat-vs-start distinction)", () => {
    const result = applyStreamEvent([], new Map(), {
      type: "tool_progress",
      leaderId: "cc_router" as any,
      toolUseId: "tu-1",
      toolName: "Skill",
      elapsedSeconds: 5,
    } as any);
    expect(result.messages.length).toBe(0);
  });

  test("stream event for cc_router leader removes existing chips for that leader", () => {
    // First emit a chip via tool_use.
    const r1 = applyStreamEvent([], new Map(), {
      type: "tool_use",
      leaderId: "cc_router" as any,
      label: "Routing",
    } as any);
    expect(r1.messages.length).toBe(1);
    // Now stream first content for cc_router — chip should be gone.
    const r2 = applyStreamEvent(r1.messages, r1.activeStreams, {
      type: "stream",
      leaderId: "cc_router" as any,
      content: "Hello",
    } as any);
    // No chip in the result (it was removed); a stream bubble may be added.
    const chips = r2.messages.filter((m) => m.type === "tool_use_chip");
    expect(chips.length).toBe(0);
  });

  test("workflow_started removes all chips", () => {
    // Emit two chips.
    const r1 = applyStreamEvent([], new Map(), {
      type: "tool_use",
      leaderId: "cc_router" as any,
      label: "Routing 1",
    } as any);
    const r2 = applyStreamEvent(r1.messages, r1.activeStreams, {
      type: "tool_use",
      leaderId: "system" as any,
      label: "System span",
    } as any);
    expect(r2.messages.filter((m) => m.type === "tool_use_chip").length).toBe(2);
    const r3 = applyStreamEvent(r2.messages, r2.activeStreams, {
      type: "workflow_started",
      workflow: "brainstorm",
      conversationId: "c-1",
    } as any);
    expect(r3.messages.filter((m) => m.type === "tool_use_chip").length).toBe(0);
  });

  // ------------------------------------------------------------------------
  // Review fix tests (PR #2925 review)
  // ------------------------------------------------------------------------

  test("F2: subagent_complete resolves correctly even after filter_prepend shifts indices", () => {
    // Reproduces the scenario where history backfill (filter_prepend) inserts
    // older messages BEFORE the existing subagent_group, invalidating any
    // absolute index stored in the original spawnIndex. The id-based lookup
    // must still find the right child.
    const r1 = applyStreamEvent([], new Map(), {
      type: "subagent_spawn",
      parentId: "p-1",
      leaderId: "cto" as any,
      spawnId: "s-1",
    } as any);
    expect(r1.messages.length).toBe(1);
    // Simulate filter_prepend by manually prepending two unrelated messages.
    const shiftedMessages: ChatMessage[] = [
      { id: "history-1", role: "user", content: "hi", type: "text" },
      { id: "history-2", role: "assistant", content: "hello", type: "text" },
      ...r1.messages,
    ];
    // Pass a *stale* spawnIndex (still pointing at messageIdx 0) — the
    // post-fix reducer ignores it and scans by spawnId.
    const r2 = applyStreamEvent(shiftedMessages, r1.activeStreams, {
      type: "subagent_complete",
      spawnId: "s-1",
      status: "success",
    } as any, r1.spawnIndex);
    const group = r2.messages.find((m) => m.type === "subagent_group");
    expect(group?.type).toBe("subagent_group");
    if (group?.type === "subagent_group") {
      expect(group.children[0].status).toBe("success");
    }
  });

  test("F4: cc_router/system tool_use chips are capped at 5 latest per leader", () => {
    let messages: ChatMessage[] = [];
    for (let i = 0; i < 7; i++) {
      const r = applyStreamEvent(messages, new Map(), {
        type: "tool_use",
        leaderId: "cc_router" as any,
        label: `Routing ${i}`,
      } as any);
      messages = r.messages;
    }
    const chips = messages.filter((m) => m.type === "tool_use_chip");
    expect(chips.length).toBe(5);
    // Oldest chips ("Routing 0", "Routing 1") were evicted; newest survive.
    if (chips[0].type === "tool_use_chip") {
      expect(chips[0].toolLabel).toBe("Routing 2");
    }
    if (chips[chips.length - 1].type === "tool_use_chip") {
      expect(chips[chips.length - 1].toolLabel).toBe("Routing 6");
    }
  });

  test("F7: duplicate interactive_prompt event is idempotent (no second card)", () => {
    const event = {
      type: "interactive_prompt",
      promptId: "pr-dup",
      conversationId: "c-1",
      kind: "ask_user",
      payload: { question: "Q?", options: ["a"], multiSelect: false },
    } as any;
    const r1 = applyStreamEvent([], new Map(), event);
    const r2 = applyStreamEvent(r1.messages, r1.activeStreams, event);
    const cards = r2.messages.filter((m) => m.type === "interactive_prompt");
    expect(cards.length).toBe(1);
    // Same reference → reducer returned the prior `messages` slice unchanged.
    expect(r2.messages).toBe(r1.messages);
  });

  test("F8: tool_use(cc_router) → stream → tool_use(cc_router) does NOT re-emit a chip", () => {
    // After `stream` creates a text bubble for cc_router, a subsequent
    // tool_use must update the bubble's toolLabel (regular per-leader path)
    // instead of appending a fresh chip.
    const r1 = applyStreamEvent([], new Map(), {
      type: "tool_use",
      leaderId: "cc_router" as any,
      label: "Routing 1",
    } as any);
    const r2 = applyStreamEvent(r1.messages, r1.activeStreams, {
      type: "stream",
      leaderId: "cc_router" as any,
      content: "Hello",
    } as any);
    // After stream, no chips remain; one text bubble exists.
    expect(r2.messages.filter((m) => m.type === "tool_use_chip").length).toBe(0);
    expect(r2.activeStreams.has("cc_router" as any)).toBe(true);
    // Now another tool_use for cc_router — must NOT append a chip.
    const r3 = applyStreamEvent(r2.messages, r2.activeStreams, {
      type: "tool_use",
      leaderId: "cc_router" as any,
      label: "Routing 2",
    } as any);
    expect(r3.messages.filter((m) => m.type === "tool_use_chip").length).toBe(0);
    // The text bubble's toolLabel was updated.
    const bubble = r3.messages.find((m) => m.type === "text" && m.leaderId === "cc_router");
    expect(bubble?.type).toBe("text");
    if (bubble?.type === "text") {
      expect(bubble.toolLabel).toBe("Routing 2");
    }
  });

  test("F11: stream_end on cc_router/system removes any lingering chips for that leader", () => {
    // tool_use creates a chip but no stream content arrives; stream_end
    // must still clean up the chip — otherwise it leaks permanently.
    const r1 = applyStreamEvent([], new Map(), {
      type: "tool_use",
      leaderId: "cc_router" as any,
      label: "Routing",
    } as any);
    expect(r1.messages.filter((m) => m.type === "tool_use_chip").length).toBe(1);
    const r2 = applyStreamEvent(r1.messages, r1.activeStreams, {
      type: "stream_end",
      leaderId: "cc_router" as any,
    } as any);
    expect(r2.messages.filter((m) => m.type === "tool_use_chip").length).toBe(0);
  });

  test("activeStreams is keyed by DomainLeaderId (Map<DomainLeaderId, number>)", () => {
    // After Stage 3, the StreamEventResult and the reducer hold a typed key.
    // This test exercises the typed boundary by minting a key via `as DomainLeaderId`
    // and asserting the reducer carries it forward without coercion.
    const streams: Map<DomainLeaderId, number> = new Map();
    const result = applyStreamEvent([], streams, {
      type: "stream_start",
      leaderId: "cmo" as DomainLeaderId,
    } as any);
    // The post-state Map type narrows to Map<DomainLeaderId, number>; if the
    // signature regressed to Map<string, number> the test still passes at
    // runtime. The compile-time gate is `tsc --noEmit` from apps/web-platform.
    expect(result.activeStreams.size).toBe(1);
    expect(result.activeStreams.has("cmo" as DomainLeaderId)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// #3775 — subagent_spawn idempotency on duplicate spawnId
// ---------------------------------------------------------------------------

describe("subagent_spawn idempotency (#3775)", () => {
  test("duplicate spawnId returns prev unchanged (no second child appended)", () => {
    const r1 = applyStreamEvent([], new Map(), {
      type: "subagent_spawn",
      parentId: "p-dup",
      leaderId: "cto" as DomainLeaderId,
      spawnId: "s-dup-1",
      task: "first",
    } as any);
    // Second call with the same spawnId — should be idempotent.
    const r2 = applyStreamEvent(r1.messages, r1.activeStreams, {
      type: "subagent_spawn",
      parentId: "p-dup",
      leaderId: "cto" as DomainLeaderId,
      spawnId: "s-dup-1",
      task: "second",
    } as any, r1.spawnIndex);
    expect(r2.messages).toBe(r1.messages);
    expect(r2.spawnIndex).toBe(r1.spawnIndex);
    const group = r2.messages[r2.messages.length - 1];
    expect(group.type).toBe("subagent_group");
    if (group.type === "subagent_group") {
      expect(group.children.length).toBe(1);
      // First-write-wins: original task preserved.
      expect(group.children[0].task).toBe("first");
    }
  });

  test("different spawnIds still append normally (regression guard)", () => {
    const r1 = applyStreamEvent([], new Map(), {
      type: "subagent_spawn",
      parentId: "p-multi",
      leaderId: "cto" as DomainLeaderId,
      spawnId: "s-multi-1",
    } as any);
    const r2 = applyStreamEvent(r1.messages, r1.activeStreams, {
      type: "subagent_spawn",
      parentId: "p-multi",
      leaderId: "cmo" as DomainLeaderId,
      spawnId: "s-multi-2",
    } as any, r1.spawnIndex);
    const group = r2.messages[r2.messages.length - 1];
    expect(group.type).toBe("subagent_group");
    if (group.type === "subagent_group") {
      expect(group.children.length).toBe(2);
    }
  });
});

// ---------------------------------------------------------------------------
// #5240 (sub-issue) — leader-liveness watchdog reset.
//
// The per-message stuck-watchdog escalated a bubble to `error` ("Agent stopped
// responding after: <label>") even though the LEADER was provably alive — the
// Debug stream was still emitting tool events (screenshot 1) and/or a SIBLING
// leader was still streaming below the errored bubble (screenshot 2). The fix
// widens the liveness INPUT set without widening what the error MEANS:
//   - a debug `tool_use` heartbeat resets the watchdog when exactly ONE leader
//     is active (unambiguous attribution) → `reset_all`;
//   - a Stage-2 timeout is BOUNDED-suppressed while ANOTHER leader is active,
//     up to MAX_LIVENESS_REARMS, then escalates regardless (genuine-hang exit
//     preserved even under a perpetually-busy sibling).
// ---------------------------------------------------------------------------

function toolUseMessage(leaderId: string, extra: Partial<ChatMessage> = {}): ChatMessage {
  return {
    id: `stream-${leaderId}-1`,
    role: "assistant",
    content: "",
    type: "text",
    leaderId: leaderId as any,
    state: "tool_use",
    toolLabel: "Reading file...",
    toolsUsed: ["Reading file..."],
    ...extra,
  } as ChatMessage;
}

function debugToolUse(): any {
  return { type: "debug_event", kind: "tool_use", body: "Running command..." };
}

describe("#5240 leader-liveness watchdog reset", () => {
  test("AC1: single-leader debug tool_use heartbeat → reset_all + clears retrying + livenessRearms 0", () => {
    // One active leader, Stage-1 retrying. A live debug tool_use proves the sole
    // leader is alive → reset every armed timer, clear the stale chip.
    const prev: ChatMessage[] = [
      toolUseMessage("cpo", { retrying: true, livenessRearms: 2 }),
    ];
    const streams = makeStreams([["cpo", 0]]);

    const result = applyStreamEvent(prev, streams, debugToolUse());

    expect(result.timerAction).toEqual({ type: "reset_all" });
    expect(result.messages[0].retrying).toBeUndefined();
    expect(result.messages[0].livenessRearms).toBe(0);
    // The debug message is still appended (panel log unchanged).
    expect(result.messages[result.messages.length - 1].type).toBe("debug_event");
  });

  test("AC2: cross-leader Stage-2 suppressed (pinned reset, leaderId) while sibling active", () => {
    const prev: ChatMessage[] = [
      toolUseMessage("cpo", { retrying: true }),
      toolUseMessage("cto"),
    ];
    const streams = makeStreams([["cpo", 0], ["cto", 1]]);

    const result = applyTimeout(prev, streams, "cpo");

    expect(result.messages[0].state).toBe("tool_use");
    expect(result.activeStreams.has("cpo" as DomainLeaderId)).toBe(true);
    expect(result.messages[0].retrying).toBe(true);
    expect(result.messages[0].livenessRearms).toBe(1);
    // Pinned: re-arm THIS leader only — never reset_all, never undefined.
    expect(result.timerAction).toEqual({ type: "reset", leaderId: "cpo" });
  });

  test("AC2-streaming: a sibling in `streaming` state (not tool_use) also grants the bounded grace", () => {
    // `siblingActive` accepts thinking|tool_use|streaming. AC2 covers tool_use;
    // this exercises the `streaming` disjunct so dropping it would go red.
    const prev: ChatMessage[] = [
      toolUseMessage("cpo", { retrying: true }),
      toolUseMessage("cto", { state: "streaming" }),
    ];
    const streams = makeStreams([["cpo", 0], ["cto", 1]]);

    const result = applyTimeout(prev, streams, "cpo");

    expect(result.messages[0].state).toBe("tool_use");
    expect(result.messages[0].livenessRearms).toBe(1);
    expect(result.timerAction).toEqual({ type: "reset", leaderId: "cpo" });
  });

  test("AC1-thinking: debug heartbeat clears retrying on a sole `thinking` bubble too", () => {
    const prev: ChatMessage[] = [
      toolUseMessage("cpo", { state: "thinking", retrying: true, livenessRearms: 1 }),
    ];
    const streams = makeStreams([["cpo", 0]]);

    const result = applyStreamEvent(prev, streams, debugToolUse());

    expect(result.timerAction).toEqual({ type: "reset_all" });
    expect(result.messages[0].retrying).toBeUndefined();
    expect(result.messages[0].livenessRearms).toBe(0);
  });

  test("AC3: genuine hang — sole active leader still escalates to error (bracketed against AC2)", () => {
    // Same retrying bubble as AC2, but with NO sibling active → must escalate.
    const prev: ChatMessage[] = [toolUseMessage("cpo", { retrying: true })];
    const streams = makeStreams([["cpo", 0]]);

    const result = applyTimeout(prev, streams, "cpo");

    expect(result.messages[0].state).toBe("error");
    expect(result.activeStreams.has("cpo" as DomainLeaderId)).toBe(false);
  });

  test("AC3b: bounded re-arm un-masks a hung leader after MAX even with sibling always active", () => {
    let messages: ChatMessage[] = [
      toolUseMessage("cpo", { retrying: true }),
      toolUseMessage("cto"),
    ];
    const streams = makeStreams([["cpo", 0], ["cto", 1]]);

    for (let call = 1; call <= MAX_LIVENESS_REARMS; call++) {
      const r = applyTimeout(messages, streams, "cpo");
      expect(r.messages[0].state).toBe("tool_use");
      expect(r.messages[0].livenessRearms).toBe(call);
      messages = r.messages;
    }
    // (MAX+1)-th timeout — budget exhausted → escalate despite cto active.
    const final = applyTimeout(messages, streams, "cpo");
    expect(final.messages[0].state).toBe("error");
    expect(final.activeStreams.has("cpo" as DomainLeaderId)).toBe(false);
  });

  test("AC3c: re-armed leader escalates once the sibling goes silent (transient, not permanent)", () => {
    const seed: ChatMessage[] = [
      toolUseMessage("cpo", { retrying: true }),
      toolUseMessage("cto"),
    ];
    const both = makeStreams([["cpo", 0], ["cto", 1]]);
    const rearmed = applyTimeout(seed, both, "cpo");
    expect(rearmed.messages[0].state).toBe("tool_use");

    // cto goes silent (removed from activeStreams) → cpo is now last.
    const onlyCpo = makeStreams([["cpo", 0]]);
    const escalated = applyTimeout(rearmed.messages, onlyCpo, "cpo");
    expect(escalated.messages[0].state).toBe("error");
    expect(escalated.activeStreams.has("cpo" as DomainLeaderId)).toBe(false);
  });

  test("AC7a: debug tool_use with NO active leader is inert (no timerAction)", () => {
    const result = applyStreamEvent([], makeStreams(), debugToolUse());
    expect(result.timerAction).toBeUndefined();
  });

  test("AC7b: debug tool_use with TWO active leaders does NOT reset_all (unattributable)", () => {
    const prev: ChatMessage[] = [
      toolUseMessage("cpo", { retrying: true }),
      toolUseMessage("cto"),
    ];
    const streams = makeStreams([["cpo", 0], ["cto", 1]]);
    const result = applyStreamEvent(prev, streams, debugToolUse());
    expect(result.timerAction).toBeUndefined();
  });

  test("AC7c: debug reasoning/result never reset_all (ceiling kept tight)", () => {
    const prev: ChatMessage[] = [toolUseMessage("cpo", { retrying: true })];
    const streams = makeStreams([["cpo", 0]]);
    for (const kind of ["reasoning", "result"] as const) {
      const result = applyStreamEvent(prev, streams, {
        type: "debug_event",
        kind,
        body: "x",
      } as any);
      expect(result.timerAction).toBeUndefined();
    }
  });

  test("AC8b: debug heartbeat does not resurrect a terminal bubble", () => {
    // Sole active leader's bubble is already `error` but transiently still in
    // activeStreams. reset_all may re-arm its timer, but a follow-up timeout
    // no-ops (transitional-state guard) — no resurrection.
    const prev: ChatMessage[] = [toolUseMessage("cpo", { state: "error" })];
    const streams = makeStreams([["cpo", 0]]);

    const afterDebug = applyStreamEvent(prev, streams, debugToolUse());
    expect(afterDebug.messages[0].state).toBe("error");

    const afterTimeout = applyTimeout(afterDebug.messages, afterDebug.activeStreams, "cpo");
    expect(afterTimeout.messages[0].state).toBe("error");
  });
});

// ---------------------------------------------------------------------------
// Path A: orphan Stage-2 error recovery (Concierge false mid-run stop)
// Plan: 2026-07-16-fix-concierge-agent-stop-mid-run-plan.md
// ---------------------------------------------------------------------------

describe("chat-state-machine orphan Stage-2 error recovery (Path A)", () => {
  const CC = "cc_router" as DomainLeaderId;

  function stage2ErrorBubble(leaderId: string = CC): ChatMessage {
    return {
      id: `stream-${leaderId}-err`,
      role: "assistant",
      content: "partial",
      type: "text",
      leaderId: leaderId as DomainLeaderId,
      state: "error",
      toolLabel: "Working",
      toolsUsed: ["Bash"],
    };
  }

  test("cc_router tool_use after Stage-2 eviction rebinds error bubble (no permanent orphan)", () => {
    // Dominant residual: after applyTimeout stage 2, cc_router is not in
    // activeStreams and tool_use took the chip-only path — red banner stuck
    // while tools continue.
    const prev: ChatMessage[] = [stage2ErrorBubble()];
    const streams = makeStreams(); // empty — leader was evicted

    const result = applyStreamEvent(prev, streams, {
      type: "tool_use",
      leaderId: CC,
      label: "Running command…",
    } as any);

    expect(result.messages).toHaveLength(1);
    expect(result.messages[0].type).toBe("text");
    expect(result.messages[0].state).toBe("tool_use");
    expect(result.messages[0].toolLabel).toBe("Running command…");
    expect(result.messages[0].retrying).toBeUndefined();
    expect(result.activeStreams.get(CC)).toBe(0);
    expect(result.timerAction).toEqual({ type: "reset", leaderId: CC });
    // Must NOT append a tool_use_chip when recovering.
    expect(result.messages.some((m) => m.type === "tool_use_chip")).toBe(false);
  });

  test("tool_progress after Stage-2 eviction rebinds to non-error + timer reset", () => {
    const prev: ChatMessage[] = [stage2ErrorBubble()];
    const streams = makeStreams();

    const result = applyStreamEvent(prev, streams, {
      type: "tool_progress",
      leaderId: CC,
      toolUseId: "tu-1",
      toolName: "Bash",
      elapsedSeconds: 60,
    } as any);

    expect(result.messages[0].state).toBe("tool_use");
    expect(result.messages[0].state).not.toBe("error");
    expect(result.activeStreams.has(CC)).toBe(true);
    expect(result.timerAction).toEqual({ type: "reset", leaderId: CC });
    expect(result.messages.some((m) => m.type === "tool_use_chip")).toBe(false);
  });

  test("Stage-2 error with no further events stays error (fail-closed)", () => {
    const prev: ChatMessage[] = [stage2ErrorBubble()];
    const streams = makeStreams();

    // No events — bubble remains terminal error; leader stays out of map.
    expect(prev[0].state).toBe("error");
    expect(streams.has(CC)).toBe(false);

    // applyTimeout on an already-evicted leader is a no-op (cannot re-escalate).
    const result = applyTimeout(prev, streams, CC);
    expect(result.messages[0].state).toBe("error");
    expect(result.activeStreams.has(CC)).toBe(false);
  });

  test("command_stream after Stage-2 error rebinds tip (no dual error + streaming)", () => {
    const prev: ChatMessage[] = [stage2ErrorBubble()];
    const streams = makeStreams();

    const result = applyStreamEvent(prev, streams, {
      type: "command_stream",
      leaderId: CC,
      phase: "start",
      command: "grep -n foo",
      toolUseId: "tu-bash-1",
    } as any);

    expect(result.messages).toHaveLength(1);
    expect(result.messages[0].state).toBe("streaming");
    expect(result.messages[0].state).not.toBe("error");
    expect(result.activeStreams.get(CC)).toBe(0);
    expect(result.timerAction).toEqual({ type: "reset", leaderId: CC });
    const blocks = (result.messages[0] as { commandBlocks?: { command: string }[] })
      .commandBlocks;
    expect(blocks?.[0]?.command).toBe("grep -n foo");
  });

  test("stream_start after Stage-2 error rebinds tip to thinking", () => {
    const prev: ChatMessage[] = [stage2ErrorBubble()];
    const streams = makeStreams();

    const result = applyStreamEvent(prev, streams, {
      type: "stream_start",
      leaderId: CC,
    } as any);

    expect(result.messages).toHaveLength(1);
    expect(result.messages[0].state).toBe("thinking");
    expect(result.activeStreams.get(CC)).toBe(0);
    expect(result.timerAction).toEqual({ type: "reset", leaderId: CC });
  });

  test("cold cc_router tool_use without error still spawns chip (preserve Stage 4)", () => {
    // No recoverable error — pre-stream tool_use remains chip behavior.
    const result = applyStreamEvent([], makeStreams(), {
      type: "tool_use",
      leaderId: CC,
      label: "Reading file…",
    } as any);

    expect(result.messages).toHaveLength(1);
    expect(result.messages[0].type).toBe("tool_use_chip");
    expect(result.activeStreams.has(CC)).toBe(false);
    expect(result.timerAction).toBeUndefined();
  });

  test("does not rebind older error when a newer non-error text tip exists", () => {
    const oldError = stage2ErrorBubble();
    const newerLive: ChatMessage = {
      id: "stream-cc_router-new",
      role: "assistant",
      content: "continued",
      type: "text",
      leaderId: CC,
      state: "streaming",
      toolsUsed: [],
    };
    const prev: ChatMessage[] = [oldError, newerLive];
    const streams = makeStreams();

    const result = applyStreamEvent(prev, streams, {
      type: "tool_use",
      leaderId: CC,
      label: "Bash",
    } as any);

    // Newer tip is non-error → chip path (no rebind of old error).
    expect(result.messages.some((m) => m.type === "tool_use_chip")).toBe(true);
    expect(result.messages[0].state).toBe("error");
  });
});

