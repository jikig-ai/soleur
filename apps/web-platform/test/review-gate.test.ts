import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import {
  abortableReviewGate,
  REVIEW_GATE_TIMEOUT_MS,
  type AgentSession,
} from "../server/review-gate";

describe("abortableReviewGate", () => {
  let session: AgentSession;
  let controller: AbortController;

  beforeEach(() => {
    vi.useFakeTimers();
    controller = new AbortController();
    session = {
      abort: controller,
      reviewGateResolvers: new Map(),
      sessionId: null,
    };
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  test("resolves normally when user responds", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal);

    const resolver = session.reviewGateResolvers.get("g1");
    expect(resolver).toBeDefined();
    resolver!("Approve");

    const result = await promise;
    expect(result).toBe("Approve");
  });

  test("cleans up abort listener after normal resolution", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal);

    const resolver = session.reviewGateResolvers.get("g1");
    resolver!("Approve");
    await promise;

    // Aborting after resolution should not throw — the listener was removed
    controller.abort(new Error("late abort"));
  });

  test("cleans up timeout after normal resolution", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal, 1000);

    const resolver = session.reviewGateResolvers.get("g1");
    resolver!("Approve");
    await promise;

    // Advancing past the timeout should not cause rejection
    vi.advanceTimersByTime(2000);
    expect(vi.getTimerCount()).toBe(0);
  });

  test("rejects when abort signal fires", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal);

    controller.abort(new Error("Session aborted: user disconnected"));

    await expect(promise).rejects.toThrow("Session aborted: user disconnected");
  });

  test("removes resolver from map on abort", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal);
    expect(session.reviewGateResolvers.has("g1")).toBe(true);

    controller.abort(new Error("disconnect"));
    await promise.catch(() => {});

    expect(session.reviewGateResolvers.has("g1")).toBe(false);
  });

  test("rejects when timeout elapses", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal, 1000);

    vi.advanceTimersByTime(1000);

    await expect(promise).rejects.toThrow("Review gate timed out");
  });

  test("removes resolver from map on timeout", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal, 1000);
    expect(session.reviewGateResolvers.has("g1")).toBe(true);

    vi.advanceTimersByTime(1000);
    await promise.catch(() => {});

    expect(session.reviewGateResolvers.has("g1")).toBe(false);
  });

  test("rejects synchronously if signal already aborted", async () => {
    controller.abort(new Error("already aborted"));

    const promise = abortableReviewGate(session, "g1", controller.signal);

    await expect(promise).rejects.toThrow("already aborted");
    expect(session.reviewGateResolvers.has("g1")).toBe(false);
  });

  test("uses signal.reason when abort is called without explicit reason", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal);

    controller.abort();

    // Node.js sets signal.reason to a DOMException("This operation was aborted")
    await expect(promise).rejects.toThrow("aborted");
  });

  test("cleans up timeout on abort", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal, 1000);

    controller.abort(new Error("disconnect"));
    await promise.catch(() => {});

    // Advancing past timeout should not cause additional rejection
    vi.advanceTimersByTime(2000);
    expect(vi.getTimerCount()).toBe(0);
  });

  test("uses default 5-minute timeout", async () => {
    expect(REVIEW_GATE_TIMEOUT_MS).toBe(5 * 60 * 1_000);

    const promise = abortableReviewGate(session, "g1", controller.signal);

    // 4m59s should not timeout
    vi.advanceTimersByTime(4 * 60 * 1000 + 59 * 1000);
    expect(session.reviewGateResolvers.has("g1")).toBe(true);

    // 5m should timeout
    vi.advanceTimersByTime(1000);
    await expect(promise).rejects.toThrow("Review gate timed out");
  });

  test("no-op when no review gate is pending on disconnect", () => {
    expect(session.reviewGateResolvers.size).toBe(0);
    controller.abort(new Error("disconnect"));
    // Map should remain empty and not throw
    expect(session.reviewGateResolvers.size).toBe(0);
  });
});
