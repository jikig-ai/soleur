import {
  describe,
  it,
  expect,
  vi,
  beforeEach,
  afterEach,
} from "vitest";
import type { SDKResultMessage } from "@anthropic-ai/claude-agent-sdk";
import {
  createMockQueryScripted as createMockQuery,
  makeAssistant,
  makeResult,
  makeToolProgress,
  makeRecordingEvents as makeEvents,
  flushMicrotasks,
} from "./helpers/soleur-go-fixtures";

// Mock observability BEFORE importing the runner so the
// `reportSilentFallback` + `mirrorWithDebounce` imports inside
// soleur-go-runner.ts resolve to the mocks and the silent-fallback
// assertion can inspect them. #3040 Finding 2 routes the
// `notifyAwaitingUser` no-active-query branch through
// `mirrorWithDebounce`; older paths still use `reportSilentFallback`.
const { mockReportSilentFallback, mockMirrorWithDebounce } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockMirrorWithDebounce: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
  mirrorWithDebounce: mockMirrorWithDebounce,
  __resetMirrorDebounceForTests: vi.fn(),
  MIRROR_DEBOUNCE_MS: 5 * 60 * 1000,
}));

import {
  createSoleurGoRunner,
  DEFAULT_WALL_CLOCK_TRIGGER_MS,
  DEFAULT_MAX_TURN_DURATION_MS,
  NOTIFY_AWAITING_NO_ACTIVE_QUERY_ERROR_CLASS,
  type WorkflowEnd,
} from "@/server/soleur-go-runner";

// Tests for plan 2026-04-29-fix-command-center-qa-permissions-runaway-rename-plan.md
// + #3040 Finding 4 cumulative-budget rewrite (drift-sweep
// per-window→cumulative narrative).
//
// The runner exposes `notifyAwaitingUser(conversationId, awaiting:
// boolean)`. While `awaiting === true`, the wall-clock runaway timer is
// paused (`clearTimeout`) and `state.pausedAt` is stamped. On resume,
// the just-finished pause interval is accumulated into
// `state.totalPausedMs` and both timers are re-armed; `firstToolUseAt`
// is preserved across pause/resume cycles. The wall-clock trigger and
// the absolute turn ceiling subtract `totalPausedMs + (pausedAt
// ? now() - pausedAt : 0)` from elapsed at fire time so paused
// intervals do not count toward either ceiling. A chatty-flap runaway
// cannot escape either ceiling by interleaving short user prompts with
// heavy compute (#3040 Finding 4).
//
// If the conversationId is unknown, `notifyAwaitingUser` MUST mirror to
// Sentry via `mirrorWithDebounce` (per
// `cq-silent-fallback-must-mirror-to-sentry`; #3040 Finding 2).

