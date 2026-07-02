/**
 * Unit tests — readWorktreeLeaseHolder (epic #5274 Phase 3 Sub-PR 3.B).
 *
 * The session router reads the CURRENT LIVE holder of a `(workspaceId,
 * worktreeId)` lease to decide local-serve vs proxy-to-owner. This is a
 * read-only, service-role SELECT (no acquire side effect) that must:
 *   - return the holder when the lease's heartbeat is within the liveness window;
 *   - return null when the row is absent (cold session) OR tombstoned/expired
 *     (heartbeat older than the window — release ages the heartbeat out);
 *   - fail-quiet to null on a DB read error (the placing host then acquires; the
 *     acquire path is itself fail-closed, and the git-data fence is the ultimate
 *     write guard) while mirroring the error to Sentry.
 */

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

const { fromMock } = vi.hoisted(() => ({ fromMock: vi.fn() }));
vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ from: fromMock }),
}));
const { reportSilentFallbackMock } = vi.hoisted(() => ({
  reportSilentFallbackMock: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackMock,
}));

import {
  readWorktreeLeaseHolder,
  LEASE_LIVENESS_WINDOW_MS,
} from "@/server/worktree-write-lease";

const WS = "11111111-1111-1111-1111-111111111111";
const WT = "22222222-2222-2222-2222-222222222222";

/** Build a recursive supabase `.from().select().eq().eq().maybeSingle()` chain
 *  that resolves to the given single-row result. */
function stubRow(result: { data: unknown; error: unknown }) {
  const chain: Record<string, unknown> = {};
  for (const m of ["select", "eq"]) chain[m] = () => chain;
  chain.maybeSingle = () => Promise.resolve(result);
  fromMock.mockReturnValue(chain);
}

beforeEach(() => {
  fromMock.mockReset();
  reportSilentFallbackMock.mockReset();
});
afterEach(() => vi.restoreAllMocks());

describe("readWorktreeLeaseHolder", () => {
  test("returns the holder when the heartbeat is within the liveness window", async () => {
    const heartbeat = new Date(Date.now() - 10_000).toISOString(); // 10s ago
    stubRow({ data: { host_id: "host-7", lease_generation: 4, heartbeat_at: heartbeat }, error: null });
    const holder = await readWorktreeLeaseHolder(WS, WT);
    expect(holder).toEqual({ hostId: "host-7", leaseGeneration: 4, heartbeatAt: heartbeat });
    // Read from the lease table, scoped to the (workspace, worktree) key.
    expect(fromMock).toHaveBeenCalledWith("worktree_write_lease");
  });

  test("returns null for a tombstoned/expired lease (heartbeat older than the window)", async () => {
    const stale = new Date(Date.now() - LEASE_LIVENESS_WINDOW_MS - 5_000).toISOString();
    stubRow({ data: { host_id: "host-dead", lease_generation: 9, heartbeat_at: stale }, error: null });
    expect(await readWorktreeLeaseHolder(WS, WT)).toBeNull();
  });

  test("returns null when no lease row exists (cold session)", async () => {
    stubRow({ data: null, error: null });
    expect(await readWorktreeLeaseHolder(WS, WT)).toBeNull();
  });

  test("fails quiet to null AND mirrors to Sentry on a read error", async () => {
    stubRow({ data: null, error: { code: "57014", message: "canceling statement" } });
    expect(await readWorktreeLeaseHolder(WS, WT)).toBeNull();
    expect(reportSilentFallbackMock).toHaveBeenCalledTimes(1);
    const ctx = reportSilentFallbackMock.mock.calls[0][1] as { feature: string; op: string };
    expect(ctx.feature).toBe("worktree_lease");
    expect(ctx.op).toBe("readWorktreeLeaseHolder");
  });
});
