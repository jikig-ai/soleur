import { describe, it, expect } from "vitest";
import {
  applyStreamEvent,
  applyTimeout,
  type ChatMessage,
  type WorkflowLifecycleState,
  type SpawnIndex,
} from "@/lib/chat-state-machine";
import type { DomainLeaderId } from "@/server/domain-leaders";

// #5214 — consumer-contract guards for the cc-surface `tool_progress` forward.
//
// NOT RED for the forwarding defect. The `chat-state-machine.ts` consumer
// (line 490 `case "tool_progress"` + `applyTimeout`) is ALREADY complete and
// is UNCHANGED by this fix (AC10). These tests run against the unchanged
// reducer and are GREEN both before and after — their value is
// regression-locking the consumer contract the new server forward feeds, so a
// future `chat-state-machine.ts` refactor cannot silently break the heartbeat
// path. The RED coverage of the actual bug (cc-dispatcher not forwarding)
// lives in `cc-dispatcher-tool-progress-forwarding.test.ts` (server #1 + #2).
//
// Pure reducer drive (no JSX) — mirrors `chat-state-machine.test.ts`; the
// `cc-soleur-go-end-to-end-render.test.tsx` `replay()` shape, minus render.

interface ReducerState {
  messages: ChatMessage[];
  activeStreams: Map<DomainLeaderId, number>;
  workflow: WorkflowLifecycleState;
  spawnIndex: SpawnIndex;
}

function emptyState(): ReducerState {
  return {
    messages: [],
    activeStreams: new Map(),
    workflow: { state: "idle" },
    spawnIndex: new Map(),
  };
}

type StreamEventArg = Parameters<typeof applyStreamEvent>[2];

function applyEvent(state: ReducerState, ev: StreamEventArg): ReducerState {
  const r = applyStreamEvent(
    state.messages,
    state.activeStreams,
    ev,
    state.spawnIndex,
    state.workflow,
  );
  return {
    messages: r.messages,
    activeStreams: r.activeStreams,
    workflow: r.workflow,
    spawnIndex: r.spawnIndex,
  };
}

function applyTimeoutTo(state: ReducerState, leaderId: DomainLeaderId): ReducerState {
  const r = applyTimeout(state.messages, state.activeStreams, leaderId);
  return { ...state, messages: r.messages, activeStreams: r.activeStreams };
}

const CC: DomainLeaderId = "cc_router" as DomainLeaderId;

function streamStart(): StreamEventArg {
  return { type: "stream_start", leaderId: CC, source: "auto" } as StreamEventArg;
}
function toolUse(): StreamEventArg {
  return { type: "tool_use", leaderId: CC, label: "Reading file..." } as StreamEventArg;
}
function toolProgress(elapsedSeconds: number): StreamEventArg {
  return {
    type: "tool_progress",
    leaderId: CC,
    toolUseId: "tu-1",
    toolName: "Reading file...",
    elapsedSeconds,
  } as StreamEventArg;
}

describe("cc-soleur-go tool_progress consumer-contract (no terminal-error on >90s tool)", () => {
  // Test #5 — a >90s single tool that emits `tool_progress` does NOT flip the
  // cc_router bubble to terminal `error`, because the heartbeat resets the
  // consecutive-timeout counter (clears `retrying`). Without the forward, the
  // second timeout would reach `applyTimeout` stage-2 and evict the leader.
  it("Test #5: heartbeat between two timeouts prevents the terminal-error flip + eviction", () => {
    let state = applyEvent(emptyState(), streamStart());
    state = applyEvent(state, toolUse());
    const idx = state.activeStreams.get(CC)!;
    expect(state.messages[idx].state).toBe("tool_use");

    // First 45s timeout → retrying (bubble stays active).
    state = applyTimeoutTo(state, CC);
    expect(state.messages[idx].retrying).toBe(true);

    // A `tool_progress` heartbeat arrives (tool still alive) → clears retrying.
    state = applyEvent(state, toolProgress(50));
    expect(state.messages[idx].retrying).toBeUndefined();

    // The NEXT timeout is therefore a FIRST timeout again (retrying was
    // cleared) — it must NOT flip to terminal error or evict the leader.
    state = applyTimeoutTo(state, CC);
    expect(state.messages[idx].state).not.toBe("error");
    expect(state.activeStreams.has(CC)).toBe(true);
  });

  // Test #6 — distinct contribution: the first-timeout `retrying: true` flag
  // is CLEARED by a `tool_progress` event. (The "no chip spawn on
  // tool_progress" half is already covered by
  // `cc-soleur-go-end-to-end-render.test.tsx:176-187` — not duplicated.)
  it("Test #6: tool_progress clears the first-timeout retrying flag", () => {
    let state = applyEvent(emptyState(), streamStart());
    state = applyEvent(state, toolUse());
    const idx = state.activeStreams.get(CC)!;

    state = applyTimeoutTo(state, CC);
    expect(state.messages[idx].retrying).toBe(true);

    state = applyEvent(state, toolProgress(46));
    expect(state.messages[idx].retrying).toBeUndefined();
    // Bubble stays active — heartbeat does not terminate or evict.
    expect(state.messages[idx].state).not.toBe("error");
    expect(state.activeStreams.has(CC)).toBe(true);
  });

  // Test #7 — control / regression-preserving: a tool that emits NO
  // `tool_progress` and times out twice STILL flips to terminal `error` and
  // evicts the leader. Proves the fix does not relax genuine-failure
  // detection (defense-pair).
  it("Test #7: NO heartbeat → two timeouts still flip to terminal error + evict", () => {
    let state = applyEvent(emptyState(), streamStart());
    state = applyEvent(state, toolUse());
    const idx = state.activeStreams.get(CC)!;

    // First timeout → retrying.
    state = applyTimeoutTo(state, CC);
    expect(state.messages[idx].retrying).toBe(true);

    // Second consecutive timeout (no heartbeat cleared retrying) → terminal.
    state = applyTimeoutTo(state, CC);
    expect(state.messages[idx].state).toBe("error");
    expect(state.activeStreams.has(CC)).toBe(false);
  });

  // Residual 2026-07-16: after Stage-2 eviction, a late `tool_progress` must
  // rebind the error bubble so the red banner does not stick while tools live.
  it("Test #8: tool_progress after Stage-2 error heals orphan red banner", () => {
    let state = applyEvent(emptyState(), streamStart());
    state = applyEvent(state, toolUse());
    const idx = state.activeStreams.get(CC)!;

    state = applyTimeoutTo(state, CC);
    state = applyTimeoutTo(state, CC);
    expect(state.messages[idx].state).toBe("error");
    expect(state.activeStreams.has(CC)).toBe(false);

    state = applyEvent(state, toolProgress(95));
    expect(state.messages[idx].state).not.toBe("error");
    expect(state.messages[idx].state).toBe("tool_use");
    expect(state.activeStreams.has(CC)).toBe(true);
  });
});
