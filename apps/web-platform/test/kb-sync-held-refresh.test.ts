// server/kb-sync-held-refresh.ts: the one compute-and-write path of the held count (#12714, rulings D39(a)/(b)/(f),
// D42, D43). The count's git runs for real in test/kb-sync-held-real-git.test.ts; here the seams are the compute, the
// write, the remote read and the isolated dir, so the write-always rule, the single flight and the no-mint rule are pinned.
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

const H = vi.hoisted(() => ({
  compute: vi.fn(),
  recovered: vi.fn(),
  write: vi.fn(),
  service: vi.fn(),
  readRemote: vi.fn(),
  resolveRepoUrl: vi.fn(),
  tenantMint: vi.fn(),
  createIso: vi.fn(),
  dispose: vi.fn(),
  present: vi.fn(),
  head: vi.fn(),
  mirrorWarn: vi.fn(),
  serviceRow: { data: { repo_url: "https://github.com/acme/widget" } as { repo_url: string | null } | null, error: null as unknown },
  serviceCalls: [] as Array<[string, ...unknown[]]>,
}));

vi.mock("@/server/kb-sync-held", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/kb-sync-held")>()),
  computeHeldFiles: H.compute,
  readRecoveredKbSyncTips: H.recovered,
}));
vi.mock("@/server/workspace-repo-mirror", () => ({ writeKbSyncHeldCols: H.write }));
vi.mock("@/lib/supabase/service", () => ({ getServiceClient: H.service }));
vi.mock("@/lib/supabase/tenant", () => ({ getFreshTenantClient: H.tenantMint, RuntimeAuthError: class extends Error {} }));
vi.mock("@/server/kb-sync-remote", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/kb-sync-remote")>()),
  readRemoteState: H.readRemote,
  resolveRepoUrl: H.resolveRepoUrl,
}));
vi.mock("@/server/git-isolated-push-dir", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/git-isolated-push-dir")>()),
  createIsolatedPushDir: H.createIso,
}));
vi.mock("@/server/kb-sync-objects", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/kb-sync-objects")>()),
  isCommitPresent: H.present,
}));
vi.mock("@/server/approval/workspace-head", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/approval/workspace-head")>()),
  readWorkspaceHeadRef: H.head,
}));
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  mirrorWarnWithDebounce: H.mirrorWarn,
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

import { IsolatedPushDirRefusal } from "@/server/git-isolated-push-dir";
import { KbRemoteError } from "@/server/kb-sync-remote";
import { refreshHeldCount, writeHeldFromIsolated } from "@/server/kb-sync-held-refresh";

const WS = "11111111-2222-3333-4444-555555555555";
const T = "a".repeat(40);
const HEAD = "b".repeat(40);
const READ_AT = new Date("2026-11-17T10:00:00.000Z");
const ISO = { gitDir: "/tmp/iso", dispose: H.dispose };

function serviceClient() {
  const chain: Record<string, unknown> = {};
  chain.select = (cols: string) => (H.serviceCalls.push(["select", cols]), chain);
  chain.eq = (col: string, val: string) => (H.serviceCalls.push(["eq", col, val]), chain);
  chain.maybeSingle = async () => ({ data: H.serviceRow.data, error: H.serviceRow.error });
  return { from: (t: string) => (H.serviceCalls.push(["from", t]), chain) };
}

beforeEach(() => {
  vi.clearAllMocks();
  H.serviceCalls.length = 0;
  H.serviceRow.data = { repo_url: "https://github.com/acme/widget" };
  H.serviceRow.error = null;
  H.compute.mockResolvedValue({ total: 2, onRecovered: 0 });
  H.recovered.mockReturnValue([]);
  H.write.mockResolvedValue(undefined);
  H.service.mockImplementation(serviceClient);
  H.readRemote.mockResolvedValue({ defaultBranch: "main", tip: T, sideTip: null, readAt: READ_AT });
  H.resolveRepoUrl.mockResolvedValue({ url: "https://github.com/acme/widget.git", owner: "acme", repo: "widget" });
  H.createIso.mockReturnValue(ISO);
  H.present.mockResolvedValue(true);
  H.head.mockReturnValue({ sha: HEAD, refName: "refs/heads/main" });
});
afterEach(() => vi.useRealTimers());

const base = { isolated: ISO as never, workspacePath: "/ws/x", workspaceId: WS, T, headSha: HEAD, checkedAt: READ_AT };

