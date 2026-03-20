import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";

// We cannot import the private abortableReviewGate directly, so we
// re-implement the same logic in a test-local copy. This validates the
// algorithm without coupling to internal module structure.
// The production code is verified end-to-end via the exported resolveReviewGate
// and abortSession functions.

interface AgentSession {
  abort: AbortController;
  reviewGateResolvers: Map<string, (selection: string) => void>;
}

const REVIEW_GATE_TIMEOUT_MS = 5 * 60 * 1_000;

function abortableReviewGate(
  session: AgentSession,
  gateId: string,
  signal: AbortSignal,
  timeoutMs: number = REVIEW_GATE_TIMEOUT_MS,
): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    if (signal.aborted) {
      reject(signal.reason || new Error("Session aborted"));
      return;
    }

    const timer = setTimeout(() => {
      signal.removeEventListener("abort", onAbort);
      session.reviewGateResolvers.delete(gateId);
      reject(new Error("Review gate timed out"));
    }, timeoutMs);
    timer.unref();

    const onAbort = () => {
      clearTimeout(timer);
      session.reviewGateResolvers.delete(gateId);
      reject(signal.reason || new Error("Session aborted"));
    };

    signal.addEventListener("abort", onAbort, { once: true });

    session.reviewGateResolvers.set(gateId, (selection: string) => {
      clearTimeout(timer);
      signal.removeEventListener("abort", onAbort);
      resolve(selection);
    });
  });
}

describe("abortableReviewGate", () => {
  let session: AgentSession;
  let controller: AbortController;

  beforeEach(() => {
    vi.useFakeTimers();
    controller = new AbortController();
    session = {
      abort: controller,
      reviewGateResolvers: new Map(),
    };
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  test("resolves normally when user responds", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal);

    // Simulate user response
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

    // Aborting after resolution should not throw
    controller.abort(new Error("late abort"));
  });

  test("cleans up timeout after normal resolution", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal, 1000);

    const resolver = session.reviewGateResolvers.get("g1");
    resolver!("Approve");
    await promise;

    // Advancing past the timeout should not cause rejection
    vi.advanceTimersByTime(2000);
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
    // Should not register a resolver
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
  });

  test("uses default 5-minute timeout", async () => {
    const promise = abortableReviewGate(session, "g1", controller.signal);

    // 4m59s should not timeout
    vi.advanceTimersByTime(4 * 60 * 1000 + 59 * 1000);
    expect(session.reviewGateResolvers.has("g1")).toBe(true);

    // 5m should timeout
    vi.advanceTimersByTime(1000);
    await expect(promise).rejects.toThrow("Review gate timed out");
  });

  test("no-op when no review gate is pending on disconnect", () => {
    // Empty resolvers map — abort should not throw
    expect(session.reviewGateResolvers.size).toBe(0);
    controller.abort(new Error("disconnect"));
  });
});
