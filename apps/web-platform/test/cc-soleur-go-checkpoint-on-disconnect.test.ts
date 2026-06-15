/**
 * #5356 — cc-soleur-go in-flight work checkpoint parity (RED).
 *
 * Plan: knowledge-base/project/plans/2026-06-15-feat-cc-soleur-go-checkpoint-parity-plan.md
 *
 * This file pins the RUNNER-side half of the fix: `closeConversation` must
 * thread an optional `reason` through the shared `closeQuery` path to the
 * `onCloseQuery` close hook. Only a `"disconnected"` close (from the grace
 * timer, Phase 4) carries a reason; natural completion (`emitWorkflowEnded`),
 * idle reap (`reapIdle`), and a bare `closeConversation()` leave `reason`
 * undefined → the dispatcher hook must NOT checkpoint.
 *
 * The SDK is removed from the assertion path: a fake `query` that pends
 * forever until `close()` (mirrors `cc-dispatcher-bash-gate.test.ts` T13b),
 * direct runner-method invocation, and a spy `onCloseQuery`. No `query({prompt})`.
 *
 * RED before GREEN per AGENTS.md `cq-write-failing-tests-before`.
 */
import { describe, it, expect, vi } from "vitest";

import { createSoleurGoRunner } from "@/server/soleur-go-runner";

// A Query stub whose async iterator never resolves — the runner keeps the
// `activeQueries` entry live until an explicit close path runs.
function makeFakeQuery() {
  return {
    async *[Symbol.asyncIterator]() {
      await new Promise<void>(() => {
        /* never resolves */
      });
    },
    close: vi.fn(),
    interrupt: vi.fn(),
    // biome-ignore lint/suspicious/noExplicitAny: minimal Query stub
  } as any;
}

const SILENT_EVENTS = {
  onText: () => {},
  onToolUse: () => {},
  onWorkflowDetected: () => {},
  onWorkflowEnded: () => {},
  onResult: () => {},
};

async function seedLiveQuery(
  runner: ReturnType<typeof createSoleurGoRunner>,
  conversationId: string,
  userId: string,
) {
  await runner.dispatch({
    conversationId,
    userId,
    userMessage: "trigger query construction",
    currentRouting: { kind: "soleur_go_pending" },
    events: SILENT_EVENTS,
    persistActiveWorkflow: async () => {},
  });
  expect(runner.hasActiveQuery(conversationId)).toBe(true);
}

describe("#5356 cc runner — reason threads to onCloseQuery", () => {
  it("T2(runner): closeConversation(convId, 'disconnected') fires onCloseQuery with reason 'disconnected'", async () => {
    const calls: Array<{
      conversationId: string;
      userId: string;
      reason?: string;
    }> = [];
    const runner = createSoleurGoRunner({
      queryFactory: () => makeFakeQuery(),
      onCloseQuery: (args) => calls.push(args),
    });

    await seedLiveQuery(runner, "conv-d", "u-d");
    runner.closeConversation("conv-d", "disconnected");

    expect(calls).toEqual([
      { conversationId: "conv-d", userId: "u-d", reason: "disconnected" },
    ]);
    expect(runner.hasActiveQuery("conv-d")).toBe(false);
  });

  it("T3(a): bare closeConversation(convId) fires onCloseQuery with reason undefined (no checkpoint)", async () => {
    const calls: Array<{ reason?: string }> = [];
    const runner = createSoleurGoRunner({
      queryFactory: () => makeFakeQuery(),
      onCloseQuery: (args) => calls.push(args),
    });

    await seedLiveQuery(runner, "conv-n", "u-n");
    runner.closeConversation("conv-n");

    expect(calls).toHaveLength(1);
    expect(calls[0].reason).toBeUndefined();
  });

  it("T3(b): idle reap fires onCloseQuery with reason undefined (no checkpoint)", async () => {
    const calls: Array<{ reason?: string }> = [];
    let nowMs = 0;
    const runner = createSoleurGoRunner({
      queryFactory: () => makeFakeQuery(),
      now: () => nowMs,
      idleReapMs: 1000,
      onCloseQuery: (args) => calls.push(args),
    });

    await seedLiveQuery(runner, "conv-r", "u-r");
    nowMs += 5000;
    expect(runner.reapIdle()).toBe(1);

    expect(calls).toHaveLength(1);
    expect(calls[0].reason).toBeUndefined();
  });

  it("T-race: closeConversation('disconnected') after the entry was already removed is a no-op (no onCloseQuery)", async () => {
    const calls: Array<{ reason?: string }> = [];
    const runner = createSoleurGoRunner({
      queryFactory: () => makeFakeQuery(),
      onCloseQuery: (args) => calls.push(args),
    });

    await seedLiveQuery(runner, "conv-race", "u-race");
    // Natural completion path removed the entry synchronously.
    runner.closeConversation("conv-race");
    expect(calls).toHaveLength(1);

    // A subsequent grace-timer signal finds no entry → no second close hook.
    runner.closeConversation("conv-race", "disconnected");
    expect(calls).toHaveLength(1);
  });
});
