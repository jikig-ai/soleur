import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { clearKbSyncHeldCols, writeKbSyncHeldCols, writeRepoColsToWorkspace } from "@/server/workspace-repo-mirror";

// The write chain is `from("workspaces").update(patch).eq("id", id).select("id")`
// resolving to `{ data, error }`. `data` is the rows the UPDATE matched — an
// empty array is the silent-0-row no-op the helper must surface (ADR-044: the
// workspace can be deleted mid-flight, current_workspace_id ON DELETE SET NULL).
function makeService(
  result: { data?: Array<{ id: string }> | null; error?: unknown } = {},
) {
  const data = result.data === undefined ? [{ id: "ws-1" }] : result.data;
  const error = result.error ?? null;
  const select = vi.fn(async () => ({ data, error }));
  const eq = vi.fn(() => ({ select }));
  const update = vi.fn(() => ({ eq }));
  const from = vi.fn(() => ({ update }));
  return { client: { from }, from, update, eq, select };
}

describe("writeRepoColsToWorkspace", () => {
  beforeEach(() => vi.clearAllMocks());

  it("writes the repo cols to workspaces WHERE id = the SUPPLIED workspace id (team id)", async () => {
    const svc = makeService();
    const TEAM = "11111111-2222-3333-4444-555555555555";
    await writeRepoColsToWorkspace(svc.client, TEAM, {
      repo_url: "https://github.com/foo/bar",
      github_installation_id: 42,
      repo_status: "cloning",
    });
    expect(svc.from).toHaveBeenCalledWith("workspaces");
    expect(svc.update).toHaveBeenCalledWith({
      repo_url: "https://github.com/foo/bar",
      github_installation_id: 42,
      repo_status: "cloning",
    });
    // Keyed on the supplied (team) id — NOT a hardcoded userId.
    expect(svc.eq).toHaveBeenCalledWith("id", TEAM);
  });

  it("writes keyed on a solo id when that is what the caller resolved", async () => {
    const svc = makeService();
    await writeRepoColsToWorkspace(svc.client, "user-1", {
      repo_status: "ready",
    });
    expect(svc.eq).toHaveBeenCalledWith("id", "user-1");
  });

  it("round-trips repo_error (now a workspaces column)", async () => {
    const svc = makeService();
    await writeRepoColsToWorkspace(svc.client, "ws-1", {
      repo_status: "error",
      repo_error: '{"code":"CLONE_FAILED","message":"boom"}',
    });
    expect(svc.update).toHaveBeenCalledWith({
      repo_status: "error",
      repo_error: '{"code":"CLONE_FAILED","message":"boom"}',
    });
  });

  it("clears the credential + repo cols on disconnect (all nulled)", async () => {
    const svc = makeService();
    await writeRepoColsToWorkspace(svc.client, "ws-1", {
      github_installation_id: null,
      repo_url: null,
      repo_status: "not_connected",
      repo_last_synced_at: null,
      repo_error: null,
    });
    expect(svc.update).toHaveBeenCalledWith({
      github_installation_id: null,
      repo_url: null,
      repo_status: "not_connected",
      repo_last_synced_at: null,
      repo_error: null,
    });
  });

  it("Sentry-mirrors on db error without throwing by default", async () => {
    const { reportSilentFallback } = await import("@/server/observability");
    const svc = makeService({ error: { message: "boom" } });
    await expect(
      writeRepoColsToWorkspace(svc.client, "ws-1", { repo_status: "error" }),
    ).resolves.toBeUndefined();
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "workspace-repo-write", op: "write-to-workspace" }),
    );
  });

  it("treats a 0-row UPDATE as a silent no-op failure (workspace deleted mid-flight) and Sentry-mirrors", async () => {
    const { reportSilentFallback } = await import("@/server/observability");
    const svc = makeService({ data: [] });
    await expect(
      writeRepoColsToWorkspace(svc.client, "ws-gone", { repo_status: "ready" }),
    ).resolves.toBeUndefined();
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "write-to-workspace.zero-rows" }),
    );
  });

  it("with throwOnError, rethrows on db error AND Sentry-mirrors (disconnect credential-clear fails closed)", async () => {
    const { reportSilentFallback } = await import("@/server/observability");
    const svc = makeService({ error: { message: "boom" } });
    await expect(
      writeRepoColsToWorkspace(
        svc.client,
        "ws-1",
        { github_installation_id: null, repo_url: null, repo_status: "not_connected" },
        { throwOnError: true },
      ),
    ).rejects.toThrow();
    expect(reportSilentFallback).toHaveBeenCalled();
  });

  it("with throwOnError, rethrows on a 0-row no-op (the clear did not land on any row)", async () => {
    const svc = makeService({ data: [] });
    await expect(
      writeRepoColsToWorkspace(
        svc.client,
        "ws-gone",
        { github_installation_id: null, repo_url: null, repo_status: "not_connected" },
        { throwOnError: true },
      ),
    ).rejects.toThrow();
  });

  it("with throwOnError, does NOT throw on a successful 1-row write", async () => {
    const svc = makeService();
    await expect(
      writeRepoColsToWorkspace(
        svc.client,
        "ws-1",
        { github_installation_id: null, repo_url: null, repo_status: "not_connected" },
        { throwOnError: true },
      ),
    ).resolves.toBeUndefined();
  });
});

