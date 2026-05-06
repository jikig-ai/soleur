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
// `reportSilentFallback` import inside soleur-go-runner.ts resolves to the
// mock and doesn't pull pino into the test bundle.
const { mockReportSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

import {
  createSoleurGoRunner,
  DEFAULT_MAX_TURN_DURATION_MS,
  type WorkflowEnd,
  type DispatchEvents,
} from "@/server/soleur-go-runner";

// RED tests for plan
// 2026-05-06-fix-cc-pdf-idle-reaper-and-issue-link-org-plan.md
//
// Bug 1: Concierge gives up mid-`Read` on a multi-MB PDF. The 90s
// `wallClockTriggerMs` ceiling fires while Anthropic is processing the PDF
// + composing the summary, because `consumeStream` only resets the per-block
// idle window on `assistant`/`result` messages — it ignores the SDK's
// `user`-role tool_use_result messages that signal forward progress
// (sdk.d.ts:2528 — `SDKUserMessage.tool_use_result?: unknown`).
//
// Fix: in `consumeStream`, when `msg.type === "user"` AND
// `tool_use_result !== undefined` AND the runner is not closed/awaitingUser,
// re-arm `state.runaway` (per-block idle window only). Do NOT touch
// `state.turnHardCap` — the 10-min absolute ceiling stays anchored on
// `firstToolUseAt` (defense-pair invariant from PR #3225 and learning
// `2026-05-05-defense-relaxation-must-name-new-ceiling.md`).

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

function makeAssistant(
  partial: Partial<SDKAssistantMessage> & {
    content: Array<
      | { type: "text"; text: string }
      | {
          type: "tool_use";
          id: string;
          name: string;
          input: Record<string, unknown>;
        }
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

// AC1.1 / AC1.4: a `user`-role SDK message carrying `tool_use_result` is
// the SDK's own forward-progress signal (sdk.d.ts:2528). The new branch
// detects it via the documented field and re-arms `armRunaway`.
function makeUserToolResult(
  toolUseId: string,
  opts: { isReplay?: boolean; sessionId?: string } = {},
): SDKUserMessage {
  const base = {
    type: "user",
    message: {
      role: "user",
      content: [
        {
          type: "tool_result",
          tool_use_id: toolUseId,
          content: "ok",
        },
      ],
      // biome-ignore lint/suspicious/noExplicitAny: minimal SDK fixture
    } as any,
    parent_tool_use_id: null,
    isSynthetic: true,
    tool_use_result: { ok: true },
    session_id: opts.sessionId ?? "sess-1",
  };
  if (opts.isReplay) {
    return {
      ...base,
      isReplay: true,
      uuid: "00000000-0000-0000-0000-0000000000aa" as never,
    } as unknown as SDKUserMessage;
  }
  return base as SDKUserMessage;
}

// AC1.6: a `user`-role SDK message WITHOUT `tool_use_result` MUST NOT
// reset the timer — the discriminator field is the single load-bearing
// check.
function makeUserNoToolResult(): SDKUserMessage {
  return {
    type: "user",
    message: {
      role: "user",
      content: "follow-up text",
      // biome-ignore lint/suspicious/noExplicitAny: minimal SDK fixture
    } as any,
    parent_tool_use_id: null,
    session_id: "sess-1",
  } as SDKUserMessage;
}

function createMockQuery(scripted: SDKMessage[] = []) {
  let closed = false;
  const queue: SDKMessage[] = [...scripted];
  let resolveNext: ((r: IteratorResult<SDKMessage>) => void) | null = null;
  const emitted: SDKMessage[] = [];
  const closeSpy = vi.fn();

  const iter: AsyncGenerator<SDKMessage, void> = {
    async next(): Promise<IteratorResult<SDKMessage>> {
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

describe("consumeStream — tool_use_result resets runaway timer (Bug 1: PDF mid-Read idle)", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mockReportSilentFallback.mockClear();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  // AC1.4: the bug fix. The PDF "Read" tool_use arms a 10s window; a
  // tool_use_result lands at t=8s and MUST reset the window so a final
  // text block at t=15s does NOT trigger runaway (would have at t=10s
  // under the no-reset semantic).
  it("scenario A: tool_use → tool_use_result @8s → text @15s does NOT trigger runaway (window reset)", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 10_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      conversationId: "conv-A",
      userId: "u1",
      userMessage: "summarize this pdf",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // First tool_use at t=0 — arms the 10s window AND the turn ceiling.
    mock.emit(
      makeAssistant({
        content: [
          {
            type: "tool_use",
            id: "tu1",
            name: "Read",
            input: { file_path: "/book.pdf" },
          },
        ],
      }),
    );
    await flushMicrotasks();

    // 8s elapses, then SDK emits a `user`-role tool_use_result. Under
    // the OLD semantic the window would NOT reset; under the NEW semantic
    // it does — the timer is re-armed for another 10s.
    vi.advanceTimersByTime(8_000);
    await flushMicrotasks();
    mock.emit(makeUserToolResult("tu1"));
    await flushMicrotasks();

    // 7s more (total t=15s). Under the OLD semantic runaway fires at
    // t=10s. Under the NEW semantic the tool_use_result reset the window
    // at t=8s, so we are 7s into a fresh 10s window.
    vi.advanceTimersByTime(7_000);
    await flushMicrotasks();
    expect(
      events._ended.find((e) => e.status === "runner_runaway"),
    ).toBeUndefined();
  });

  // AC1.5: defense-pair invariant. A tool_use_result drumbeat every 5s
  // MUST NOT defeat the 10-min `DEFAULT_MAX_TURN_DURATION_MS` ceiling.
  // Use a SHRUNK maxTurnDurationMs in the test (production constant
  // is asserted separately, see scenario B-pin) so the test runs in
  // bounded fake-timer time, but pin that the new branch does NOT call
  // `armTurnHardCap`.
  it("scenario B: tool_use_result drumbeat does NOT defeat the absolute turn ceiling", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 20_000,
      maxTurnDurationMs: 30_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      conversationId: "conv-B",
      userId: "u1",
      userMessage: "loop",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // First tool_use at t=0 arms BOTH timers.
    mock.emit(
      makeAssistant({
        content: [
          {
            type: "tool_use",
            id: "tu0",
            name: "Read",
            input: { file_path: "/x.pdf" },
          },
        ],
      }),
    );
    await flushMicrotasks();

    // Drum-beat tool_use_result every 5s — the per-block idle window
    // (20s) keeps resetting under the new semantic. The hard cap (30s
    // anchor) MUST still fire because the new branch does not touch
    // `turnHardCap`.
    for (let i = 1; i <= 7; i++) {
      vi.advanceTimersByTime(5_000);
      mock.emit(makeUserToolResult(`tu${i}`));
      await flushMicrotasks();
    }

    const end = events._ended.find((e) => e.status === "runner_runaway") as
      | (WorkflowEnd & { status: "runner_runaway"; reason?: unknown })
      | undefined;
    expect(end).toBeDefined();
    expect(end!.reason).toBe("max_turn_duration");
  });

  // AC1.5 production-constant pin: the test fixture uses a smaller value
  // for runtime, but the production constant MUST stay at 10 min — the
  // load-bearing assertion that protects the defense-pair invariant per
  // learning `2026-05-05-defense-relaxation-must-name-new-ceiling.md`.
  it("scenario B-pin: DEFAULT_MAX_TURN_DURATION_MS is 10 min (production-constant invariant)", () => {
    expect(DEFAULT_MAX_TURN_DURATION_MS).toBe(10 * 60 * 1000);
  });

  // AC1.6: a `user` message WITHOUT `tool_use_result` MUST NOT reset
  // the timer. The discriminator field is the single load-bearing check.
  it("scenario C: user message with tool_use_result === undefined does NOT reset the timer", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 10_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      conversationId: "conv-C",
      userId: "u1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    // Tool_use at t=0 arms the 10s window.
    mock.emit(
      makeAssistant({
        content: [
          {
            type: "tool_use",
            id: "tu1",
            name: "Read",
            input: { file_path: "/x.pdf" },
          },
        ],
      }),
    );
    await flushMicrotasks();

    // A non-tool_use_result `user` message lands at t=5s — MUST NOT reset.
    vi.advanceTimersByTime(5_000);
    await flushMicrotasks();
    mock.emit(makeUserNoToolResult());
    await flushMicrotasks();

    // Advance another 5.001s (total t=10.001s). Under the correct
    // discriminator-precision semantic, runaway MUST fire at t=10s.
    vi.advanceTimersByTime(5_001);
    await flushMicrotasks();
    const end = events._ended.find((e) => e.status === "runner_runaway") as
      | (WorkflowEnd & { status: "runner_runaway"; reason?: unknown })
      | undefined;
    expect(end).toBeDefined();
    expect(end!.reason).toBe("idle_window");
  });

  // AC1.7: silence still fires. A `tool_use` followed by 10.001s of
  // silence (no tool_use_result, no assistant text) MUST still trigger
  // runaway with `reason: "idle_window"`. The fix is forward-progress-
  // aware, not a blanket relaxation.
  it("scenario D: tool_use + 10.001s silence still fires runaway with reason=idle_window", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 10_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      conversationId: "conv-D",
      userId: "u1",
      userMessage: "summarize",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    mock.emit(
      makeAssistant({
        content: [
          {
            type: "tool_use",
            id: "tu1",
            name: "Read",
            input: { file_path: "/x.pdf" },
          },
        ],
      }),
    );
    await flushMicrotasks();
    vi.advanceTimersByTime(10_001);
    await flushMicrotasks();

    const end = events._ended.find((e) => e.status === "runner_runaway") as
      | (WorkflowEnd & {
          status: "runner_runaway";
          reason?: unknown;
          lastBlockToolName?: unknown;
        })
      | undefined;
    expect(end).toBeDefined();
    expect(end!.reason).toBe("idle_window");
    expect(end!.lastBlockToolName).toBe("Read");
  });

  // AC1.8: replay-path resilience. `SDKUserMessageReplay` (sdk.d.ts:
  // 2538-2552) shares the `tool_use_result?: unknown` field. The shared
  // field-check covers both shapes — no extra branch.
  it("scenario E: SDKUserMessageReplay with tool_use_result also resets the runaway timer", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 10_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      conversationId: "conv-E",
      userId: "u1",
      userMessage: "resume",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    mock.emit(
      makeAssistant({
        content: [
          {
            type: "tool_use",
            id: "tu1",
            name: "Read",
            input: { file_path: "/x.pdf" },
          },
        ],
      }),
    );
    await flushMicrotasks();

    vi.advanceTimersByTime(8_000);
    await flushMicrotasks();
    // Replay-path tool_use_result.
    mock.emit(makeUserToolResult("tu1", { isReplay: true }));
    await flushMicrotasks();

    // 7s more — under the correct semantic the replay-path message reset
    // the window; runaway must NOT fire.
    vi.advanceTimersByTime(7_000);
    await flushMicrotasks();
    expect(
      events._ended.find((e) => e.status === "runner_runaway"),
    ).toBeUndefined();
  });

  // AC1.2 + AC1.3 indirect: the result-message path (post-tool_use_result)
  // continues to work — emitting a `result` after a tool_use_result clears
  // cleanly with no runaway emission. Pins that the new branch does not
  // poison subsequent `result` handling.
  it("subsequent result message clears the workflow cleanly after a tool_use_result reset", async () => {
    vi.setSystemTime(0);
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      wallClockTriggerMs: 10_000,
    });
    const events = makeEvents();

    await runner.dispatch({
      conversationId: "conv-F",
      userId: "u1",
      userMessage: "summarize",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    mock.emit(
      makeAssistant({
        content: [
          {
            type: "tool_use",
            id: "tu1",
            name: "Read",
            input: { file_path: "/x.pdf" },
          },
        ],
      }),
    );
    await flushMicrotasks();
    vi.advanceTimersByTime(5_000);
    await flushMicrotasks();
    mock.emit(makeUserToolResult("tu1"));
    await flushMicrotasks();

    // Final assistant text block + result.
    vi.advanceTimersByTime(2_000);
    await flushMicrotasks();
    mock.emit(makeAssistant({ content: [{ type: "text", text: "summary..." }] }));
    await flushMicrotasks();
    mock.emit(makeResult(0.01));
    await flushMicrotasks();

    expect(
      events._ended.find((e) => e.status === "runner_runaway"),
    ).toBeUndefined();
  });
});
