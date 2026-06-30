/**
 * Unit tests — worktree-write-lease.ts thin RPC client (epic #5274, Phase 2, PR A).
 *
 * Covers the result-mapping + fail-closed contract of the acquire/touch/release
 * wrappers over the migration-115 RPCs (the live RPC semantics are covered by
 * worktree-write-lease.integration.test.ts against DEV). Mirrors concurrency.ts:
 * lazy service client, transient retry on acquire, reportSilentFallback on error,
 * never throws.
 */

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

const { rpcMock } = vi.hoisted(() => ({ rpcMock: vi.fn() }));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ rpc: rpcMock }),
}));

const { reportSilentFallbackMock } = vi.hoisted(() => ({
  reportSilentFallbackMock: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackMock,
}));

import {
  acquireWorktreeLease,
  touchWorktreeLease,
  releaseWorktreeLease,
} from "@/server/worktree-write-lease";

const WS = "11111111-1111-1111-1111-111111111111";
const WT = "wt-main";
const HOST = "host-stable-7";

beforeEach(() => {
  rpcMock.mockReset();
  reportSilentFallbackMock.mockReset();
});
afterEach(() => {
  vi.useRealTimers();
});

describe("acquireWorktreeLease", () => {
  test("maps a returned row to {hostId, leaseGeneration}", async () => {
    rpcMock.mockResolvedValueOnce({
      data: [{ host_id: HOST, lease_generation: 3 }],
      error: null,
    });
    const lease = await acquireWorktreeLease(WS, WT, HOST);
    expect(lease).toEqual({ hostId: HOST, leaseGeneration: 3 });
    expect(rpcMock).toHaveBeenCalledWith("acquire_worktree_lease", {
      p_workspace_id: WS,
      p_worktree_id: WT,
      p_host_id: HOST,
    });
    expect(reportSilentFallbackMock).not.toHaveBeenCalled();
  });

  test("returns null when another host holds it (zero rows = lost)", async () => {
    rpcMock.mockResolvedValueOnce({ data: [], error: null });
    expect(await acquireWorktreeLease(WS, WT, HOST)).toBeNull();
    expect(reportSilentFallbackMock).not.toHaveBeenCalled();
  });

  test("fail-closed: a non-transient RPC error reports + returns null", async () => {
    rpcMock.mockResolvedValueOnce({
      data: null,
      error: { code: "42501", message: "insufficient_privilege" },
    });
    expect(await acquireWorktreeLease(WS, WT, HOST)).toBeNull();
    expect(reportSilentFallbackMock).toHaveBeenCalledTimes(1);
  });

  test("retries once on a transient error then succeeds", async () => {
    rpcMock
      .mockResolvedValueOnce({ data: null, error: { code: "40P01", message: "deadlock_detected" } })
      .mockResolvedValueOnce({ data: [{ host_id: HOST, lease_generation: 1 }], error: null });
    const lease = await acquireWorktreeLease(WS, WT, HOST);
    expect(lease).toEqual({ hostId: HOST, leaseGeneration: 1 });
    expect(rpcMock).toHaveBeenCalledTimes(2);
    expect(reportSilentFallbackMock).not.toHaveBeenCalled();
  });
});

describe("touchWorktreeLease", () => {
  test("returns true while the lease is still held (row_count 1)", async () => {
    rpcMock.mockResolvedValueOnce({ data: 1, error: null });
    expect(await touchWorktreeLease(WS, WT, HOST, 2)).toBe(true);
    expect(rpcMock).toHaveBeenCalledWith("touch_worktree_lease", {
      p_workspace_id: WS,
      p_worktree_id: WT,
      p_host_id: HOST,
      p_lease_generation: 2,
    });
  });

  test("returns false when reclaimed (row_count 0 = fail-loud signal for caller)", async () => {
    rpcMock.mockResolvedValueOnce({ data: 0, error: null });
    expect(await touchWorktreeLease(WS, WT, HOST, 2)).toBe(false);
  });

  test("an RPC error reports + returns false (caller treats as lost)", async () => {
    rpcMock.mockResolvedValueOnce({ data: null, error: { code: "08006", message: "conn" } });
    expect(await touchWorktreeLease(WS, WT, HOST, 2)).toBe(false);
    expect(reportSilentFallbackMock).toHaveBeenCalledTimes(1);
  });
});

describe("releaseWorktreeLease", () => {
  test("calls the release RPC with the gen-matched params and never throws", async () => {
    rpcMock.mockResolvedValueOnce({ data: 1, error: null });
    await expect(releaseWorktreeLease(WS, WT, HOST, 5)).resolves.toBeUndefined();
    expect(rpcMock).toHaveBeenCalledWith("release_worktree_lease", {
      p_workspace_id: WS,
      p_worktree_id: WT,
      p_host_id: HOST,
      p_lease_generation: 5,
    });
  });

  test("an RPC error is reported but not re-thrown (best-effort teardown)", async () => {
    rpcMock.mockResolvedValueOnce({ data: null, error: { code: "XX000", message: "boom" } });
    await expect(releaseWorktreeLease(WS, WT, HOST, 5)).resolves.toBeUndefined();
    expect(reportSilentFallbackMock).toHaveBeenCalledTimes(1);
  });
});
