import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  mirrorWithDebounce: vi.fn(),
}));

import {
  clearKbSyncHeldCols,
  writeKbSyncHeldCols,
  writeKbSyncPullBlocked,
  writeRepoColsToWorkspace,
} from "@/server/workspace-repo-mirror";

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

// #12714: the held columns (migration 187) have ONE write body (simplicity F7) and are never part of WorkspaceRepoCols
// (simplicity F6), so the authoritative throwOnError repo write can never carry them.
/** A chainable fake of `from("workspaces").update(row).eq(...).eq(...).or(...).select("id")` that records the chain. */
function heldChain(result: { data?: Array<{ id: string }> | null; error?: unknown; reject?: unknown } = {}) {
  const data = result.data === undefined ? [{ id: "ws-team" }] : result.data;
  const calls: Array<[string, ...unknown[]]> = [];
  type Chain = {
    eq: (col: string, val: string) => Chain;
    or: (f: string) => Chain;
    select: (cols: string) => Promise<{ data: Array<{ id: string }> | null; error: unknown }>;
  };
  const builder: Chain = {
    eq: (col, val) => (calls.push(["eq", col, val]), builder),
    or: (f) => (calls.push(["or", f]), builder),
    select: (cols) => {
      calls.push(["select", cols]);
      return result.reject !== undefined ? Promise.reject(result.reject) : Promise.resolve({ data, error: result.error ?? null });
    },
  };
  const update = vi.fn((row: unknown) => (calls.push(["update", row]), builder));
  const from = vi.fn((t: string) => (calls.push(["from", t]), { update }));
  return { client: { from }, from, update, calls };
}

const mirrorCalls = async () => {
  const { mirrorWithDebounce, reportSilentFallback } = await import("@/server/observability");
  expect(reportSilentFallback, "held writes mirror only through the debounced helper (obs F1)").not.toHaveBeenCalled();
  return vi.mocked(mirrorWithDebounce).mock.calls;
};

// D29(1), D33(2), D42: disconnect and setup null the held columns in a SEPARATE best-effort UPDATE after their existing
// write, so a missing column (an apply that lags, or a rollback) never fails the route.
describe("clearKbSyncHeldCols", () => {
  beforeEach(() => vi.clearAllMocks());

  it("nulls the count and pull-blocked and STAMPS checked_at = now, WHERE id = the supplied workspace id, no freshness guard", async () => {
    vi.useFakeTimers({ now: new Date("2026-11-18T09:30:00.000Z") });
    try {
      const svc = heldChain();
      await clearKbSyncHeldCols(svc.client, "ws-team");
      expect(svc.calls).toEqual([
        ["from", "workspaces"],
        ["update", { kb_sync_held_files: null, kb_sync_held_checked_at: "2026-11-18T09:30:00.000Z", kb_sync_pull_blocked: null }],
        ["eq", "id", "ws-team"],
        ["select", "id"],
      ]);
      expect(await mirrorCalls()).toHaveLength(0);
    } finally {
      vi.useRealTimers();
    }
  });

  it("verify-data-sec P3-3: a run that read T before the clear loses the D39(f) guard after a reconnect (checked_at is never NULL)", async () => {
    // The clear's stamp is what the next guarded write is ordered against: a stale in-flight run (readAt before the
    // clear) cannot pass on `is.null`, because the clear never leaves NULL behind.
    const clearAt = new Date("2026-11-18T09:30:00.000Z");
    vi.useFakeTimers({ now: clearAt });
    try {
      const svc = heldChain();
      await clearKbSyncHeldCols(svc.client, "ws-team");
      const stamped = (svc.update.mock.calls[0][0] as { kb_sync_held_checked_at: unknown }).kb_sync_held_checked_at;
      expect(stamped).not.toBeNull();
      expect(typeof stamped === "string" && new Date(stamped).getTime()).toBe(clearAt.getTime());
      const stale = new Date(clearAt.getTime() - 1);
      expect(stale.toISOString() < (stamped as string)).toBe(true); // the guard's `lt` comparison, as PostgREST runs it
    } finally {
      vi.useRealTimers();
    }
  });

  it("an UPDATE error (column missing) resolves and mirrors once, debounced, err null, pg_code tag (obs F1/F9)", async () => {
    const svc = heldChain({ error: { message: "column workspaces.kb_sync_held_files does not exist", code: "42703" } });
    await expect(clearKbSyncHeldCols(svc.client, "ws-1")).resolves.toBeUndefined();
    const calls = await mirrorCalls();
    expect(calls).toHaveLength(1);
    expect(calls[0][0]).toBeNull();
    expect(calls[0][1]).toMatchObject({ feature: "workspace-repo-write", op: "kb-sync-held.clear", tags: { pg_code: "42703" } });
    expect(calls[0][2]).toBe("kb-sync-held.clear"); // constant key: one event per process per window, not per workspace
  });

  it("a rejected UPDATE resolves too, and mirrors exactly once", async () => {
    const svc = heldChain({ reject: new Error("socket hang up") });
    await expect(clearKbSyncHeldCols(svc.client, "ws-1")).resolves.toBeUndefined();
    const calls = await mirrorCalls();
    expect(calls).toHaveLength(1);
    expect(calls[0][0]).toBeNull();
    expect(calls[0][1]).toMatchObject({ tags: { pg_code: "none", err_name: "Error" } });
  });

  it("a 0-row clear (the workspace is gone) is not mirrored", async () => {
    const svc = heldChain({ data: [] });
    await expect(clearKbSyncHeldCols(svc.client, "ws-gone")).resolves.toBeUndefined();
    expect(await mirrorCalls()).toHaveLength(0);
  });
});

