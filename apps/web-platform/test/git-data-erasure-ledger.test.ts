import { describe, it, expect, vi, afterEach } from "vitest";
import { isUuid } from "../lib/is-uuid";

vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
}));

import { reportSilentFallback } from "@/server/observability";
import {
  GIT_DATA_ERASURE_LEDGER_FEATURE,
  LEDGER_WRITE_TIMEOUT_MS,
  recordGitDataErasurePendingBestEffort,
  gitDataErasureOwnerGone,
  recordGitDataErasurePending,
} from "../server/git-data-erasure-ledger";

const A = "3f2504e0-4f89-41d3-9a0c-0305e82c3301";
const svc = (result: { data?: unknown; error?: { message: string } | null }) => ({
  rpc: vi.fn(async () => ({ data: result.data ?? null, error: result.error ?? null })),
});

describe("git-data erasure ledger helpers", () => {
  it("the ledger's id guard (isUuid) accepts canonical UUIDs only, including a short or long last group", () => {
    expect(isUuid(A)).toBe(true);
    expect(isUuid(A.toUpperCase())).toBe(true);
    const head = A.slice(0, A.lastIndexOf("-") + 1);
    for (const bad of [
      "", "user-123", `${A}\n`, ` ${A}`, `${A}x`, null, undefined, 7, {},
      `${head}${"0".repeat(11)}`, // 11-hex last group
      `${head}${"0".repeat(13)}`, // 13-hex last group
    ]) {
      expect(isUuid(bad), String(bad)).toBe(false);
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

    it("a failed write reaches Sentry as a TAGGED message (null err) with the cause in extra, not as an Error", async () => {
      vi.mocked(reportSilentFallback).mockClear();
      await recordGitDataErasurePendingBestEffort(svc({ error: { message: "23514" } }) as never, A, "refused");
      expect(reportSilentFallback).toHaveBeenCalledTimes(1);
      const [err, opts] = vi.mocked(reportSilentFallback).mock.calls[0];
      expect(err).toBeNull(); // an Error would be deduplicated against the pino mirror, dropping tags/extra (#8629)
      expect(opts).toMatchObject({
        feature: GIT_DATA_ERASURE_LEDGER_FEATURE,
        op: "record-pending",
        extra: { gitDataRepoId: A, outcome: "refused", cause: expect.stringMatching(/23514/) },
      });
    });

    it("a hung write is abandoned at exactly the timeout, and no timer remains afterwards", async () => {
      vi.useFakeTimers();
      const hung = { rpc: vi.fn(() => new Promise(() => {})) };
      let done = false;
      vi.mocked(reportSilentFallback).mockClear();
      const p = recordGitDataErasurePendingBestEffort(hung as never, A, "refused", LEDGER_WRITE_TIMEOUT_MS).then(
        () => (done = true),
      );
      await vi.advanceTimersByTimeAsync(LEDGER_WRITE_TIMEOUT_MS - 1);
      expect(done).toBe(false);
      await vi.advanceTimersByTimeAsync(1);
      await p;
      expect(done).toBe(true);
      expect(vi.getTimerCount()).toBe(0);
      expect(vi.mocked(reportSilentFallback).mock.calls[0][1]).toMatchObject({
        extra: { cause: `ledger write exceeded ${LEDGER_WRITE_TIMEOUT_MS} ms; the deletion cascade continues` },
      });
    });
  });
});