// #12714 (D29(1), D33(2)): disconnect and setup null the held columns in a SEPARATE best-effort UPDATE after their
// existing write, so a missing column (an apply that lags, or a rollback) never fails the route.
describe("clearKbSyncHeldCols", () => {
  beforeEach(() => vi.clearAllMocks());

  function heldService(result: { error?: unknown; reject?: unknown } = {}) {
    const eq = vi.fn(() =>
      result.reject !== undefined ? Promise.reject(result.reject) : Promise.resolve({ error: result.error ?? null }),
    );
    const update = vi.fn(() => ({ eq }));
    const from = vi.fn(() => ({ update }));
    return { client: { from }, from, update, eq };
  }

  it("nulls both held columns on workspaces WHERE id = the supplied workspace id, and nothing else", async () => {
    const svc = heldService();
    await clearKbSyncHeldCols(svc.client, "ws-team");
    expect(svc.from).toHaveBeenCalledWith("workspaces");
    expect(svc.update).toHaveBeenCalledWith({ kb_sync_held_files: null, kb_sync_held_checked_at: null });
    expect(svc.eq).toHaveBeenCalledWith("id", "ws-team");
    const { reportSilentFallback } = await import("@/server/observability");
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("an UPDATE error (column missing) resolves, and mirrors exactly once", async () => {
    const svc = heldService({ error: { message: "column workspaces.kb_sync_held_files does not exist", code: "42703" } });
    await expect(clearKbSyncHeldCols(svc.client, "ws-1")).resolves.toBeUndefined();
    const { reportSilentFallback } = await import("@/server/observability");
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(vi.mocked(reportSilentFallback).mock.calls[0][1]).toMatchObject({
      feature: "workspace-repo-write",
      op: "clear-kb-sync-held",
    });
  });

  it("a rejected UPDATE resolves too, and mirrors exactly once", async () => {
    const svc = heldService({ reject: new Error("socket hang up") });
    await expect(clearKbSyncHeldCols(svc.client, "ws-1")).resolves.toBeUndefined();
    const { reportSilentFallback } = await import("@/server/observability");
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
  });
});

// #12714 (D29(1), D33): every sync writes the held count in a SEPARATE service-client UPDATE (never folded into the
// `repo_last_synced_at` stamp), so a missing column fails only this write. Never throws; one mirror per failure.
describe("writeKbSyncHeldCols", () => {
  beforeEach(() => vi.clearAllMocks());

  const PATCH = { kb_sync_held_files: 3, kb_sync_held_checked_at: "2026-11-17T10:00:00.000Z" };

  function writeService(result: { data?: Array<{ id: string }> | null; error?: unknown; reject?: unknown } = {}) {
    const data = result.data === undefined ? [{ id: "ws-team" }] : result.data;
    const select = vi.fn(() =>
      result.reject !== undefined ? Promise.reject(result.reject) : Promise.resolve({ data, error: result.error ?? null }),
    );
    const eq = vi.fn(() => ({ select }));
    const update = vi.fn(() => ({ eq }));
    const from = vi.fn(() => ({ update }));
    return { client: { from }, from, update, eq, select };
  }

  it("writes exactly the two held columns on workspaces WHERE id = the supplied workspace id", async () => {
    const svc = writeService();
    await writeKbSyncHeldCols(svc.client, "ws-team", PATCH);
    expect(svc.from).toHaveBeenCalledWith("workspaces");
    expect(svc.update).toHaveBeenCalledTimes(1);
    expect(svc.update).toHaveBeenCalledWith(PATCH);
    expect(svc.eq).toHaveBeenCalledWith("id", "ws-team");
    const { reportSilentFallback } = await import("@/server/observability");
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("writes a 0 too (a clean sync clears the notice)", async () => {
    const svc = writeService();
    await writeKbSyncHeldCols(svc.client, "ws-1", { ...PATCH, kb_sync_held_files: 0 });
    expect(svc.update).toHaveBeenCalledWith({ ...PATCH, kb_sync_held_files: 0 });
  });

  it("an UPDATE error (column missing, D33) resolves, and mirrors exactly once", async () => {
    const svc = writeService({ error: { message: "column workspaces.kb_sync_held_files does not exist", code: "42703" } });
    await expect(writeKbSyncHeldCols(svc.client, "ws-1", PATCH)).resolves.toBeUndefined();
    const { reportSilentFallback } = await import("@/server/observability");
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(vi.mocked(reportSilentFallback).mock.calls[0][1]).toMatchObject({
      feature: "workspace-repo-write",
      op: "write-kb-sync-held",
      extra: { workspaceId: "ws-1" },
    });
  });

  it("a rejected UPDATE resolves, and mirrors exactly once", async () => {
    const svc = writeService({ reject: new Error("socket hang up") });
    await expect(writeKbSyncHeldCols(svc.client, "ws-1", PATCH)).resolves.toBeUndefined();
    const { reportSilentFallback } = await import("@/server/observability");
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
  });

  it("a 0-row UPDATE (workspace gone) resolves, and mirrors exactly once", async () => {
    const svc = writeService({ data: [] });
    await expect(writeKbSyncHeldCols(svc.client, "ws-gone", PATCH)).resolves.toBeUndefined();
    const { reportSilentFallback } = await import("@/server/observability");
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(vi.mocked(reportSilentFallback).mock.calls[0][1]).toMatchObject({ op: "write-kb-sync-held.zero-rows" });
  });

  it("a client whose from() throws resolves, and mirrors exactly once", async () => {
    const client = { from: () => { throw new Error("boom"); } };
    await expect(writeKbSyncHeldCols(client as never, "ws-1", PATCH)).resolves.toBeUndefined();
    const { reportSilentFallback } = await import("@/server/observability");
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
  });
});