// D29(1), D33, D39(f), D42: the held-count write, a SEPARATE service-client UPDATE (never folded into the
// `repo_last_synced_at` stamp). Last writer wins by `checkedAt` (the instant the run read T), and only on a ready repo.
describe("writeKbSyncHeldCols", () => {
  beforeEach(() => vi.clearAllMocks());

  const AT = "2026-11-17T10:00:00.000Z";
  const PATCH = { heldFiles: 3, checkedAt: new Date(AT) };
  const COLS = { kb_sync_held_files: 3, kb_sync_held_checked_at: AT };
  const GUARD: Array<[string, ...unknown[]]> = [
    ["eq", "id", "ws-team"],
    ["eq", "repo_status", "ready"],
    ["or", `kb_sync_held_checked_at.is.null,kb_sync_held_checked_at.lt."${AT}"`],
    ["select", "id"],
  ];

  it("writes exactly the two held columns, keyed on the id, guarded on repo_status=ready and an older checked_at", async () => {
    const svc = heldChain();
    await writeKbSyncHeldCols(svc.client, "ws-team", PATCH);
    expect(svc.calls).toEqual([["from", "workspaces"], ["update", COLS], ...GUARD]);
    expect(await mirrorCalls()).toHaveLength(0);
  });

  it("writes a 0 too (a clean sync clears the notice), and a null with its checked_at (W1: a failed count stores null)", async () => {
    const svc = heldChain();
    await writeKbSyncHeldCols(svc.client, "ws-team", { ...PATCH, heldFiles: 0 });
    await writeKbSyncHeldCols(svc.client, "ws-team", { ...PATCH, heldFiles: null });
    expect(svc.update.mock.calls).toEqual([[{ ...COLS, kb_sync_held_files: 0 }], [{ ...COLS, kb_sync_held_files: null }]]);
  });

  it("never writes kb_sync_pull_blocked: that column has its own UPDATE, off the count's ordering (verify-data-sec P3-4)", async () => {
    const svc = heldChain();
    await writeKbSyncHeldCols(svc.client, "ws-team", PATCH);
    expect(svc.update.mock.calls).toEqual([[COLS]]);
  });

  it("an older checkedAt or a repo that is not ready matches 0 rows: expected, not mirrored (D39(f))", async () => {
    const svc = heldChain({ data: [] });
    await expect(writeKbSyncHeldCols(svc.client, "ws-team", PATCH)).resolves.toBeUndefined();
    expect(await mirrorCalls()).toHaveLength(0);
  });

  it("an UPDATE error (column missing, D33) resolves and mirrors once: debounced, err null, pg_code tag", async () => {
    const svc = heldChain({ error: { message: "column workspaces.kb_sync_held_files does not exist", code: "PGRST204" } });
    await expect(writeKbSyncHeldCols(svc.client, "ws-1", PATCH)).resolves.toBeUndefined();
    const calls = await mirrorCalls();
    expect(calls).toHaveLength(1);
    expect(calls[0][0]).toBeNull();
    expect(calls[0][1]).toMatchObject({
      feature: "workspace-repo-write",
      op: "kb-sync-held.write",
      tags: { pg_code: "PGRST204" },
      extra: { workspaceId: "ws-1" },
    });
    expect(calls[0][2]).toBe("kb-sync-held.write");
    expect(calls[0][3]).toBe("kb-sync-held.write:PGRST204");
  });

  it("a pg code that is not SQLSTATE-shaped is not put in a tag", async () => {
    const svc = heldChain({ error: { message: "x", code: "user 42 said <hi>" } });
    await writeKbSyncHeldCols(svc.client, "ws-1", PATCH);
    expect((await mirrorCalls())[0][1]).toMatchObject({ tags: { pg_code: "none" } });
  });

  it("a rejected UPDATE resolves, and mirrors exactly once", async () => {
    const svc = heldChain({ reject: new Error("socket hang up") });
    await expect(writeKbSyncHeldCols(svc.client, "ws-1", PATCH)).resolves.toBeUndefined();
    expect(await mirrorCalls()).toHaveLength(1);
  });

  it("an invalid checkedAt writes nothing and resolves (no instant to order by)", async () => {
    const svc = heldChain();
    await expect(writeKbSyncHeldCols(svc.client, "ws-1", { heldFiles: 1, checkedAt: new Date("nope") })).resolves.toBeUndefined();
    expect(svc.from).not.toHaveBeenCalled();
  });

  it("a client whose from() throws resolves, and mirrors exactly once", async () => {
    const client = { from: () => { throw new Error("boom"); } };
    await expect(writeKbSyncHeldCols(client as never, "ws-1", PATCH)).resolves.toBeUndefined();
    expect(await mirrorCalls()).toHaveLength(1);
  });
});

