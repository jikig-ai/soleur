import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// The lease module lazily constructs a service client via createServiceClient()
// on first `supabase.*` access (Proxy at worktree-write-lease.ts:32). Mock the
// factory so releaseAllHeldLeases' transitive release_worktree_lease RPC is
// observable without a live DB. Partial mock — keep every other export real.
const rpc = vi.fn().mockResolvedValue({ data: 1, error: null });
vi.mock("@/lib/supabase/service", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/lib/supabase/service")>()),
  createServiceClient: () => ({ rpc }),
}));

import {
  registerHeldLease,
  unregisterHeldLease,
  releaseAllHeldLeases,
  __test_only__,
  type HeldWorktreeLease,
} from "@/server/worktree-write-lease";

const lease = (workspaceId: string, gen = 1): HeldWorktreeLease => ({
  workspaceId,
  worktreeId: "primary",
  hostId: "12345678",
  leaseGeneration: gen,
});

beforeEach(() => {
  __test_only__.clearHeldLeases();
  rpc.mockClear().mockResolvedValue({ data: 1, error: null });
});
afterEach(() => {
  __test_only__.clearHeldLeases();
});

describe("held-lease registry (SIGTERM drain, #5274 Phase 2 PR B)", () => {
  it("registers a held lease (count reflects the new entry)", () => {
    expect(__test_only__.heldLeaseCount()).toBe(0);
    registerHeldLease(lease("ws-a"));
    expect(__test_only__.heldLeaseCount()).toBe(1);
  });

  it("is idempotent per (workspaceId, worktreeId) key — re-register does not double-count", () => {
    registerHeldLease(lease("ws-a", 1));
    registerHeldLease(lease("ws-a", 2)); // same key, refreshed gen
    expect(__test_only__.heldLeaseCount()).toBe(1);
  });

  it("distinct workspaces occupy distinct keys", () => {
    registerHeldLease(lease("ws-a"));
    registerHeldLease(lease("ws-b"));
    expect(__test_only__.heldLeaseCount()).toBe(2);
  });

  it("unregisterHeldLease drops only the matching key", () => {
    registerHeldLease(lease("ws-a"));
    registerHeldLease(lease("ws-b"));
    unregisterHeldLease("ws-a", "primary");
    expect(__test_only__.heldLeaseCount()).toBe(1);
  });

  it("releaseAllHeldLeases releases every held lease via the RPC, with the held lease's identity", async () => {
    registerHeldLease(lease("ws-a", 3));
    registerHeldLease(lease("ws-b", 5));

    await releaseAllHeldLeases();

    expect(rpc).toHaveBeenCalledTimes(2);
    expect(rpc).toHaveBeenCalledWith("release_worktree_lease", {
      p_workspace_id: "ws-a",
      p_worktree_id: "primary",
      p_host_id: "12345678",
      p_lease_generation: 3,
    });
    expect(rpc).toHaveBeenCalledWith("release_worktree_lease", {
      p_workspace_id: "ws-b",
      p_worktree_id: "primary",
      p_host_id: "12345678",
      p_lease_generation: 5,
    });
  });

  it("clears the registry up front so a release racing a concurrent acquire cannot resurrect a stale entry", async () => {
    registerHeldLease(lease("ws-a"));
    await releaseAllHeldLeases();
    expect(__test_only__.heldLeaseCount()).toBe(0);
  });

  it("a failing release does not throw and still drains the rest (allSettled, bounded shutdown)", async () => {
    rpc
      .mockResolvedValueOnce({ data: null, error: { message: "boom" } })
      .mockResolvedValue({ data: 1, error: null });
    registerHeldLease(lease("ws-a"));
    registerHeldLease(lease("ws-b"));

    await expect(releaseAllHeldLeases()).resolves.toBeUndefined();
    expect(rpc).toHaveBeenCalledTimes(2);
    expect(__test_only__.heldLeaseCount()).toBe(0);
  });
});
