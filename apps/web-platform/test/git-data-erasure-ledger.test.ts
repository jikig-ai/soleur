import { describe, it, expect, vi, afterEach } from "vitest";

vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
}));

import {
  recordGitDataErasurePendingBestEffort,
  gitDataErasureOwnerGone,
  isLedgerWorkspaceId,
  recordGitDataErasurePending,
} from "../server/git-data-erasure-ledger";

const A = "3f2504e0-4f89-41d3-9a0c-0305e82c3301";
const svc = (result: { data?: unknown; error?: { message: string } | null }) => ({
  rpc: vi.fn(async () => ({ data: result.data ?? null, error: result.error ?? null })),
});

describe("git-data erasure ledger helpers", () => {
  it("isLedgerWorkspaceId accepts canonical UUIDs only", () => {
    expect(isLedgerWorkspaceId(A)).toBe(true);
    expect(isLedgerWorkspaceId(A.toUpperCase())).toBe(true);
    for (const bad of ["", "user-123", `${A}\n`, ` ${A}`, `${A}x`, null, undefined, 7, {}]) {
      expect(isLedgerWorkspaceId(bad), String(bad)).toBe(false);
    }
  });

  it("owner_gone is true ONLY for a literal true: false, null, undefined and strings all read as 'not gone'", async () => {
    expect(await gitDataErasureOwnerGone(svc({ data: true }) as never, A)).toBe(true);
    for (const data of [false, null, undefined, "true", 1]) {
      expect(await gitDataErasureOwnerGone(svc({ data }) as never, A), String(data)).toBe(false);
    }
  });

  it("owner_gone throws on an RPC error (a caller must read an error as 'not gone')", async () => {
    await expect(gitDataErasureOwnerGone(svc({ error: { message: "db down" } }) as never, A)).rejects.toThrow(/owner_gone failed/);
  });

  it("record passes p_requested_at only when given (seed path), as an ISO string", async () => {
    const a = svc({});
    await recordGitDataErasurePending(a as never, A, "refused");
    expect(a.rpc).toHaveBeenCalledWith("record_git_data_erasure_pending", { p_workspace_id: A, p_outcome: "refused" });
    const b = svc({});
    await recordGitDataErasurePending(b as never, A, "seeded", new Date("2026-10-01T00:00:00Z"));
    expect(b.rpc).toHaveBeenCalledWith("record_git_data_erasure_pending", {
      p_workspace_id: A,
      p_outcome: "seeded",
      p_requested_at: "2026-10-01T00:00:00.000Z",
    });
  });

  it("record throws on an RPC error", async () => {
    await expect(recordGitDataErasurePending(svc({ error: { message: "23514" } }) as never, A, "refused")).rejects.toThrow(/failed: 23514/);
  });

  describe("recordGitDataErasurePendingBestEffort timer hygiene", () => {
    afterEach(() => vi.useRealTimers());

    it("leaves NO pending timer after a resolving write, a rejecting write, an RPC error and a non-UUID skip", async () => {
      vi.useFakeTimers();
      await recordGitDataErasurePendingBestEffort(svc({}) as never, A, "refused");
      expect(vi.getTimerCount()).toBe(0);
      const rejecting = { rpc: vi.fn(async () => { throw new Error("socket hang up"); }) };
      await recordGitDataErasurePendingBestEffort(rejecting as never, A, "refused");
      expect(vi.getTimerCount()).toBe(0);
      await recordGitDataErasurePendingBestEffort(svc({ error: { message: "23514" } }) as never, A, "refused");
      expect(vi.getTimerCount()).toBe(0);
      await recordGitDataErasurePendingBestEffort(svc({}) as never, "user-123", "refused");
      expect(vi.getTimerCount()).toBe(0);
    });

    it("a hung write is abandoned at exactly the timeout, and no timer remains afterwards", async () => {
      vi.useFakeTimers();
      const hung = { rpc: vi.fn(() => new Promise(() => {})) };
      let done = false;
      const p = recordGitDataErasurePendingBestEffort(hung as never, A, "refused", 5_000).then(() => (done = true));
      await vi.advanceTimersByTimeAsync(4_999);
      expect(done).toBe(false);
      await vi.advanceTimersByTimeAsync(1);
      await p;
      expect(done).toBe(true);
      expect(vi.getTimerCount()).toBe(0);
    });
  });
});
