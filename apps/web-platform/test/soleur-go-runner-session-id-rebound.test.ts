/**
 * RED tests for issue #3266 Phase 3 — soleur-go-runner emits an
 * `onSessionIdCaptured(sessionId)` event exactly once per state on the
 * first non-null `session_id` observed in an `SDKResultMessage`.
 *
 * Once-only contract: duplicate result messages with the same session_id
 * MUST NOT re-fire. A runner that never observes a session_id MUST NOT
 * fire.
 *
 * Mirrors the test-stub pattern in `soleur-go-runner-lifecycle.test.ts`
 * (mock Query + factory + emit/finish controls).
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type {
  Query,
  SDKMessage,
  SDKResultMessage,
} from "@anthropic-ai/claude-agent-sdk";

import {
  createSoleurGoRunner,
  type QueryFactory,
} from "@/server/soleur-go-runner";

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

function makeResult(opts: {
  totalCostUsd?: number;
  sessionId?: string | null;
}): SDKResultMessage {
  return {
    type: "result",
    subtype: "success",
    duration_ms: 1,
    duration_api_ms: 1,
    is_error: false,
    num_turns: 1,
    result: "",
    stop_reason: "end_turn",
    total_cost_usd: opts.totalCostUsd ?? 0,
    // biome-ignore lint/suspicious/noExplicitAny: test fixture
    usage: { input_tokens: 0, output_tokens: 0 } as any,
    modelUsage: {},
    permission_denials: [],
    uuid: "00000000-0000-0000-0000-0000000000ff" as never,
    session_id: (opts.sessionId ?? "") as string,
  } as SDKResultMessage;
}

function createMockQuery() {
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

  return { query: q as Query, emit, finish, closeSpy, isClosed: () => closed };
}

function makeEvents() {
  return {
    onText: vi.fn(),
    onToolUse: vi.fn(),
    onWorkflowDetected: vi.fn(),
    onWorkflowEnded: vi.fn(),
    onResult: vi.fn(),
    onTextTurnEnd: vi.fn(),
    onSessionIdCaptured: vi.fn(),
  };
}

async function flush(n = 16) {
  for (let i = 0; i < n; i++) await Promise.resolve();
}

describe("soleur-go-runner — onSessionIdCaptured (#3266 Phase 3)", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("fires exactly once on first non-null session_id from a result message", async () => {
    const mock = createMockQuery();
    const factory = vi.fn<QueryFactory>(() => mock.query);
    const runner = createSoleurGoRunner({ queryFactory: factory });
    const events = makeEvents();
    const persist = vi.fn().mockResolvedValue(undefined);

    await runner.dispatch({
      conversationId: "c-cap-1",
      userId: "u1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });

    mock.emit(makeResult({ sessionId: "sess-Z" }));
    await flush();

    expect(events.onSessionIdCaptured).toHaveBeenCalledTimes(1);
    expect(events.onSessionIdCaptured).toHaveBeenCalledWith("sess-Z");

    mock.finish();
    await flush();
  });

  it("does NOT re-fire on a duplicate result message carrying the same session_id", async () => {
    const mock = createMockQuery();
    const factory = vi.fn<QueryFactory>(() => mock.query);
    const runner = createSoleurGoRunner({ queryFactory: factory });
    const events = makeEvents();
    const persist = vi.fn().mockResolvedValue(undefined);

    await runner.dispatch({
      conversationId: "c-cap-2",
      userId: "u1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });

    mock.emit(makeResult({ sessionId: "sess-A" }));
    await flush();
    mock.emit(makeResult({ sessionId: "sess-A" }));
    await flush();

    expect(events.onSessionIdCaptured).toHaveBeenCalledTimes(1);
    expect(events.onSessionIdCaptured).toHaveBeenCalledWith("sess-A");

    mock.finish();
    await flush();
  });

  it("does NOT fire on warm-resume cold-Query (state seeded with sessionId; SDK echoes same value)", async () => {
    // Steady-state scenario: cc-dispatcher's previous cold-Query persisted
    // sess-W to DB; ws-handler now forwards it back as args.sessionId on
    // the next cold-Query construction. The SDK echoes the same value in
    // its first result. The runner must NOT re-fire the writer.
    const mock = createMockQuery();
    const factory = vi.fn<QueryFactory>(() => mock.query);
    const runner = createSoleurGoRunner({ queryFactory: factory });
    const events = makeEvents();
    const persist = vi.fn().mockResolvedValue(undefined);

    await runner.dispatch({
      conversationId: "c-cap-warm",
      userId: "u1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
      sessionId: "sess-W",
    });

    mock.emit(makeResult({ sessionId: "sess-W" }));
    await flush();

    expect(events.onSessionIdCaptured).not.toHaveBeenCalled();

    mock.finish();
    await flush();
  });

  it("fires on SDK rebind within the same state (state had sess-A, SDK returns sess-B)", async () => {
    // Defensive: should not happen in practice (SDK does not reuse
    // session_ids across Queries) but a rebind MUST fire to keep the
    // persisted value aligned with the runner's in-memory state.
    const mock = createMockQuery();
    const factory = vi.fn<QueryFactory>(() => mock.query);
    const runner = createSoleurGoRunner({ queryFactory: factory });
    const events = makeEvents();
    const persist = vi.fn().mockResolvedValue(undefined);

    await runner.dispatch({
      conversationId: "c-cap-rebind",
      userId: "u1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
      sessionId: "sess-A",
    });

    mock.emit(makeResult({ sessionId: "sess-B" }));
    await flush();

    expect(events.onSessionIdCaptured).toHaveBeenCalledTimes(1);
    expect(events.onSessionIdCaptured).toHaveBeenCalledWith("sess-B");

    mock.finish();
    await flush();
  });

  it("does NOT fire when the runner never observes a non-empty session_id", async () => {
    const mock = createMockQuery();
    const factory = vi.fn<QueryFactory>(() => mock.query);
    const runner = createSoleurGoRunner({ queryFactory: factory });
    const events = makeEvents();
    const persist = vi.fn().mockResolvedValue(undefined);

    await runner.dispatch({
      conversationId: "c-cap-3",
      userId: "u1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });

    mock.emit(makeResult({ sessionId: "" }));
    await flush();

    expect(events.onSessionIdCaptured).not.toHaveBeenCalled();

    mock.finish();
    await flush();
  });
});