describe("writeHeldFromIsolated (D39(a)/(b))", () => {
  test("a computed count is written with this run's checkedAt (the instant T was read) and returned", async () => {
    H.compute.mockResolvedValueOnce({ total: 2, onRecovered: 1 });
    // the whole count comes back: `total` is what was stored, `onRecovered` feeds syncPull's agent line (no recompute)
    await expect(writeHeldFromIsolated(base)).resolves.toEqual({ total: 2, onRecovered: 1 });
    expect(H.compute.mock.calls[0][0]).toMatchObject({ base: T, head: HEAD, recovered: [], workspaceId: WS });
    expect(H.write.mock.calls).toEqual([[expect.anything(), WS, { heldFiles: 2, checkedAt: READ_AT }]]);
    expect(H.compute).toHaveBeenCalledTimes(1);
  });

  test("the caller's injected service client carries the write; without one, the process's service client does", async () => {
    const injected = { injected: true } as never;
    await writeHeldFromIsolated({ ...base, service: injected });
    expect(H.service).not.toHaveBeenCalled();
    expect(H.write.mock.calls[0][0]).toBe(injected);
    await writeHeldFromIsolated(base);
    expect(H.service).toHaveBeenCalledTimes(1);
    expect(H.write.mock.calls[1][0]).toBe(H.service.mock.results[0].value);
  });

  test("W1 binding: a failed count writes null with its checked_at, never skips the write", async () => {
    H.compute.mockResolvedValue(null);
    await expect(writeHeldFromIsolated(base)).resolves.toBeNull();
    expect(H.write.mock.calls).toEqual([[expect.anything(), WS, { heldFiles: null, checkedAt: READ_AT }]]);
  });

  test("recovered_unreadable writes null, logs the cause and sends ONE debounced warning keyed on the workspace", async () => {
    H.recovered.mockReturnValue(null);
    await expect(writeHeldFromIsolated(base)).resolves.toBeNull();
    expect(H.compute).not.toHaveBeenCalled();
    expect(H.write.mock.calls).toEqual([[expect.anything(), WS, { heldFiles: null, checkedAt: READ_AT }]]);
    expect(H.mirrorWarn).toHaveBeenCalledTimes(1);
    const [err, ctx, key, cls] = H.mirrorWarn.mock.calls[0];
    expect(err).toBeNull();
    expect(ctx).toMatchObject({ op: "kb-sync-held.count", tags: { null_cause: "recovered_unreadable" }, extra: { workspaceId: WS } });
    expect(key).toBe(WS);
    expect(cls).toBe("kb-sync-held.count:recovered_unreadable");
  });

  test("pullBlocked is passed through (D42); undefined leaves it out of the patch", async () => {
    await writeHeldFromIsolated({ ...base, pullBlocked: "merge_conflict_precheck" });
    await writeHeldFromIsolated({ ...base, pullBlocked: null });
    await writeHeldFromIsolated(base);
    expect(H.write.mock.calls.map((c) => c[2])).toEqual([
      { heldFiles: 2, checkedAt: READ_AT, pullBlocked: "merge_conflict_precheck" },
      { heldFiles: 2, checkedAt: READ_AT, pullBlocked: null },
      { heldFiles: 2, checkedAt: READ_AT },
    ]);
  });

  test("budgetMs reaches the count (D38(5))", async () => {
    await writeHeldFromIsolated({ ...base, budgetMs: 1234 });
    expect(H.compute.mock.calls[0][1]).toEqual({ budgetMs: 1234 });
  });

  test("never throws: a throwing compute, a throwing service-client factory or a rejecting write", async () => {
    H.compute.mockRejectedValueOnce(new Error("boom"));
    await expect(writeHeldFromIsolated(base)).resolves.toBeNull();
    expect(H.write.mock.calls.at(-1)?.[2]).toEqual({ heldFiles: null, checkedAt: READ_AT });
    H.service.mockImplementationOnce(() => {
      throw new Error("no env");
    });
    await expect(writeHeldFromIsolated(base)).resolves.toEqual({ total: 2, onRecovered: 0 });
    H.write.mockRejectedValueOnce(new Error("socket"));
    await expect(writeHeldFromIsolated(base)).resolves.toEqual({ total: 2, onRecovered: 0 });
  });
});

