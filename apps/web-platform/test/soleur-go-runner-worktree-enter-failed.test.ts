import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type { SDKUserMessage } from "@anthropic-ai/claude-agent-sdk";
import {
  createMockQueryScripted as createMockQuery,
  makeAssistant,
  makeRecordingEvents as makeEvents,
  flushMicrotasks,
} from "./helpers/soleur-go-fixtures";

// Mock observability BEFORE importing the runner so `reportSilentFallback`
// resolves to the mock (and doesn't pull pino into the test bundle).
const { mockReportSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

import { createSoleurGoRunner, type WorkflowEnd } from "@/server/soleur-go-runner";

// RED tests for #5313 (deferred #5240 FR-half): the worktree-rebind loop.
// The runner must detect a Bash CWD-verification loop — N=3 consecutive
// near-identical `cd <path> && pwd` commands whose output does NOT equal the
// expected worktree path — and terminate the turn with a `worktree_enter_failed`
// WorkflowEnd (fast, honest), instead of letting the agent loop until the
// 10-min runaway breaker. Detection is COMMAND-PATTERN-DRIVEN off observed Bash
// tool-results (extractBashToolResults), NOT a cooperative agent-emitted marker
// (the agent ignores prose contracts — it ignored "abort").

const WORKTREE = "/workspaces/abc/.worktrees/feat-x";
const VERIFY_CMD = `cd ${WORKTREE} && pwd`;
const WRONG_CWD = "/home/soleur"; // bwrap fell back to $HOME — the bug signature

/** A `tool_result` user message with a settable output string (the observed
 *  `pwd`). Mirrors makeUserToolResult but parameterizes `content`. */
function makeBashResult(toolUseId: string, output: string): SDKUserMessage {
  return {
    type: "user",
    message: {
      role: "user",
      content: [{ type: "tool_result", tool_use_id: toolUseId, content: output }],
      // biome-ignore lint/suspicious/noExplicitAny: minimal SDK fixture
    } as any,
    parent_tool_use_id: null,
    isSynthetic: true,
    tool_use_result: { ok: true },
    session_id: "sess-1",
  } as SDKUserMessage;
}

function bashToolUse(id: string, command: string) {
  return makeAssistant({
    content: [{ type: "tool_use", id, name: "Bash", input: { command } }],
  });
}

async function dispatchRunner(conversationId: string) {
  const mock = createMockQuery();
  const runner = createSoleurGoRunner({
    queryFactory: () => mock.query,
    now: () => Date.now(),
  });
  const events = makeEvents();
  // The runner only records Bash commands into bashToolUses (and runs the
  // CWD-verify detector) when onToolResult is wired — the cc-soleur-go path.
  events.onToolResult = vi.fn();
  await runner.dispatch({
    persona: "command_center",
    conversationId,
    userId: "u1",
    userMessage: "fix issue",
    currentRouting: { kind: "soleur_go_pending" },
    events,
    persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
  });
  return { mock, events };
}

describe("soleur-go-runner — worktree-enter CWD-verify loop guardrail (#5313)", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(0);
    mockReportSilentFallback.mockClear();
  });
  afterEach(() => vi.useRealTimers());

  // AC1: 3 consecutive identical `cd <wt> && pwd` with a mismatched pwd output
  // → fast `worktree_enter_failed` with the diagnostic triple + Sentry mirror.
  it("fires worktree_enter_failed after 3 mismatched CWD-verify commands", async () => {
    const { mock, events } = await dispatchRunner("conv-loop");
    for (let i = 1; i <= 3; i++) {
      mock.emit(bashToolUse(`tu${i}`, VERIFY_CMD));
      await flushMicrotasks();
      mock.emit(makeBashResult(`tu${i}`, WRONG_CWD));
      await flushMicrotasks();
    }
    const end = events._ended.find(
      (e) => (e.status as string) === "worktree_enter_failed",
    ) as (WorkflowEnd & { expectedPath?: string; observedCwd?: string; attempts?: number }) | undefined;
    expect(end).toBeDefined();
    expect(end!.expectedPath).toBe(WORKTREE);
    expect(end!.observedCwd).toBe(WRONG_CWD);
    expect(end!.attempts).toBe(3);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "agent-sandbox", op: "worktree_enter" }),
    );
  });

  // Counter-case: 2 mismatched then a MATCHING pwd resets the counter — no fire.
  it("does NOT fire when the CWD-verify eventually succeeds", async () => {
    const { mock, events } = await dispatchRunner("conv-ok");
    for (let i = 1; i <= 2; i++) {
      mock.emit(bashToolUse(`tu${i}`, VERIFY_CMD));
      await flushMicrotasks();
      mock.emit(makeBashResult(`tu${i}`, WRONG_CWD));
      await flushMicrotasks();
    }
    // Third attempt SUCCEEDS (pwd === expected) → resets the loop counter.
    mock.emit(bashToolUse("tu3", VERIFY_CMD));
    await flushMicrotasks();
    mock.emit(makeBashResult("tu3", WORKTREE));
    await flushMicrotasks();
    expect(
      events._ended.find((e) => (e.status as string) === "worktree_enter_failed"),
    ).toBeUndefined();
  });

  // AC8 (FR2.4 single-terminal invariant): emitting worktree_enter_failed
  // clears both timers (via emitWorkflowEnded -> closeQuery) and sets
  // state.closed, so the armed runner_runaway timer cannot double-fire a
  // second WorkflowEnd. After the loop fires, advancing past the runaway
  // ceiling MUST still yield exactly ONE workflow_ended, and it is the
  // worktree_enter_failed one — not runner_runaway.
  it("does not double-fire runner_runaway after worktree_enter_failed (single terminal)", async () => {
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 10_000,
      maxTurnDurationMs: 30_000,
    });
    const events = makeEvents();
    events.onToolResult = vi.fn();
    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-single",
      userId: "u1",
      userMessage: "fix",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });
    // 3 mismatched verifies arm the timers (first tool_use) AND fire the loop.
    for (let i = 1; i <= 3; i++) {
      mock.emit(bashToolUse(`tu${i}`, VERIFY_CMD));
      await flushMicrotasks();
      mock.emit(makeBashResult(`tu${i}`, WRONG_CWD));
      await flushMicrotasks();
    }
    // Advance well past both the idle window AND the absolute turn ceiling.
    vi.advanceTimersByTime(60_000);
    await flushMicrotasks();
    expect(events._ended).toHaveLength(1);
    expect((events._ended[0].status as string)).toBe("worktree_enter_failed");
  });

  // Non-CWD-verify Bash commands must never trip the detector.
  it("does NOT fire on unrelated repeated Bash commands", async () => {
    const { mock, events } = await dispatchRunner("conv-ls");
    for (let i = 1; i <= 4; i++) {
      mock.emit(bashToolUse(`tu${i}`, "ls -la"));
      await flushMicrotasks();
      mock.emit(makeBashResult(`tu${i}`, "file1\nfile2"));
      await flushMicrotasks();
    }
    expect(
      events._ended.find((e) => (e.status as string) === "worktree_enter_failed"),
    ).toBeUndefined();
  });
});