// verify-data-sec P3-4 (D42): the pull-blocked state is the self-heal's verdict on the workspace, not a property of one
// count, so it is NOT ordered by the count's checked_at (an unrelated newer count write would drop a set or a clear).
// Its own UPDATE, guarded only by repo_status = 'ready' (a disconnected or re-cloning row is untouched).
describe("writeKbSyncPullBlocked", () => {
  beforeEach(() => vi.clearAllMocks());

  it("writes only kb_sync_pull_blocked, keyed on the id, guarded on repo_status=ready and on nothing else", async () => {
    const svc = heldChain();
    await writeKbSyncPullBlocked(svc.client, "ws-team", "merge_conflict_precheck");
    expect(svc.calls).toEqual([
      ["from", "workspaces"],
      ["update", { kb_sync_pull_blocked: "merge_conflict_precheck" }],
      ["eq", "id", "ws-team"],
      ["eq", "repo_status", "ready"],
      ["select", "id"],
    ]);
    expect(await mirrorCalls()).toHaveLength(0);
  });

  it("null clears it (a merged or up-to-date pull, a recovered self-heal); each closed value is written as given", async () => {
    const svc = heldChain();
    await writeKbSyncPullBlocked(svc.client, "ws-team", null);
    await writeKbSyncPullBlocked(svc.client, "ws-team", "untracked_collision");
    expect(svc.update.mock.calls).toEqual([[{ kb_sync_pull_blocked: null }], [{ kb_sync_pull_blocked: "untracked_collision" }]]);
  });

  it("a 0-row match (not ready, or gone) is expected, not mirrored", async () => {
    const svc = heldChain({ data: [] });
    await expect(writeKbSyncPullBlocked(svc.client, "ws-team", null)).resolves.toBeUndefined();
    expect(await mirrorCalls()).toHaveLength(0);
  });

  it("an error or a rejection resolves and mirrors once, debounced on its own constant op key", async () => {
    const svc = heldChain({ error: { message: "column workspaces.kb_sync_pull_blocked does not exist", code: "PGRST204" } });
    await expect(writeKbSyncPullBlocked(svc.client, "ws-1", "untracked_collision")).resolves.toBeUndefined();
    const rej = heldChain({ reject: new Error("socket hang up") });
    await expect(writeKbSyncPullBlocked(rej.client, "ws-1", null)).resolves.toBeUndefined();
    const calls = await mirrorCalls();
    expect(calls).toHaveLength(2);
    expect(calls[0][1]).toMatchObject({ op: "kb-sync-held.pull-blocked", tags: { pg_code: "PGRST204" } });
    expect(calls[0][2]).toBe("kb-sync-held.pull-blocked");
    expect(calls[0][3]).toBe("kb-sync-held.pull-blocked:PGRST204");
  });

  it("a value outside the closed set writes nothing (a caller bug; the named check would reject it anyway)", async () => {
    const svc = heldChain();
    await writeKbSyncPullBlocked(svc.client, "ws-1", "nope" as never);
    expect(svc.from).not.toHaveBeenCalled();
  });
});
