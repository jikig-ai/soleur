/**
 * Abort-aware review gate promise with timeout safety net.
 *
 * Extracted from agent-runner.ts for unit testability without SDK/Supabase
 * dependencies. Follows the same extraction pattern as tool-path-checker.ts.
 */

export interface AgentSession {
  abort: AbortController;
  reviewGateResolvers: Map<string, (selection: string) => void>;
}

export const REVIEW_GATE_TIMEOUT_MS = 5 * 60 * 1_000; // 5 minutes

/**
 * Create a promise that resolves when the user responds to a review gate,
 * or rejects when the session is aborted (disconnect) or the timeout elapses.
 */
export function abortableReviewGate(
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
