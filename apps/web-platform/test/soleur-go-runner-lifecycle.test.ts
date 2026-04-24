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
  SDKResultMessage,
} from "@anthropic-ai/claude-agent-sdk";

import {
  createSoleurGoRunner,
  type QueryFactory,
  DEFAULT_IDLE_REAP_MS,
} from "@/server/soleur-go-runner";

// RED test for Stage 2.21 of plan 2026-04-23-feat-cc-route-via-soleur-go-plan.md.
//
// Streaming-input mode HARD REQUIREMENT: one long-lived Query per
// conversation, reused across turns (so the CLI subprocess doesn't pay the
// ~30s spawn/plugin-load cost on every message). This file pins that
// contract.
//
// Invariants under test:
//   (a) Query reuse: two dispatch() calls for the same conversationId
//       create exactly one Query; the second call pushes a new
//       SDKUserMessage into the existing stream.
//   (b) Idle reap: after `idleReapMs` of inactivity, reapIdle() closes
//       the Query and removes it from activeQueries.
//   (c) Close on terminal: a cost_ceiling or runner_runaway workflow_ended
//       closes the Query and removes it from activeQueries.
//   (d) Post-reap reopen: a dispatch after reap creates a fresh Query,
//       passing `resume: sessionId` to the factory for SDK session
//       continuity.
//   (e) Different conversations get independent Queries.

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

function makeResult(totalCostUsd: number, sessionId = "sess-1"): SDKResultMessage {
  return {
    type: "result",
    subtype: "success",
    duration_ms: 1,
    duration_api_ms: 1,
    is_error: false,
    num_turns: 1,
    result: "",
    stop_reason: "end_turn",
    total_cost_usd: totalCostUsd,
    // biome-ignore lint/suspicious/noExplicitAny: test fixture
    usage: { input_tokens: 0, output_tokens: 0 } as any,
    modelUsage: {},
    permission_denials: [],
    uuid: "00000000-0000-0000-0000-0000000000ff" as never,
    session_id: sessionId,
  } as SDKResultMessage;
}

