import { afterEach, describe, expect, it, vi } from "vitest";
import {
  DEFAULT_WAIT_MS,
  MAX_POLL_READS,
  POLL_INTERVAL_MS,
  clearAllWaiters,
  registerWaiter,
  unregisterWaiter,
  waiterCount,
  wakeWaiter,
  waitForDecision,
  type WaitStatus,
} from "@/server/approval/waiters";
import { APPROVAL_ID } from "./fixtures";

afterEach(() => clearAllWaiters());

type Reader = () => Promise<WaitStatus | null>;
const run = (over: Partial<Parameters<typeof waitForDecision>[0]> & { read: Reader }) => {
  let now = 0;
  const sleeps: number[] = [];
  const p = waitForDecision({
    approvalId: APPROVAL_ID,
    signal: new AbortController().signal,
    now: () => now,
    sleep: async (ms) => {
      sleeps.push(ms);
      now += ms;
    },
    random: () => 0.5,
    ...over,
  });
  return { p, sleeps, advance: (ms: number) => (now += ms) };
};

describe("registry", () => {
  it("registers, wakes once and unregisters a waiter keyed by approval id", async () => {
    const w = registerWaiter(APPROVAL_ID);
    expect(waiterCount()).toBe(1);
    expect(wakeWaiter(APPROVAL_ID, "approved")).toBe(true);
    await expect(w.woken).resolves.toBe("approved");
    expect(wakeWaiter(APPROVAL_ID, "approved")).toBe(false);
    unregisterWaiter(APPROVAL_ID);
    expect(waiterCount()).toBe(0);
  });

  it("waking an id that has no waiter on this host is a no-op (the poll covers the other host)", () => {
    expect(wakeWaiter("11111111-1111-1111-1111-111111111111", "rejected")).toBe(false);
  });

  it("is a separate namespace: a review-gate id can never wake an approval waiter", () => {
    registerWaiter(APPROVAL_ID);
    expect(wakeWaiter("review-gate-id", "approved")).toBe(false);
    expect(waiterCount()).toBe(1);
  });
});

describe("waitForDecision", () => {
  it("returns the decided status as soon as a read shows it", async () => {
    const reads = ["pending", "pending", "approved"] as WaitStatus[];
    const { p } = run({ read: async () => reads.shift() ?? "approved" });
    expect(await p).toEqual({ kind: "decided", status: "approved" });
  });

  it("a rejected row is returned as rejected, never as approved", async () => {
    const { p } = run({ read: async () => "rejected" });
    expect(await p).toEqual({ kind: "decided", status: "rejected" });
  });

  it("an expired or consumed row ends the wait without an allow", async () => {
    for (const s of ["expired", "consumed"] as WaitStatus[]) {
      const { p } = run({ read: async () => s });
      expect(await p).toEqual({ kind: "decided", status: s });
    }
  });

  it("times out undecided after the deadline and leaves the verdict to the caller (row stays pending)", async () => {
    const { p, sleeps } = run({ read: async () => "pending" });
    expect(await p).toEqual({ kind: "timeout" });
    const total = sleeps.reduce((a, b) => a + b, 0);
    expect(total).toBeGreaterThanOrEqual(DEFAULT_WAIT_MS - POLL_INTERVAL_MS);
  });

  it("reads at most MAX_POLL_READS times", async () => {
    const read = vi.fn<Reader>(async () => "pending");
    const { p } = run({ read });
    await p;
    expect(read.mock.calls.length).toBeLessThanOrEqual(MAX_POLL_READS);
    expect(read.mock.calls.length).toBeGreaterThan(1);
  });

  it("a transient read error continues until the deadline and never allows", async () => {
    const read = vi.fn<Reader>(async () => {
      throw new Error("db down");
    });
    const { p } = run({ read });
    expect(await p).toEqual({ kind: "timeout" });
    expect(read.mock.calls.length).toBeGreaterThan(1);
  });

  it("a read error followed by a decision still returns the decision", async () => {
    let n = 0;
    const { p } = run({
      read: async () => {
        if (n++ === 0) throw new Error("blip");
        return "approved";
      },
    });
    expect(await p).toEqual({ kind: "decided", status: "approved" });
  });

  it("checks the signal first: an already aborted signal does not read at all", async () => {
    const ac = new AbortController();
    ac.abort();
    const read = vi.fn<Reader>(async () => "approved");
    const { p } = run({ read, signal: ac.signal });
    expect(await p).toEqual({ kind: "aborted" });
    expect(read).not.toHaveBeenCalled();
  });

  it("an abort during the sleep ends the wait as aborted, not as a decision", async () => {
    const ac = new AbortController();
    const { p } = run({
      read: async () => "pending",
      signal: ac.signal,
      sleep: async () => {
        ac.abort();
      },
    });
    expect(await p).toEqual({ kind: "aborted" });
  });

  it("an in-memory wake on this host short-circuits the sleep and is confirmed by one database read", async () => {
    const reads: WaitStatus[] = ["pending", "approved"];
    const read = vi.fn<Reader>(async () => reads.shift() ?? "approved");
    const w = registerWaiter(APPROVAL_ID);
    const { p } = run({
      read,
      woken: w.woken,
      sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
    });
    setTimeout(() => wakeWaiter(APPROVAL_ID, "approved"), 5);
    expect(await p).toEqual({ kind: "decided", status: "approved" });
    expect(read).toHaveBeenCalledTimes(2);
  });

  it("the wake is a hint only: a woken 'approved' with a database row still pending is not an allow", async () => {
    const w = registerWaiter(APPROVAL_ID);
    wakeWaiter(APPROVAL_ID, "approved");
    const { p } = run({ read: async () => "pending", woken: w.woken });
    expect(await p).toEqual({ kind: "timeout" });
  });

  it("jitters the poll interval within +-20% of the base", async () => {
    for (const rnd of [0, 1]) {
      const { p, sleeps } = run({ read: async () => "pending", random: () => rnd });
      await p;
      for (const s of sleeps.slice(0, -1)) {
        expect(s).toBeGreaterThanOrEqual(POLL_INTERVAL_MS * 0.8 - 1);
        expect(s).toBeLessThanOrEqual(POLL_INTERVAL_MS * 1.2 + 1);
      }
    }
  });
});
