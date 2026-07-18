import {
  describe,
  it,
  expect,
  vi,
  beforeEach,
  afterEach,
} from "vitest";

import {
  createSoleurGoRunner,
  type QueryFactory,
  DEFAULT_IDLE_REAP_MS,
} from "@/server/soleur-go-runner";
import {
  createMockQueryLean as createMockQuery,
  flushMicrotasks,
  makeResult,
} from "./helpers/soleur-go-fixtures";

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

function makeEvents() {
  return {
    onText: vi.fn(),
    onToolUse: vi.fn(),
    onWorkflowDetected: vi.fn(),
    onWorkflowEnded: vi.fn(),
    onResult: vi.fn(),
  };
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
      persona: "command_center",
      conversationId: "c-reuse",
      userId: "u1",
      userMessage: "first",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });
    const second = await runner.dispatch({
      persona: "command_center",
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
    await flushMicrotasks(8);
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
      persona: "command_center",
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
      persona: "command_center",
      conversationId: "c-term",
      userId: "u1",
      userMessage: "spend",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });

    expect(runner.activeQueriesSize()).toBe(1);

    mock.emit(makeResult(1.0));
    await flushMicrotasks(8);

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
      persona: "command_center",
      conversationId: "c-resume",
      userId: "u1",
      userMessage: "1",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
      sessionId: null,
    });
    first.emit(makeResult(0.01, "sess-A"));
    await flushMicrotasks(8);

    // Reap the first Query.
    now = 20 * 60 * 1000;
    runner.reapIdle();
    expect(runner.hasActiveQuery("c-resume")).toBe(false);

    // Second dispatch should open a fresh Query and pass resume: "sess-A".
    await runner.dispatch({
      persona: "command_center",
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
    await flushMicrotasks(8);
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
      persona: "command_center",
      conversationId: "A",
      userId: "u1",
      userMessage: "x",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });
    await runner.dispatch({
      persona: "command_center",
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
    await flushMicrotasks(8);
  });

  it("exports DEFAULT_IDLE_REAP_MS = 10 minutes", () => {
    expect(DEFAULT_IDLE_REAP_MS).toBe(10 * 60 * 1000);
  });

  // #5371 — closeAllForShutdown (SIGTERM drain). Contract:
  //   - closes EVERY active query, aborting WITHOUT a checkpoint reason
  //     (legacy `abortAllSessions` parity — server_shutdown does not
  //     checkpoint), so onCloseQuery fires with `reason === undefined`;
  //   - does NOT skip `awaitingUser` (a deploy tears down review-gate
  //     queries too — unlike reapIdle);
  //   - is idempotent against the grace-abort overlap (a conversation the
  //     ws-handler already closed via closeConversation(id,"disconnected")
  //     is not re-fired).

  it("closeAllForShutdown closes active queries WITHOUT a checkpoint reason (AC4)", async () => {
    const onCloseQuery = vi.fn();
    const m1 = createMockQuery();
    const m2 = createMockQuery();
    let nth = 0;
    const runner = createSoleurGoRunner({
      queryFactory: () => (nth++ === 0 ? m1.query : m2.query),
      now: () => Date.now(),
      onCloseQuery,
    });
    const events = makeEvents();
    const persist = vi.fn().mockResolvedValue(undefined);

    await runner.dispatch({
      persona: "command_center",
      conversationId: "d1",
      userId: "u1",
      userMessage: "x",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });
    await runner.dispatch({
      persona: "command_center",
      conversationId: "d2",
      userId: "u1",
      userMessage: "y",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });
    expect(runner.activeQueriesSize()).toBe(2);

    const drained = runner.closeAllForShutdown();

    expect(drained).toBe(2);
    expect(runner.activeQueriesSize()).toBe(0);
    expect(m1.closeSpy).toHaveBeenCalled();
    expect(m2.closeSpy).toHaveBeenCalled();
    expect(onCloseQuery).toHaveBeenCalledTimes(2);
    for (const call of onCloseQuery.mock.calls) {
      // The checkable contract: a `"disconnected"` reason is the ONLY
      // thing that triggers a checkpoint via handleCcCloseQuery. Drain
      // must pass none.
      expect(call[0]?.reason).toBeUndefined();
    }
  });

  it("closeAllForShutdown does NOT re-fire on an already grace-aborted query (AC6)", async () => {
    const onCloseQuery = vi.fn();
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => Date.now(),
      onCloseQuery,
    });
    const events = makeEvents();
    const persist = vi.fn().mockResolvedValue(undefined);

    await runner.dispatch({
      persona: "command_center",
      conversationId: "g1",
      userId: "u1",
      userMessage: "x",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });

    // ws-handler grace timer fired first: closeConversation → closeQuery, which
    // DELETES the entry from activeQueries (soleur-go-runner.ts). So the drain
    // below observes an empty map and returns 0 via absence — the in-loop
    // `if (state.closed) continue` skip is belt-and-suspenders for a
    // closed-but-still-present entry that no public caller can produce (every
    // caller deletes). This test pins the OBSERVABLE contract (the drain does
    // not double-fire onCloseQuery / query.close() after a grace-abort), not the
    // unreachable guard line.
    runner.closeConversation("g1", "disconnected");
    expect(onCloseQuery).toHaveBeenCalledTimes(1);
    expect(onCloseQuery.mock.calls[0]?.[0]?.reason).toBe("disconnected");
    expect(mock.closeSpy).toHaveBeenCalledTimes(1);

    // Now the SIGTERM drain runs — exactly one onCloseQuery AND one query.close()
    // total across both the grace-abort and the drain (no double-close).
    const drained = runner.closeAllForShutdown();

    expect(drained).toBe(0);
    expect(onCloseQuery).toHaveBeenCalledTimes(1);
    expect(mock.closeSpy).toHaveBeenCalledTimes(1);
  });

  it("reapIdle skips awaitingUser but closeAllForShutdown closes it (AC7)", async () => {
    const onCloseQuery = vi.fn();
    let now = 0;
    const mock = createMockQuery();
    const runner = createSoleurGoRunner({
      queryFactory: () => mock.query,
      now: () => now,
      idleReapMs: 10 * 60 * 1000,
      onCloseQuery,
    });
    const events = makeEvents();
    const persist = vi.fn().mockResolvedValue(undefined);

    await runner.dispatch({
      persona: "command_center",
      conversationId: "a1",
      userId: "u1",
      userMessage: "x",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });
    runner.notifyAwaitingUser("a1", true);

    now = 30 * 60 * 1000; // well past the 10-min idle window
    // Reaper skips the paused (human-review-gate) query.
    expect(runner.reapIdle()).toBe(0);
    expect(runner.activeQueriesSize()).toBe(1);

    // Drain does NOT copy the reaper's awaitingUser skip — a deploy must
    // tear down review-gate-parked queries too.
    const drained = runner.closeAllForShutdown();

    expect(drained).toBe(1);
    expect(runner.activeQueriesSize()).toBe(0);
    expect(onCloseQuery).toHaveBeenCalledTimes(1);
    expect(onCloseQuery.mock.calls[0]?.[0]?.reason).toBeUndefined();
  });
});
