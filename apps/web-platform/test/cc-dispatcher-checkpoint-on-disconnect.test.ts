/**
 * #5356 — cc dispatcher close hook `handleCcCloseQuery` (RED).
 *
 * Plan: knowledge-base/project/plans/2026-06-15-feat-cc-soleur-go-checkpoint-parity-plan.md
 *
 * The `onCloseQuery` hook wired in `getSoleurGoRunner` must:
 *   - ALWAYS drain `_ccBashGates` for the conversation (existing behavior), and
 *   - checkpoint the in-flight work ONLY when `reason === "disconnected"` (AC4).
 *
 * `checkpointInflightWorkForConversation` is mocked (cross-module seam) so the
 * test asserts the conditional invocation without touching git plumbing.
 *
 * RED before GREEN per AGENTS.md `cq-write-failing-tests-before`.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";

const { mockCheckpointForConversation } = vi.hoisted(() => ({
  mockCheckpointForConversation: vi.fn(async () => {}),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: vi.fn(),
  tool: vi.fn(),
  createSdkMcpServer: vi.fn(),
}));
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));
vi.mock("@/server/ws-handler", () => ({ sendToClient: vi.fn() }));
vi.mock("@/server/notifications", () => ({ notifyOfflineUser: vi.fn() }));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  mirrorWithDebounce: vi.fn(),
  __resetMirrorDebounceForTests: vi.fn(),
  MIRROR_DEBOUNCE_MS: 5 * 60 * 1000,
}));
vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }),
}));
vi.mock("@/server/inflight-checkpoint", () => ({
  checkpointInflightWorkForConversation: mockCheckpointForConversation,
}));

import {
  handleCcCloseQuery,
  registerCcBashGate,
  resolveCcBashGate,
  reapIdleCcQueries,
  drainCcQueriesForShutdown,
  startCcIdleReaper,
  __resetDispatcherForTests,
  __setCcRunnerForTests,
} from "@/server/cc-dispatcher";
import type { SoleurGoRunner } from "@/server/soleur-go-runner";

function seedBashGate(userId: string, conversationId: string) {
  const session = {
    abort: new AbortController(),
    reviewGateResolvers: new Map<
      string,
      { resolve: (s: string) => void; options: string[] }
    >([["g1", { resolve: () => {}, options: [] }]]),
    sessionId: null,
  };
  registerCcBashGate({ userId, conversationId, gateId: "g1", session });
}

function gateIsLive(userId: string, conversationId: string): boolean {
  return resolveCcBashGate({
    userId,
    conversationId,
    gateId: "g1",
    selection: "Approve",
  });
}

describe("#5356 handleCcCloseQuery", () => {
  beforeEach(() => {
    __resetDispatcherForTests();
    mockCheckpointForConversation.mockClear();
  });

  it("T2(dispatcher): reason 'disconnected' checkpoints AND drains the bash gate", () => {
    seedBashGate("u-d", "conv-d");

    handleCcCloseQuery({
      conversationId: "conv-d",
      userId: "u-d",
      reason: "disconnected",
    });

    expect(mockCheckpointForConversation).toHaveBeenCalledTimes(1);
    // cc call site tags the Sentry stage distinctly while sharing the
    // `op: "checkpoint-on-abort"` monitor with the legacy path.
    expect(mockCheckpointForConversation).toHaveBeenCalledWith(
      "u-d",
      "conv-d",
      "cc-resolve-workspace-path",
    );
    // Gate was drained — a subsequent resolve returns false.
    expect(gateIsLive("u-d", "conv-d")).toBe(false);
  });

  it("T3(dispatcher): no reason drains the bash gate but does NOT checkpoint", () => {
    seedBashGate("u-n", "conv-n");

    handleCcCloseQuery({ conversationId: "conv-n", userId: "u-n" });

    expect(mockCheckpointForConversation).not.toHaveBeenCalled();
    expect(gateIsLive("u-n", "conv-n")).toBe(false);
  });

  it("T5(dispatcher): bash-gate drain does NOT depend on checkpoint completion", () => {
    // The user-facing drain runs synchronously BEFORE the fire-and-forget
    // checkpoint. A never-settling checkpoint must not leave the gate live.
    mockCheckpointForConversation.mockImplementationOnce(
      () => new Promise<void>(() => {}),
    );
    seedBashGate("u-s", "conv-s");

    handleCcCloseQuery({
      conversationId: "conv-s",
      userId: "u-s",
      reason: "disconnected",
    });

    expect(mockCheckpointForConversation).toHaveBeenCalledTimes(1);
    // Drained synchronously, independent of the still-pending checkpoint.
    expect(gateIsLive("u-s", "conv-s")).toBe(false);
  });
});

describe("#5371 cc idle-reaper scheduling + SIGTERM drain accessors", () => {
  beforeEach(() => {
    __resetDispatcherForTests(); // sets _runner = null
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("AC5: reaper/drain accessors no-op when no runner exists yet", () => {
    // Lazy singleton: a deploy with no cc traffic since boot has _runner null.
    // Both accessors must return 0 without forcing runner creation.
    expect(reapIdleCcQueries()).toBe(0);
    expect(drainCcQueriesForShutdown()).toBe(0);
  });

  it("AC1: startCcIdleReaper schedules reapIdle() on the live runner", () => {
    vi.useFakeTimers();
    const reapIdle = vi.fn(() => 0);
    // Only `reapIdle` is exercised by the scheduler path; the rest of the
    // SoleurGoRunner surface is irrelevant here.
    const stub = { reapIdle } as unknown as SoleurGoRunner;
    __setCcRunnerForTests(stub);

    const timer = startCcIdleReaper();
    // Returned timer is unref'd by the scheduler (mirrors startStuckActiveReaper
    // in agent-runner.ts) — never blocks shutdown. `unref` is a no-op under fake
    // timers but must not throw.
    expect(typeof timer.unref).toBe("function");
    expect(reapIdle).not.toHaveBeenCalled();

    // Pin the cadence semantically (gate-present AND boundary): one tick short
    // of the interval fires nothing; crossing it fires exactly once. A naive
    // single advanceTimersByTime can't distinguish "fires at the interval" from
    // "fires on any tick".
    vi.advanceTimersByTime(299_999);
    expect(reapIdle).not.toHaveBeenCalled();
    vi.advanceTimersByTime(1); // crosses CC_IDLE_REAPER_INTERVAL_MS (300_000)
    expect(reapIdle).toHaveBeenCalledTimes(1);
    vi.advanceTimersByTime(300_000);
    expect(reapIdle).toHaveBeenCalledTimes(2);

    clearInterval(timer);
  });
});