describe("soleur-go-runner notifyAwaitingUser pause/resume", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mockReportSilentFallback.mockClear();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("AC8: runaway timer is PAUSED while awaitingUser=true (no fire after 60s); resumes cleanly on result after notify(false)", async () => {
    // Use Date.now() (fake-timer-driven) so `now()` advances when we
    // call `vi.advanceTimersByTime`.
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 30_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-pause",
      userId: "u1",
      userMessage: "do",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // First Bash tool_use arms the wall-clock.
    mock.emit(
      makeAssistant({
        content: [
          { type: "tool_use", id: "t1", name: "Bash", input: { command: "ls" } },
        ],
      }),
    );
    await flushMicrotasks();

    // Pause for user.
    runner.notifyAwaitingUser("conv-pause", true);

    // Advance 60s (well past the 30s threshold). Timer must NOT fire.
    vi.advanceTimersByTime(60_000);
    await flushMicrotasks();
    expect(events._ended.find((e) => e.status === "runner_runaway")).toBeUndefined();

    // Resume + emit terminal result. Workflow should clear cleanly with
    // no runaway emission.
    runner.notifyAwaitingUser("conv-pause", false);
    mock.emit(makeResult(0.1));
    await flushMicrotasks();

    expect(events._ended.find((e) => e.status === "runner_runaway")).toBeUndefined();
  });

  it("AC9 (cumulative): runaway fires on cumulative-active-time threshold across pause/resume — 5s active + 20s paused + 30s active fires at the boundary; paused time deducted at fire (#3040 Finding 4)", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 30_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-resume",
      userId: "u1",
      userMessage: "go",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // First tool_use arms the timer at t=0.
    mock.emit(
      makeAssistant({
        content: [
          { type: "tool_use", id: "t1", name: "Bash", input: { command: "ls" } },
        ],
      }),
    );
    await flushMicrotasks();

    // 5s of agent compute time.
    vi.advanceTimersByTime(5_000);
    await flushMicrotasks();

    // Pause for user.
    runner.notifyAwaitingUser("conv-resume", true);

    // 20s paused (human read time — must not count).
    vi.advanceTimersByTime(20_000);
    await flushMicrotasks();
    expect(events._ended.find((e) => e.status === "runner_runaway")).toBeUndefined();

    // Resume — re-arms both timers; `firstToolUseAt` preserved at 0.
    // `totalPausedMs` now holds the 20s pause interval, which the
    // fire-time recheck subtracts from elapsed.
    runner.notifyAwaitingUser("conv-resume", false);

    // Advance 29.999s post-resume — setTimeout scheduled at t=25s
    // for 30s would fire at t=55s. Under cumulative semantics, at
    // fire time elapsedMs = 55 - 0 (firstToolUseAt) - 20 (totalPausedMs)
    // = 35s. We have not yet hit the wall-clock t=55s, so no fire.
    vi.advanceTimersByTime(29_999);
    await flushMicrotasks();
    expect(events._ended.find((e) => e.status === "runner_runaway")).toBeUndefined();

    // Final 2ms tips us past wall-clock t=55s; the re-armed setTimeout
    // fires, recomputes elapsedMs=35s (≥ 30s threshold), and emits
    // runner_runaway. The 20s of human read time was DEDUCTED at fire
    // time — only the 35s of cumulative active compute counts toward
    // the threshold.
    vi.advanceTimersByTime(2);
    await flushMicrotasks();
    expect(events._ended.find((e) => e.status === "runner_runaway")).toBeDefined();
    expect(mock.closeSpy).toHaveBeenCalled();
  });

  it("AC17: 5-min review-gate safety net — abortableReviewGate rejection → consumeStream catch fires internal_error exactly once; runaway does NOT also fire", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 30_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-safetynet",
      userId: "u1",
      userMessage: "do",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // Bash tool_use arms the timer.
    mock.emit(
      makeAssistant({
        content: [
          { type: "tool_use", id: "t1", name: "Bash", input: { command: "ls" } },
        ],
      }),
    );
    await flushMicrotasks();

    // Status flips to waiting_for_user → pause.
    runner.notifyAwaitingUser("conv-safetynet", true);

    // 5min + 1s elapses without resolution — safety net rejects.
    vi.advanceTimersByTime(5 * 60 * 1000 + 1000);
    await flushMicrotasks();

    // Simulate the SDK promise chain rejecting because canUseTool threw.
    // The rejection lands in consumeStream's `for await` catch block.
    mock.emitError(new Error("review-gate timeout (5min safety net)"));
    await flushMicrotasks(20);

    // (a) Exactly one workflow_ended event with internal_error.
    const internalErrorEnds = events._ended.filter(
      (e) => e.status === "internal_error",
    );
    expect(internalErrorEnds).toHaveLength(1);

    // (b) Runaway timer did NOT fire (we paused at 0s, 5min wall-clock
    // never charged against compute).
    expect(events._ended.find((e) => e.status === "runner_runaway")).toBeUndefined();

    // (c) closed === true (active query removed).
    expect(runner.hasActiveQuery("conv-safetynet")).toBe(false);

    // (d) NO double-emit. workflow_ended fires exactly once total.
    expect(events._ended).toHaveLength(1);
  });

  it("silent-fallback: notifyAwaitingUser on unknown conversationId mirrors via mirrorWithDebounce (#3040 Finding 2)", () => {
    mockMirrorWithDebounce.mockClear();
    const runner = createSoleurGoRunner({
      queryFactory: () => createMockQuery().query,
      now: () => Date.now(),
      wallClockTriggerMs: 30_000,
    });

    runner.notifyAwaitingUser("unknown-conv-id", true);

    const matchingCalls = mockMirrorWithDebounce.mock.calls.filter(
      ([, ctx]) =>
        ctx?.feature === "soleur-go-runner" && ctx?.op === "notifyAwaitingUser",
    );
    expect(matchingCalls).toHaveLength(1);
    const [err, ctx, userId, errorClass] = matchingCalls[0]!;
    expect(err).toBeInstanceOf(Error);
    expect((err as Error).message).toContain("notifyAwaitingUser");
    expect(ctx.extra).toMatchObject({ conversationId: "unknown-conv-id" });
    expect(userId).toBe("unknown");
    expect(errorClass).toBe(NOTIFY_AWAITING_NO_ACTIVE_QUERY_ERROR_CLASS);
  });

  it("AC11 (#3040 Finding 3): reapIdle skips conversations with awaitingUser=true even when lastActivityAt < cutoff", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      idleReapMs: 60_000,
      wallClockTriggerMs: 30_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-reaper-paused",
      userId: "u1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    runner.notifyAwaitingUser("conv-reaper-paused", true);

    // Advance past the idle cutoff while paused — reapIdle MUST NOT
    // close the query because the user is still mid-review.
    vi.advanceTimersByTime(120_000);
    expect(runner.reapIdle()).toBe(0);
    expect(runner.hasActiveQuery("conv-reaper-paused")).toBe(true);

    // After resume, the reaper proceeds normally on the next idle window.
    runner.notifyAwaitingUser("conv-reaper-paused", false);
    vi.advanceTimersByTime(120_000);
    expect(runner.reapIdle()).toBe(1);
    expect(runner.hasActiveQuery("conv-reaper-paused")).toBe(false);
  });

  it("AC12 (#3040 Finding 4): absolute turn-hard-cap subtracts paused intervals — 30s ceiling, 5s active + 20s paused + 25s active fires at the boundary; paused time deducted at fire", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      // Make idle-window large so only the absolute turn-hard-cap can fire.
      wallClockTriggerMs: 10 * 60 * 1000,
      maxTurnDurationMs: 30_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-hardcap",
      userId: "u1",
      userMessage: "go",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    mock.emit(
      makeAssistant({
        content: [
          { type: "tool_use", id: "t1", name: "Read", input: { file_path: "x" } },
        ],
      }),
    );
    await flushMicrotasks();

    // 5s active
    vi.advanceTimersByTime(5_000);
    await flushMicrotasks();
    // Pause for 20s
    runner.notifyAwaitingUser("conv-hardcap", true);
    vi.advanceTimersByTime(20_000);
    await flushMicrotasks();
    expect(events._ended.find((e) => e.status === "runner_runaway")).toBeUndefined();
    // Resume — armTurnHardCap re-arms; setTimeout scheduled at t=25
    // for 30s would fire at t=55s. Under cumulative semantics, at
    // fire time elapsedMs = 55 - 0 - 20 = 35s > 30s ceiling.
    runner.notifyAwaitingUser("conv-hardcap", false);
    // Advance to t=54.999s — under cumulative threshold, no fire yet.
    vi.advanceTimersByTime(29_999);
    await flushMicrotasks();
    expect(events._ended.find((e) => e.status === "runner_runaway")).toBeUndefined();
    // +2ms tips us past wall-clock t=55s; turnHardCap fires with
    // reason="max_turn_duration".
    vi.advanceTimersByTime(2);
    await flushMicrotasks();
    const hardCapEnd = events._ended.find((e) => e.status === "runner_runaway");
    expect(hardCapEnd?.reason).toBe("max_turn_duration");
  });

  it("AC13 (#3040 Finding 4): multi-turn paused-budget reset — turn 1's paused interval does NOT leak into turn 2's wall-clock budget", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 30_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-multiturn",
      userId: "u1",
      userMessage: "go",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // Turn 1: first block at t=0, pause 10s, terminal result clears
    // firstToolUseAt.
    mock.emit(
      makeAssistant({
        content: [
          { type: "tool_use", id: "t1", name: "Bash", input: { command: "ls" } },
        ],
      }),
    );
    await flushMicrotasks();
    runner.notifyAwaitingUser("conv-multiturn", true);
    vi.advanceTimersByTime(10_000);
    runner.notifyAwaitingUser("conv-multiturn", false);
    // Terminal result @ t=10s — clears firstToolUseAt.
    mock.emit({
      type: "result",
      subtype: "success",
      duration_ms: 10,
      duration_api_ms: 10,
      is_error: false,
      num_turns: 1,
      result: "ok",
      session_id: "s1",
      total_cost_usd: 0,
      usage: { input_tokens: 1, output_tokens: 1 },
    } as SDKResultMessage);
    await flushMicrotasks();

    // Turn 2: first block at t=15s wall-time (5s of inter-turn idle).
    vi.advanceTimersByTime(5_000);
    mock.emit(
      makeAssistant({
        content: [
          { type: "tool_use", id: "t2", name: "Bash", input: { command: "pwd" } },
        ],
      }),
    );
    await flushMicrotasks();
    // recordAssistantBlock has reset totalPausedMs to 0 for the new
    // turn. Wall-clock fires at t = 15 + 30 = 45s; effective elapsed
    // = 45 - 15 - 0 = 30s.
    vi.advanceTimersByTime(29_999);
    await flushMicrotasks();
    expect(events._ended.find((e) => e.status === "runner_runaway")).toBeUndefined();
    vi.advanceTimersByTime(2);
    await flushMicrotasks();
    expect(events._ended.find((e) => e.status === "runner_runaway")).toBeDefined();
  });

  it("AC14 (#3040 Finding 2): mirrorWithDebounce 5-min TTL on 'unknown:notify-awaiting-no-active-query' — 3 calls within 100ms coalesce; advance 5min+1ms then a second mirror fires", () => {
    mockMirrorWithDebounce.mockClear();
    const runner = createSoleurGoRunner({
      queryFactory: () => createMockQuery().query,
      now: () => Date.now(),
      wallClockTriggerMs: 30_000,
    });

    // 3 rapid calls — under the real `mirrorWithDebounce`, only the
    // first would mirror. Here the mock fires every time, so we assert
    // shape and rely on observability-mirror-debounce.test.ts to pin
    // the TTL semantics. The runner's contract: pass the const errorClass
    // and "unknown" userId on every call so the real debounce coalesces.
    runner.notifyAwaitingUser("ghost-conv", true);
    runner.notifyAwaitingUser("ghost-conv", true);
    runner.notifyAwaitingUser("ghost-conv", true);
    expect(mockMirrorWithDebounce).toHaveBeenCalledTimes(3);
    for (const call of mockMirrorWithDebounce.mock.calls) {
      expect(call[2]).toBe("unknown");
      expect(call[3]).toBe(NOTIFY_AWAITING_NO_ACTIVE_QUERY_ERROR_CLASS);
    }
  });

  it("AC7 regression: without notifyAwaitingUser, 30s runaway still fires after first tool_use without a result", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 30_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-regression",
      userId: "u1",
      userMessage: "do",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    mock.emit(
      makeAssistant({
        content: [
          { type: "tool_use", id: "t1", name: "Bash", input: { command: "ls" } },
        ],
      }),
    );
    await flushMicrotasks();

    // Advance past 30s without any user-pause.
    vi.advanceTimersByTime(30_001);
    await flushMicrotasks();

    expect(events._ended.find((e) => e.status === "runner_runaway")).toBeDefined();
    expect(mock.closeSpy).toHaveBeenCalled();
  });
});

