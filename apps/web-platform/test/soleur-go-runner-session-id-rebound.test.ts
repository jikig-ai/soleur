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

import {
  createSoleurGoRunner,
  type QueryFactory,
} from "@/server/soleur-go-runner";
import {
  createMockQueryLean as createMockQuery,
  flushMicrotasks,
  makeResult,
} from "./helpers/soleur-go-fixtures";

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
      persona: "command_center",
      conversationId: "c-cap-1",
      userId: "u1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });

    mock.emit(makeResult({ sessionId: "sess-Z" }));
    await flushMicrotasks(16);

    expect(events.onSessionIdCaptured).toHaveBeenCalledTimes(1);
    expect(events.onSessionIdCaptured).toHaveBeenCalledWith("sess-Z");

    mock.finish();
    await flushMicrotasks(16);
  });

  it("does NOT re-fire on a duplicate result message carrying the same session_id", async () => {
    const mock = createMockQuery();
    const factory = vi.fn<QueryFactory>(() => mock.query);
    const runner = createSoleurGoRunner({ queryFactory: factory });
    const events = makeEvents();
    const persist = vi.fn().mockResolvedValue(undefined);

    await runner.dispatch({
      persona: "command_center",
      conversationId: "c-cap-2",
      userId: "u1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });

    mock.emit(makeResult({ sessionId: "sess-A" }));
    await flushMicrotasks(16);
    mock.emit(makeResult({ sessionId: "sess-A" }));
    await flushMicrotasks(16);

    expect(events.onSessionIdCaptured).toHaveBeenCalledTimes(1);
    expect(events.onSessionIdCaptured).toHaveBeenCalledWith("sess-A");

    mock.finish();
    await flushMicrotasks(16);
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
      persona: "command_center",
      conversationId: "c-cap-warm",
      userId: "u1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
      sessionId: "sess-W",
    });

    mock.emit(makeResult({ sessionId: "sess-W" }));
    await flushMicrotasks(16);

    expect(events.onSessionIdCaptured).not.toHaveBeenCalled();

    mock.finish();
    await flushMicrotasks(16);
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
      persona: "command_center",
      conversationId: "c-cap-rebind",
      userId: "u1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
      sessionId: "sess-A",
    });

    mock.emit(makeResult({ sessionId: "sess-B" }));
    await flushMicrotasks(16);

    expect(events.onSessionIdCaptured).toHaveBeenCalledTimes(1);
    expect(events.onSessionIdCaptured).toHaveBeenCalledWith("sess-B");

    mock.finish();
    await flushMicrotasks(16);
  });

  it("does NOT fire when the runner never observes a non-empty session_id", async () => {
    const mock = createMockQuery();
    const factory = vi.fn<QueryFactory>(() => mock.query);
    const runner = createSoleurGoRunner({ queryFactory: factory });
    const events = makeEvents();
    const persist = vi.fn().mockResolvedValue(undefined);

    await runner.dispatch({
      persona: "command_center",
      conversationId: "c-cap-3",
      userId: "u1",
      userMessage: "hi",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: persist,
    });

    mock.emit(makeResult({ sessionId: "" }));
    await flushMicrotasks(16);

    expect(events.onSessionIdCaptured).not.toHaveBeenCalled();

    mock.finish();
    await flushMicrotasks(16);
  });
});