describe("refreshHeldCount (D39(a), D43)", () => {
  const args = { workspaceId: WS, workspacePath: "/ws/x", installationId: 42 };

  test("no userId: the repo URL comes from the service read on a ready row, and no tenant token is minted", async () => {
    await refreshHeldCount(args);
    expect(H.resolveRepoUrl).not.toHaveBeenCalled();
    expect(H.tenantMint).not.toHaveBeenCalled();
    expect(H.serviceCalls).toEqual([
      ["from", "workspaces"],
      ["select", "repo_url"],
      ["eq", "id", WS],
      ["eq", "repo_status", "ready"],
    ]);
    expect(H.readRemote).toHaveBeenCalledWith(ISO, 42, "https://github.com/acme/widget.git");
    expect(H.write.mock.calls).toEqual([[expect.anything(), WS, { heldFiles: 2, checkedAt: READ_AT }]]);
    expect(H.compute.mock.calls[0][0]).toMatchObject({ base: T, head: HEAD });
    expect(H.dispose).toHaveBeenCalledTimes(1);
  });

  test("with userId: the tenant-scoped repo URL read (resolveRepoUrl) keyed on (userId, workspaceId)", async () => {
    await refreshHeldCount({ ...args, userId: "user-1" });
    expect(H.resolveRepoUrl).toHaveBeenCalledWith("user-1", WS);
    expect(H.serviceCalls.filter((c) => c[0] === "select")).toEqual([]);
    expect(H.write).toHaveBeenCalledTimes(1);
  });

  test("single-flight per workspace: a second call while one runs joins it (one remote read, one write)", async () => {
    let release!: () => void;
    H.readRemote.mockImplementationOnce(
      () => new Promise((r) => (release = () => r({ defaultBranch: "main", tip: T, sideTip: null, readAt: READ_AT }))),
    );
    const a = refreshHeldCount(args);
    const b = refreshHeldCount(args);
    expect(b).toBe(a);
    await vi.waitFor(() => expect(H.readRemote).toHaveBeenCalledTimes(1));
    release();
    await Promise.all([a, b]);
    expect(H.write).toHaveBeenCalledTimes(1);
    // Once settled, the next call runs again.
    await refreshHeldCount(args);
    expect(H.readRemote).toHaveBeenCalledTimes(2);
  });

  test("another workspace is not joined", async () => {
    await Promise.all([refreshHeldCount(args), refreshHeldCount({ ...args, workspaceId: "w2" })]);
    expect(H.readRemote).toHaveBeenCalledTimes(2);
  });

  test("not ready (no row from the guarded read), no installation, or an unreadable HEAD: nothing is attempted or written", async () => {
    H.serviceRow.data = null;
    await refreshHeldCount(args);
    H.serviceRow.data = { repo_url: "https://github.com/acme/widget" };
    await refreshHeldCount({ ...args, installationId: 0 });
    H.head.mockImplementationOnce(() => {
      throw new Error("head_unreadable");
    });
    await refreshHeldCount(args);
    expect(H.createIso).not.toHaveBeenCalled();
    expect(H.write).not.toHaveBeenCalled();
  });

  test("no remote tip (ls-remote failed or no HEAD) or T not in the object store: no count attempted, nothing written", async () => {
    H.readRemote.mockRejectedValueOnce(new KbRemoteError("ls_remote_failed"));
    await refreshHeldCount(args);
    H.readRemote.mockResolvedValueOnce(null);
    await refreshHeldCount(args);
    // T absent locally: the self-heal or the next sync (which fetch T) owns the count; a null here would erase a
    // count they wrote with the same T.
    H.present.mockResolvedValueOnce(false);
    await refreshHeldCount(args);
    expect(H.compute).not.toHaveBeenCalled();
    expect(H.write).not.toHaveBeenCalled();
    expect(H.dispose).toHaveBeenCalledTimes(3);
  });

  test("an isolated-dir refusal is a skip, not a failure", async () => {
    H.createIso.mockImplementationOnce(() => {
      throw new IsolatedPushDirRefusal("symlinked_git_dir" as never);
    });
    await expect(refreshHeldCount(args)).resolves.toBeUndefined();
    expect(H.write).not.toHaveBeenCalled();
    expect(H.mirrorWarn).not.toHaveBeenCalled();
  });

  test("never throws: an unexpected failure resolves, disposes and sends one debounced warning", async () => {
    H.readRemote.mockRejectedValueOnce(new TypeError("unexpected"));
    await expect(refreshHeldCount(args)).resolves.toBeUndefined();
    expect(H.dispose).toHaveBeenCalledTimes(1);
    expect(H.mirrorWarn).toHaveBeenCalledTimes(1);
    expect(H.mirrorWarn.mock.calls[0][1]).toMatchObject({ op: "kb-sync-held.refresh", tags: { err_name: "TypeError" } });
    // A failed service read too.
    H.serviceRow.error = { code: "57014" };
    await expect(refreshHeldCount(args)).resolves.toBeUndefined();
    H.service.mockImplementationOnce(() => {
      throw new Error("no env");
    });
    await expect(refreshHeldCount(args)).resolves.toBeUndefined();
  });
});