// RED tests for plan
// 2026-05-05-fix-concierge-idle-runaway-and-duplicate-label-plan.md
//
// Bug 1 — Concierge "agent went idle without finishing" on PDF summarize:
// `DEFAULT_WALL_CLOCK_TRIGGER_MS = 30s` is too tight for PDF Read+summarize
// turns. The fix raises the default to 90s AND, more importantly, resets the
// timeout window on EVERY assistant block (text or tool_use). Turn-origin
// `firstToolUseAt` is preserved so `elapsedMs` reports total turn time
// (not "time since last block"). The runaway WorkflowEnded payload carries
// `lastBlockKind` and `lastBlockToolName` so future timer-tightening is
// informed by which tool consistently bumps against the ceiling.

describe("soleur-go-runner runaway window reset (Bug 1: PDF summarize idle)", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mockReportSilentFallback.mockClear();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("DEFAULT_WALL_CLOCK_TRIGGER_MS is 90s — bumped from 30s to accommodate PDF Read+summarize turns", () => {
    expect(DEFAULT_WALL_CLOCK_TRIGGER_MS).toBe(90 * 1000);
  });

  it("a second tool_use at t=8s resets the runaway window — runaway does NOT fire at t=15s (would have under no-reset semantic)", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 10_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-reset-tool",
      userId: "u1",
      userMessage: "summarize",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // First tool_use at t=0 — arms the timer (and stamps turn-origin).
    mock.emit(
      makeAssistant({
        content: [{ type: "tool_use", id: "t1", name: "Read", input: { file_path: "/x.pdf" } }],
      }),
    );
    await flushMicrotasks();

    // 8s elapses, then a second tool_use arrives — the window MUST reset.
    vi.advanceTimersByTime(8_000);
    await flushMicrotasks();
    mock.emit(
      makeAssistant({
        content: [{ type: "tool_use", id: "t2", name: "Read", input: { file_path: "/y.pdf" } }],
      }),
    );
    await flushMicrotasks();

    // 7s more (total t=15s). Under the OLD no-reset semantic, runaway would
    // fire at t=10s. Under the NEW per-block-reset semantic, the second
    // arm at t=8s gives a fresh 10s window, so runaway must NOT fire.
    vi.advanceTimersByTime(7_000);
    await flushMicrotasks();
    expect(events._ended.find((e) => e.status === "runner_runaway")).toBeUndefined();
  });

  it("a text assistant block at t=8s also resets the runaway window — text counts as 'agent is alive'", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 10_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-reset-text",
      userId: "u1",
      userMessage: "summarize",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // First tool_use at t=0.
    mock.emit(
      makeAssistant({
        content: [{ type: "tool_use", id: "t1", name: "Read", input: { file_path: "/x.pdf" } }],
      }),
    );
    await flushMicrotasks();

    // 8s elapses, agent emits a text block (analyzing, narrating progress).
    vi.advanceTimersByTime(8_000);
    await flushMicrotasks();
    mock.emit(
      makeAssistant({
        content: [{ type: "text", text: "Reading the document and preparing a summary..." }],
      }),
    );
    await flushMicrotasks();

    // 7s more (total t=15s). Under the NEW semantic the text block reset the
    // window; runaway must NOT fire.
    vi.advanceTimersByTime(7_000);
    await flushMicrotasks();
    expect(events._ended.find((e) => e.status === "runner_runaway")).toBeUndefined();
  });

  it("DEFAULT_MAX_TURN_DURATION_MS is 10 min — absolute ceiling on a single turn, not reset by per-block activity", () => {
    expect(DEFAULT_MAX_TURN_DURATION_MS).toBe(10 * 60 * 1000);
  });

  it("absolute turn ceiling fires runaway with reason=max_turn_duration even when blocks keep arriving (chatty-stall defense-in-depth)", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      // Idle window must be larger than the per-step gap so it never fires;
      // hard cap is 30s. The agent emits a block every 5s — under the new
      // semantic the idle window keeps resetting indefinitely. The hard
      // cap is what stops it.
      wallClockTriggerMs: 20_000,
      maxTurnDurationMs: 30_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-hardcap",
      userId: "u1",
      userMessage: "loop forever",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // First block at t=0 arms both timers.
    mock.emit(
      makeAssistant({
        content: [{ type: "tool_use", id: "t0", name: "Bash", input: { command: "x" } }],
      }),
    );
    await flushMicrotasks();

    // Emit a block every 5s — the idle window (20s) keeps resetting.
    for (let i = 1; i <= 7; i++) {
      vi.advanceTimersByTime(5_000);
      // Before t=30s, neither timer should have fired.
      if (i * 5_000 < 30_000) {
        expect(events._ended.find((e) => e.status === "runner_runaway")).toBeUndefined();
      }
      mock.emit(
        makeAssistant({
          content: [{ type: "text", text: `chatter ${i}` }],
        }),
      );
      await flushMicrotasks();
    }

    // The hard cap (30s anchor) has now elapsed (we are at t=35s) and the
    // hard-cap timer fires INDEPENDENTLY of the per-block window.
    const end = events._ended.find((e) => e.status === "runner_runaway") as
      | (WorkflowEnd & { status: "runner_runaway"; reason?: unknown; lastBlockKind?: unknown })
      | undefined;
    expect(end).toBeDefined();
    expect(end!.reason).toBe("max_turn_duration");
    // Last block at fire time was the most recent text chatter.
    expect(end!.lastBlockKind).toBe("text");
    expect(mock.closeSpy).toHaveBeenCalled();
  });

  it("re-dispatch on existing state resets per-turn diagnostics — prior turn's lastBlockToolName MUST NOT poison the next runaway log", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 10_000,
      maxTurnDurationMs: 60_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-redispatch",
      userId: "u1",
      userMessage: "first turn",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // Turn 1 ends mid-stream WITHOUT a result (e.g., dropped/delayed) —
    // only a `Read` tool_use lands.
    mock.emit(
      makeAssistant({
        content: [{ type: "tool_use", id: "t1", name: "Read", input: { file_path: "/x" } }],
      }),
    );
    await flushMicrotasks();

    // User fires a follow-up dispatch before turn 1's result arrives.
    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-redispatch",
      userId: "u1",
      userMessage: "second turn",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // Now turn 2 stalls (no blocks, no result) past the idle window.
    vi.advanceTimersByTime(10_001);
    await flushMicrotasks();

    const end = events._ended.find((e) => e.status === "runner_runaway") as
      | (WorkflowEnd & { status: "runner_runaway"; lastBlockKind?: unknown; lastBlockToolName?: unknown })
      | undefined;
    // Either no runaway fires (turn 2 had zero blocks so the timer was
    // never armed) OR if a runaway fires its payload reflects turn 2's
    // state (null), NOT turn 1's "Read".
    if (end) {
      expect(end.lastBlockToolName).not.toBe("Read");
      expect(end.lastBlockKind).toBeNull();
      expect(end.lastBlockToolName).toBeNull();
    }
  });

  it("when runaway DOES fire, elapsedMs reports total turn elapsed (turn-origin), NOT time-since-last-block", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 10_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-elapsed",
      userId: "u1",
      userMessage: "summarize",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // First tool_use at t=0 (turn origin).
    mock.emit(
      makeAssistant({
        content: [{ type: "tool_use", id: "t1", name: "Read", input: { file_path: "/x.pdf" } }],
      }),
    );
    await flushMicrotasks();

    // Second tool_use at t=5s (resets the 10s window).
    vi.advanceTimersByTime(5_000);
    await flushMicrotasks();
    mock.emit(
      makeAssistant({
        content: [{ type: "tool_use", id: "t2", name: "Read", input: { file_path: "/y.pdf" } }],
      }),
    );
    await flushMicrotasks();

    // No more blocks — runaway fires at t = 5s + 10s = 15s.
    vi.advanceTimersByTime(10_001);
    await flushMicrotasks();
    const end = events._ended.find((e) => e.status === "runner_runaway") as
      | (WorkflowEnd & { status: "runner_runaway" })
      | undefined;
    expect(end).toBeDefined();
    // elapsedMs reflects total turn elapsed (~15s), not the 10s window.
    // Tolerance widened to 1s to survive future async-shape refactors
    // (extra await boundaries, batched emits) without false-fail.
    expect(end!.elapsedMs).toBeGreaterThanOrEqual(15_000);
    expect(end!.elapsedMs).toBeLessThan(16_000);
  });

  it("runaway WorkflowEnded carries lastBlockKind and lastBlockToolName so future tightening is informed by which tool bumps the ceiling", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 10_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-observ",
      userId: "u1",
      userMessage: "summarize",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // Single Read tool_use, then nothing for >10s — runaway fires.
    mock.emit(
      makeAssistant({
        content: [{ type: "tool_use", id: "t1", name: "Read", input: { file_path: "/au-chat-potan.pdf" } }],
      }),
    );
    await flushMicrotasks();
    vi.advanceTimersByTime(10_001);
    await flushMicrotasks();

    const end = events._ended.find((e) => e.status === "runner_runaway") as
      | (WorkflowEnd & {
          status: "runner_runaway";
          lastBlockKind?: unknown;
          lastBlockToolName?: unknown;
          reason?: unknown;
        })
      | undefined;
    expect(end).toBeDefined();
    expect(end!.lastBlockKind).toBe("tool_use");
    expect(end!.lastBlockToolName).toBe("Read");
    expect(end!.reason).toBe("idle_window");
  });
});

