import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Dispatch supabase.rpc(name, args) by RPC name so acquire/touch/release are
// each independently programmable. Default: acquire→held(gen 7), touch→held,
// release→ok. Partial mock keeps every other export of the service module real.
const acquireResult = { value: { data: [{ host_id: "h1", lease_generation: 7 }], error: null } };
const touchResult = { value: { data: 1, error: null } };
const rpc = vi.fn((name: string) => {
  if (name === "acquire_worktree_lease") return Promise.resolve(acquireResult.value);
  if (name === "touch_worktree_lease") return Promise.resolve(touchResult.value);
  if (name === "release_worktree_lease") return Promise.resolve({ data: null, error: null });
  throw new Error(`unexpected rpc: ${name}`);
});
vi.mock("@/lib/supabase/service", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/lib/supabase/service")>()),
  createServiceClient: () => ({ rpc }),
}));

import {
  acquireAndHoldWorktreeLease,
  WORKTREE_LEASE_HEARTBEAT_MS,
  __test_only__,
} from "@/server/worktree-write-lease";

const rpcNames = () => rpc.mock.calls.map((c) => c[0]);

beforeEach(() => {
  vi.useFakeTimers();
  __test_only__.clearHeldLeases();
  rpc.mockClear();
  acquireResult.value = { data: [{ host_id: "h1", lease_generation: 7 }], error: null };
  touchResult.value = { data: 1, error: null };
});
afterEach(() => {
  vi.useRealTimers();
  __test_only__.clearHeldLeases();
});

describe("acquireAndHoldWorktreeLease (#5274 PR B steps 7-9)", () => {
  it("acquires, returns the fencing generation, and registers for the SIGTERM drain", async () => {
    const onLost = vi.fn();
    const handle = await acquireAndHoldWorktreeLease("ws", "primary", "h1", onLost);

    expect(handle).not.toBeNull();
    expect(handle!.leaseGeneration).toBe(7);
    expect(__test_only__.heldLeaseCount()).toBe(1);
    expect(onLost).not.toHaveBeenCalled();
  });

  it("returns null and does NOT register when another host holds the lease (fail-closed)", async () => {
    acquireResult.value = { data: [], error: null }; // [] = live lease held elsewhere
    const handle = await acquireAndHoldWorktreeLease("ws", "primary", "h1", vi.fn());

    expect(handle).toBeNull();
    expect(__test_only__.heldLeaseCount()).toBe(0);
  });

  it("heartbeats on the cadence and keeps holding while touch succeeds (onLost silent)", async () => {
    const onLost = vi.fn();
    await acquireAndHoldWorktreeLease("ws", "primary", "h1", onLost);

    await vi.advanceTimersByTimeAsync(WORKTREE_LEASE_HEARTBEAT_MS * 2 + 10);

    expect(rpcNames().filter((n) => n === "touch_worktree_lease").length).toBe(2);
    expect(onLost).not.toHaveBeenCalled();
    expect(__test_only__.heldLeaseCount()).toBe(1);
  });

  it("fires onLost exactly once, stops the heartbeat, and unregisters on a touch loss", async () => {
    const onLost = vi.fn();
    await acquireAndHoldWorktreeLease("ws", "primary", "h1", onLost);

    touchResult.value = { data: 0, error: null }; // reclaimed by another host
    await vi.advanceTimersByTimeAsync(WORKTREE_LEASE_HEARTBEAT_MS + 10);

    expect(onLost).toHaveBeenCalledTimes(1);
    expect(__test_only__.heldLeaseCount()).toBe(0);

    // Heartbeat is stopped: further time advances issue no more touches.
    const touchesAfterLoss = rpcNames().filter((n) => n === "touch_worktree_lease").length;
    await vi.advanceTimersByTimeAsync(WORKTREE_LEASE_HEARTBEAT_MS * 2);
    expect(rpcNames().filter((n) => n === "touch_worktree_lease").length).toBe(touchesAfterLoss);
    expect(onLost).toHaveBeenCalledTimes(1);
  });

  it("release() stops the heartbeat, unregisters, frees the row, and is idempotent", async () => {
    const handle = await acquireAndHoldWorktreeLease("ws", "primary", "h1", vi.fn());

    await handle!.release();
    expect(rpcNames().filter((n) => n === "release_worktree_lease").length).toBe(1);
    expect(__test_only__.heldLeaseCount()).toBe(0);

    await handle!.release(); // idempotent — no second RPC
    expect(rpcNames().filter((n) => n === "release_worktree_lease").length).toBe(1);

    // No heartbeat fires after release.
    await vi.advanceTimersByTimeAsync(WORKTREE_LEASE_HEARTBEAT_MS * 2);
    expect(rpcNames().filter((n) => n === "touch_worktree_lease").length).toBe(0);
  });

  it("release() after an observed loss is suppressed (the reclaimer's row is never stomped)", async () => {
    const handle = await acquireAndHoldWorktreeLease("ws", "primary", "h1", vi.fn());

    touchResult.value = { data: 0, error: null };
    await vi.advanceTimersByTimeAsync(WORKTREE_LEASE_HEARTBEAT_MS + 10);

    await handle!.release();
    expect(rpcNames().filter((n) => n === "release_worktree_lease").length).toBe(0);
  });
});