function createMockQuery(sessionId = "sess-1") {
  let closed = false;
  const queue: SDKMessage[] = [];
  let resolveNext: ((r: IteratorResult<SDKMessage>) => void) | null = null;
  const closeSpy = vi.fn();

  const iter: AsyncGenerator<SDKMessage, void> = {
    async next() {
      if (queue.length > 0) {
        const v = queue.shift()!;
        return { value: v, done: false };
      }
      if (closed) return { value: undefined, done: true };
      return new Promise<IteratorResult<SDKMessage>>((r) => {
        resolveNext = r;
      });
    },
    async return() {
      closed = true;
      return { value: undefined, done: true };
    },
    async throw(e) {
      closed = true;
      throw e;
    },
    async [Symbol.asyncDispose]() {
      closed = true;
    },
    [Symbol.asyncIterator]() {
      return iter;
    },
  };

  function emit(msg: SDKMessage) {
    if (resolveNext) {
      const r = resolveNext;
      resolveNext = null;
      r({ value: msg, done: false });
    } else {
      queue.push(msg);
    }
  }

  function finish() {
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

  return { query: q as Query, emit, finish, closeSpy, sessionId, isClosed: () => closed };
}

function makeEvents() {
  return {
    onText: vi.fn(),
    onToolUse: vi.fn(),
    onWorkflowDetected: vi.fn(),
    onWorkflowEnded: vi.fn(),
    onResult: vi.fn(),
  };
}

async function flush(n = 8) {
  for (let i = 0; i < n; i++) await Promise.resolve();
}

describe("soleur-go-runner lifecycle (Stage 2.21)", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("reuses one Query across multiple dispatches for the same conversationId", async () => {
    const mock = createMockQuery();
    const factory = vi.fn<QueryFactory>(() => mock.query);
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => Date.now(),
    });
    const events = makeEvents();
    const persist = vi.fn().mockResolvedValue(undefined);

    const first = await runner.dispatch({
      conversationId: "c-reuse",
      userId: "u1",
      userMessage: "first",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });
    const second = await runner.dispatch({
      conversationId: "c-reuse",
      userId: "u1",
      userMessage: "second",
      currentRouting: { kind: "soleur_go_active", workflow: "brainstorm" },
      events,
      persistActiveWorkflow: persist,
    });

    expect(factory).toHaveBeenCalledTimes(1);
    expect(first.queryReused).toBe(false);
    expect(second.queryReused).toBe(true);
    expect(runner.activeQueriesSize()).toBe(1);

    mock.finish();
    await flush();
  });

  it("reapIdle() closes Queries idle longer than idleReapMs", async () => {
    const mock = createMockQuery();
    let now = 0;
    const factory = vi.fn<QueryFactory>(() => mock.query);
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => now,
      idleReapMs: 10 * 60 * 1000,
    });
    const events = makeEvents();
    const persist = vi.fn().mockResolvedValue(undefined);

    await runner.dispatch({
      conversationId: "c-idle",
      userId: "u1",
      userMessage: "hello",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });

    now = 9 * 60 * 1000; // 9 min — still fresh
    expect(runner.reapIdle()).toBe(0);
    expect(runner.activeQueriesSize()).toBe(1);

    now = 11 * 60 * 1000; // 11 min — past the 10-min TTL
    expect(runner.reapIdle()).toBe(1);
    expect(mock.closeSpy).toHaveBeenCalled();
    expect(runner.activeQueriesSize()).toBe(0);
    expect(runner.hasActiveQuery("c-idle")).toBe(false);
  });

  it("terminal workflow_ended (cost_ceiling) closes the Query and removes it from the map", async () => {
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      defaultCostCaps: { perWorkflow: {}, default: 0.1 },
    });
    const events = makeEvents();
    const persist = vi.fn().mockResolvedValue(undefined);

    await runner.dispatch({
      conversationId: "c-term",
      userId: "u1",
      userMessage: "spend",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });

    expect(runner.activeQueriesSize()).toBe(1);

    mock.emit(makeResult(1.0));
    await flush();

    expect(mock.closeSpy).toHaveBeenCalled();
    expect(runner.hasActiveQuery("c-term")).toBe(false);
    expect(runner.activeQueriesSize()).toBe(0);
  });

  it("post-reap dispatch opens a fresh Query with resume: sessionId for SDK session continuity", async () => {
    const first = createMockQuery("sess-A");
    const second = createMockQuery("sess-A");
    const calls: Array<{ resumeSessionId: string | undefined }> = [];
    let nth = 0;
    const factory: QueryFactory = (args) => {
      calls.push({ resumeSessionId: args.resumeSessionId });
      return nth++ === 0 ? first.query : second.query;
    };
    let now = 0;
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => now,
      idleReapMs: 10 * 60 * 1000,
    });
    const events = makeEvents();
    const persist = vi.fn().mockResolvedValue(undefined);

    await runner.dispatch({
      conversationId: "c-resume",
      userId: "u1",
      userMessage: "1",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
      sessionId: null,
    });
    first.emit(makeResult(0.01, "sess-A"));
    await flush();

    // Reap the first Query.
    now = 20 * 60 * 1000;
    runner.reapIdle();
    expect(runner.hasActiveQuery("c-resume")).toBe(false);

    // Second dispatch should open a fresh Query and pass resume: "sess-A".
    await runner.dispatch({
      conversationId: "c-resume",
      userId: "u1",
      userMessage: "2",
      currentRouting: { kind: "soleur_go_active", workflow: "brainstorm" },
      events,
      persistActiveWorkflow: persist,
      sessionId: "sess-A",
    });

    expect(calls).toHaveLength(2);
    expect(calls[1]!.resumeSessionId).toBe("sess-A");
    second.finish();
    await flush();
  });

  it("different conversationIds get independent Queries", async () => {
    const m1 = createMockQuery("s1");
    const m2 = createMockQuery("s2");
    let nth = 0;
    const factory: QueryFactory = () => (nth++ === 0 ? m1.query : m2.query);
    const runner = createSoleurGoRunner({
      queryFactory: factory,
      now: () => Date.now(),
    });
    const events = makeEvents();
    const persist = vi.fn().mockResolvedValue(undefined);

    await runner.dispatch({
      conversationId: "A",
      userId: "u1",
      userMessage: "x",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });
    await runner.dispatch({
      conversationId: "B",
      userId: "u1",
      userMessage: "y",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });

    expect(runner.activeQueriesSize()).toBe(2);
    expect(runner.hasActiveQuery("A")).toBe(true);
    expect(runner.hasActiveQuery("B")).toBe(true);

    m1.finish();
    m2.finish();
    await flush();
  });

  it("exports DEFAULT_IDLE_REAP_MS = 10 minutes", () => {
    expect(DEFAULT_IDLE_REAP_MS).toBe(10 * 60 * 1000);
  });
});
