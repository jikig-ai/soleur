import {
  describe,
  it,
  expect,
  vi,
  beforeEach,
  afterEach,
} from "vitest";
import type {
  Query,
  SDKMessage,
  SDKUserMessage,
  SDKResultMessage,
  SDKAssistantMessage,
} from "@anthropic-ai/claude-agent-sdk";

// Mock observability BEFORE importing the runner so the
// `reportSilentFallback` import inside soleur-go-runner.ts resolves to
// the mock and the silent-fallback assertion can inspect it.
const { mockReportSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

import {
  createSoleurGoRunner,
  DEFAULT_WALL_CLOCK_TRIGGER_MS,
  DEFAULT_MAX_TURN_DURATION_MS,
  type QueryFactory,
  type WorkflowEnd,
  type DispatchEvents,
} from "@/server/soleur-go-runner";

// RED tests for plan 2026-04-29-fix-command-center-qa-permissions-runaway-rename-plan.md
// Stage TS4 (AC8), TS5 (AC9), AC17 — `notifyAwaitingUser` pause/resume of
// the runaway wall-clock so `5xx`-style runaway timeouts are not charged
// against human read time during a Bash review-gate or other interactive
// prompt.
//
// The runner exposes `notifyAwaitingUser(conversationId, awaiting:
// boolean)`. While `awaiting === true`, the wall-clock runaway timer is
// paused (`clearTimeout`); when transitioning back to false, the runner
// re-arms with `firstToolUseAt = now()` so the elapsed counter resets.
// If the conversationId is unknown, it MUST mirror to Sentry via
// `reportSilentFallback` (no silent no-op) per
// `cq-silent-fallback-must-mirror-to-sentry`.

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

function makeAssistant(
  partial: Partial<SDKAssistantMessage> & {
    content: Array<
      | { type: "text"; text: string }
      | { type: "tool_use"; id: string; name: string; input: Record<string, unknown> }
    >;
  },
): SDKAssistantMessage {
  return {
    type: "assistant",
    message: {
      id: partial.uuid ?? "msg_1",
      role: "assistant",
      model: "claude-sonnet-4-6",
      stop_reason: null,
      stop_sequence: null,
      type: "message",
      usage: {
        input_tokens: 0,
        output_tokens: 0,
        cache_creation_input_tokens: 0,
        cache_read_input_tokens: 0,
        server_tool_use: null,
        service_tier: null,
      },
      content: partial.content,
      // biome-ignore lint/suspicious/noExplicitAny: minimal SDK fixture
    } as any,
    parent_tool_use_id: partial.parent_tool_use_id ?? null,
    uuid: (partial.uuid ?? "00000000-0000-0000-0000-000000000001") as never,
    session_id: partial.session_id ?? "sess-1",
  } as SDKAssistantMessage;
}

function makeResult(totalCostUsd: number, sessionId = "sess-1"): SDKResultMessage {
  return {
    type: "result",
    subtype: "success",
    duration_ms: 100,
    duration_api_ms: 50,
    is_error: false,
    num_turns: 1,
    result: "",
    stop_reason: "end_turn",
    total_cost_usd: totalCostUsd,
    // biome-ignore lint/suspicious/noExplicitAny: minimal SDK fixture
    usage: { input_tokens: 0, output_tokens: 0 } as any,
    modelUsage: {},
    permission_denials: [],
    uuid: "00000000-0000-0000-0000-0000000000ff" as never,
    session_id: sessionId,
  } as SDKResultMessage;
}

function createMockQuery(scripted: SDKMessage[] = []) {
  let closed = false;
  const queue: SDKMessage[] = [...scripted];
  let resolveNext: ((r: IteratorResult<SDKMessage>) => void) | null = null;
  const emitted: SDKMessage[] = [];
  const closeSpy = vi.fn();
  let throwOnNext: unknown = null;

  const iter: AsyncGenerator<SDKMessage, void> = {
    async next(): Promise<IteratorResult<SDKMessage>> {
      if (throwOnNext !== null) {
        const err = throwOnNext;
        throwOnNext = null;
        throw err;
      }
      if (queue.length > 0) {
        const value = queue.shift()!;
        emitted.push(value);
        return { value, done: false };
      }
      if (closed) return { value: undefined, done: true };
      return new Promise<IteratorResult<SDKMessage>>((resolve) => {
        resolveNext = resolve;
      });
    },
    async return() {
      closed = true;
      return { value: undefined, done: true };
    },
    async throw(err) {
      closed = true;
      throw err;
    },
    async [Symbol.asyncDispose]() {
      closed = true;
    },
    [Symbol.asyncIterator]() {
      return iter;
    },
  };

  function emit(msg: SDKMessage): void {
    if (resolveNext) {
      const r = resolveNext;
      resolveNext = null;
      emitted.push(msg);
      r({ value: msg, done: false });
    } else {
      queue.push(msg);
    }
  }

  function emitError(err: unknown): void {
    // Inject an error into the consumeStream loop. If a consumer is
    // currently awaiting next(), we must reject that pending promise.
    if (resolveNext) {
      const r = resolveNext;
      resolveNext = null;
      // Trigger via the iterator's `throw` semantics: settle the awaiting
      // promise with a rejected one.
      Promise.resolve().then(() => r(Promise.reject(err) as never));
    } else {
      throwOnNext = err;
    }
  }

  function finish(): void {
    if (resolveNext) {
      const r = resolveNext;
      resolveNext = null;
      r({ value: undefined, done: true });
    }
    closed = true;
  }

  const q: Mutable<Partial<Query>> = {
    ...(iter as unknown as Query),
    close: () => {
      closeSpy();
      finish();
    },
    interrupt: vi.fn(async () => {}),
    setPermissionMode: vi.fn(async () => {}),
    setModel: vi.fn(async () => {}),
    setMaxThinkingTokens: vi.fn(async () => {}),
    applyFlagSettings: vi.fn(async () => {}),
    // biome-ignore lint/suspicious/noExplicitAny: test stub
    initializationResult: vi.fn(async () => ({}) as any),
    supportedCommands: vi.fn(async () => []),
    supportedModels: vi.fn(async () => []),
    streamInput: vi.fn(async () => {}),
    stopTask: vi.fn(async () => {}),
  };

  return {
    query: q as Query,
    emit,
    emitError,
    finish,
    closeSpy,
    emitted,
    isClosed: () => closed,
  };
}

function makeEvents(): DispatchEvents & {
  _ended: WorkflowEnd[];
  _tools: Array<{ name: string; input: Record<string, unknown> }>;
} {
  const ended: WorkflowEnd[] = [];
  const tools: Array<{ name: string; input: Record<string, unknown> }> = [];
  return {
    onText: () => {},
    onToolUse: (b) => tools.push(b),
    onWorkflowDetected: () => {},
    onWorkflowEnded: (e) => ended.push(e),
    onResult: () => {},
    _ended: ended,
    _tools: tools,
  };
}

async function flushMicrotasks(count = 8): Promise<void> {
  for (let i = 0; i < count; i++) await Promise.resolve();
}

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

  it("AC9: runaway re-arms after notify(false) — only ACTIVE compute time counts (5s + 30s = 35s, paused 20s in middle)", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 30_000,
    });
    const events = makeEvents();

    await runner.dispatch({
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

    // Resume — re-arms with fresh firstToolUseAt = now().
    runner.notifyAwaitingUser("conv-resume", false);

    // Advance 29.999s post-resume — still under threshold.
    vi.advanceTimersByTime(29_999);
    await flushMicrotasks();
    expect(events._ended.find((e) => e.status === "runner_runaway")).toBeUndefined();

    // Final 2ms tips us past 30s of post-resume active time. Runaway
    // fires now (total elapsed real-clock = 5s + 20s + ~30s ≈ 55s; only
    // the 30s post-resume window matters).
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

  it("silent-fallback: notifyAwaitingUser on unknown conversationId mirrors to Sentry via reportSilentFallback (does NOT silently no-op)", () => {
    const runner = createSoleurGoRunner({
      queryFactory: () => createMockQuery().query,
      now: () => Date.now(),
      wallClockTriggerMs: 30_000,
    });

    runner.notifyAwaitingUser("unknown-conv-id", true);

    // Find the call attributable to notifyAwaitingUser.
    const matchingCalls = mockReportSilentFallback.mock.calls.filter(
      ([, ctx]) =>
        ctx?.feature === "soleur-go-runner" && ctx?.op === "notifyAwaitingUser",
    );
    expect(matchingCalls).toHaveLength(1);
    const [err, ctx] = matchingCalls[0]!;
    expect(err).toBeInstanceOf(Error);
    expect((err as Error).message).toContain("notifyAwaitingUser");
    expect(ctx.extra).toMatchObject({ conversationId: "unknown-conv-id" });
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
