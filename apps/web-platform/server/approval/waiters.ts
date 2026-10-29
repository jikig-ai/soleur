/**
 * In-memory waiter registry and the bounded wait loop for the gated branch (#4672).
 *
 * Correctness never depends on the in-memory wake: the loop re-reads the approval row (one indexed read by id,
 * about every 5 s with jitter, at most `MAX_POLL_READS`), so a decision made on ANOTHER host over HTTP is seen
 * within one poll. The registry only shortens the latency when the decide lands on this process: the wake is a
 * HINT that triggers one database read, never a verdict (a wake that the row does not confirm is not an allow).
 *
 * The registry is keyed by approval id and is a separate namespace from `review-gate.ts` waiters: a
 * `review_gate_response` can never resolve an approval waiter (the ws-handler guard relies on this).
 *
 * Loop contract: the signal is checked FIRST (an aborted call performs no read and cannot allow); a transient read
 * error continues until the deadline and never allows; only `decided` carries a status, and the CALLER maps
 * `approved` to a consume. A wait that ends `timeout` or `aborted` leaves the row `pending` (the durable request
 * outlives the in-session wait).
 */

export type WaitStatus = "pending" | "approved" | "rejected" | "expired" | "consumed";

export const DEFAULT_WAIT_MS = 5 * 60 * 1000;
export const POLL_INTERVAL_MS = 5_000;
export const MAX_POLL_READS = 60;
const JITTER = 0.2;

interface Waiter {
  woken: Promise<WaitStatus>;
  wake: (s: WaitStatus) => void;
  settled: boolean;
  /** Concurrent gates for the same approval id (an identical re-ask while the first wait is still open). */
  refs: number;
}

const waiters = new Map<string, Waiter>();

export function registerWaiter(approvalId: string): { woken: Promise<WaitStatus> } {
  const existing = waiters.get(approvalId);
  if (existing) {
    existing.refs += 1;
    return { woken: existing.woken };
  }
  let resolve!: (s: WaitStatus) => void;
  const woken = new Promise<WaitStatus>((r) => {
    resolve = r;
  });
  const w: Waiter = { woken, wake: resolve, settled: false, refs: 1 };
  waiters.set(approvalId, w);
  return { woken };
}

/** Wake the waiter registered on THIS host. Returns false when there is none (or it was already woken). */
export function wakeWaiter(approvalId: string, status: WaitStatus): boolean {
  const w = waiters.get(approvalId);
  if (!w || w.settled) return false;
  w.settled = true;
  w.wake(status);
  return true;
}

/** True while an approval waiter is registered under this id (used to refuse a cross-kind `review_gate_response`). */
export function hasWaiter(approvalId: string): boolean {
  return waiters.has(approvalId);
}

/** Release one registration; the waiter is dropped only when the LAST concurrent gate for the id has finished. */
export function unregisterWaiter(approvalId: string): void {
  const w = waiters.get(approvalId);
  if (!w) return;
  w.refs -= 1;
  if (w.refs <= 0) waiters.delete(approvalId);
}

export function waiterCount(): number {
  return waiters.size;
}

export function clearAllWaiters(): void {
  waiters.clear();
}

export type WaitOutcome =
  | { kind: "decided"; status: Exclude<WaitStatus, "pending"> }
  /** `readErrors` = status reads that failed during the wait (each one kept waiting; never an allow). */
  | { kind: "timeout"; readErrors: number }
  | { kind: "aborted"; readErrors: number };

export interface WaitDeps {
  approvalId: string;
  /** One indexed read of the row status; null (row not found) is treated as still pending. */
  read: () => Promise<WaitStatus | null>;
  signal: AbortSignal;
  /** Resolves when an in-process decide woke this waiter (a hint, confirmed by a read). */
  woken?: Promise<WaitStatus>;
  deadlineMs?: number;
  now?: () => number;
  sleep?: (ms: number) => Promise<void>;
  random?: () => number;
}

const realSleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

function jittered(random: () => number): number {
  return Math.round(POLL_INTERVAL_MS * (1 - JITTER + 2 * JITTER * random()));
}

export async function waitForDecision(deps: WaitDeps): Promise<WaitOutcome> {
  const now = deps.now ?? Date.now;
  const sleep = deps.sleep ?? realSleep;
  const random = deps.random ?? Math.random;
  const deadline = now() + (deps.deadlineMs ?? DEFAULT_WAIT_MS);
  let wake = deps.woken;
  let reads = 0;
  let readErrors = 0;

  // One abort listener for the whole wait (a listener per poll would pile up on the signal).
  const onAbort: { resolve: () => void } = { resolve: () => {} };
  const aborted = new Promise<"aborted">((resolve) => {
    onAbort.resolve = () => resolve("aborted");
  });
  deps.signal.addEventListener("abort", onAbort.resolve, { once: true });

  try {
    while (true) {
      if (deps.signal.aborted) return { kind: "aborted", readErrors };

      if (reads < MAX_POLL_READS) {
        reads += 1;
        try {
          const s = await deps.read();
          if (s && s !== "pending") return { kind: "decided", status: s };
        } catch {
          // Transient read error: keep waiting until the deadline. Never an allow. Counted, and reported once per wait.
          readErrors += 1;
        }
      }

      const remaining = deadline - now();
      if (remaining <= 0 || reads >= MAX_POLL_READS) return { kind: "timeout", readErrors };

      const nap = Math.min(jittered(random), remaining);
      const racers: Array<Promise<"slept" | "woken" | "aborted">> = [sleep(nap).then(() => "slept" as const), aborted];
      if (wake) racers.push(wake.then(() => "woken" as const));
      const r = await Promise.race(racers);
      if (r === "aborted" || deps.signal.aborted) return { kind: "aborted", readErrors };
      // The hint is consumed once: a resolved promise must not turn the loop into a hot database poll.
      if (r === "woken") wake = undefined;
    }
  } finally {
    deps.signal.removeEventListener("abort", onAbort.resolve);
  }
}