// Tests for plan 2026-06-12-fix-concierge-stream-timeout-debug-scroll-plan.md
// — the SDK's mid-tool `tool_progress` heartbeat re-arms `state.runaway`.
//
// A single long tool execution (large `Read`, slow Anthropic round-trip)
// emits no assistant block and no `tool_use_result` for tens of seconds,
// but the SDK DOES yield `SDKToolProgressMessage` (type: "tool_progress")
// every few seconds while the tool is alive and progressing. The runner
// must treat that as forward progress and re-arm the per-block idle window
// (`state.runaway` ONLY — never `state.turnHardCap`). A genuinely HUNG tool
// emits NO `tool_progress`, so it still trips `idle_window` (AC2b).
describe("soleur-go-runner runaway window reset (tool_progress heartbeat)", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mockReportSilentFallback.mockClear();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("AC1: tool_use + N tool_progress < window apart spanning > window does NOT fire runaway (heartbeat re-arms state.runaway)", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 10_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-progress-reset",
      userId: "u1",
      userMessage: "read big file",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // Single tool_use at t=0 arms the 10s window. No second block, no result.
    mock.emit(
      makeAssistant({
        content: [{ type: "tool_use", id: "t1", name: "Read", input: { file_path: "/big.pdf" } }],
      }),
    );
    await flushMicrotasks();

    // Emit a tool_progress heartbeat every 7s for ~28s total (well past the
    // 10s window). Each heartbeat must re-arm the window. Under the OLD
    // semantic (no tool_progress reset) runaway would fire at t=10s.
    for (let i = 1; i <= 4; i++) {
      vi.advanceTimersByTime(7_000);
      await flushMicrotasks();
      expect(events._ended.find((e) => e.status === "runner_runaway")).toBeUndefined();
      mock.emit(makeToolProgress("t1", i * 7));
      await flushMicrotasks();
    }

    // Total elapsed > 28s with no block/result — but each heartbeat kept the
    // window fresh, so runaway must NOT have fired.
    expect(events._ended.find((e) => e.status === "runner_runaway")).toBeUndefined();
  });

  it("AC2b (merge-blocking): tool_use then SDK SILENCE (no tool_progress, no result) > window STILL fires runner_runaway reason=idle_window — the heartbeat reset must NOT blind the watchdog to a genuinely hung tool", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 10_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-hung-tool",
      userId: "u1",
      userMessage: "read hung file",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // Single tool_use at t=0, then total silence — a genuinely HUNG tool
    // emits NO tool_progress and NO result.
    mock.emit(
      makeAssistant({
        content: [{ type: "tool_use", id: "t1", name: "Read", input: { file_path: "/hung" } }],
      }),
    );
    await flushMicrotasks();

    vi.advanceTimersByTime(10_001);
    await flushMicrotasks();

    const end = events._ended.find((e) => e.status === "runner_runaway") as
      | (WorkflowEnd & { status: "runner_runaway"; reason?: unknown })
      | undefined;
    expect(end).toBeDefined();
    expect(end!.reason).toBe("idle_window");
  });

  it("AC3: tool_progress heartbeats re-arm state.runaway but NEVER state.turnHardCap — the 10-min absolute ceiling still fires reason=max_turn_duration even when heartbeats keep arriving", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      // Idle window (20s) larger than the heartbeat gap (5s) so it never
      // fires; the hard cap (30s) is what must stop a forever-progressing tool.
      wallClockTriggerMs: 20_000,
      maxTurnDurationMs: 30_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      persona: "command_center",
      conversationId: "conv-progress-hardcap",
      userId: "u1",
      userMessage: "read forever",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // First block at t=0 arms both timers.
    mock.emit(
      makeAssistant({
        content: [{ type: "tool_use", id: "t1", name: "Read", input: { file_path: "/x" } }],
      }),
    );
    await flushMicrotasks();

    // Heartbeat every 5s — the idle window (20s) keeps resetting, but the
    // hard cap (30s anchor) must fire INDEPENDENTLY.
    for (let i = 1; i <= 7; i++) {
      vi.advanceTimersByTime(5_000);
      if (i * 5_000 < 30_000) {
        expect(events._ended.find((e) => e.status === "runner_runaway")).toBeUndefined();
      }
      mock.emit(makeToolProgress("t1", i * 5));
      await flushMicrotasks();
    }

    const end = events._ended.find((e) => e.status === "runner_runaway") as
      | (WorkflowEnd & { status: "runner_runaway"; reason?: unknown })
      | undefined;
    expect(end).toBeDefined();
    expect(end!.reason).toBe("max_turn_duration");
  });
});
