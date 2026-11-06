// resolveOrCreateSupportConversation — B2 repo-less support conversation
// resolve-or-create for the SSE route (ADR-113). Deterministic — the tenant
// client + workspace resolver are mocked.

import { vi, describe, it, expect, beforeEach } from "vitest";

const { mockGetFreshTenantClient, mockResolveCurrentWorkspaceId, mockReportSilentFallback } = vi.hoisted(() => ({
  mockGetFreshTenantClient: vi.fn(),
  mockResolveCurrentWorkspaceId: vi.fn(async () => "ws-123"),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: mockGetFreshTenantClient,
}));
vi.mock("@/server/observability", () => ({ reportSilentFallback: mockReportSilentFallback }));
vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentWorkspaceId: mockResolveCurrentWorkspaceId,
}));

import { resolveOrCreateSupportConversation } from "@/server/support-conversation";

/** A chainable supabase mock. `existingRow` = what the resolve SELECT returns. */
function makeTenant(
  existingRow: { id: string; engine_binding_state?: string; workspace_id?: string | null } | null,
  rpcError: { message: string } | null = null,
  boundEngine = "claude-code",
) {
  const insert = vi.fn().mockResolvedValue({ error: null });
  // #11591: the support conversation is bound before dispatch via bind_agent_engine_run. The mock MUST carry
  // rpc, or the (non-fatal) bind throws a TypeError that is swallowed and the bind tests pass vacuously.
  // The RPC returns the bound run row (RETURNING *); assertLegacyEngineBinding reads its engine_id.
  const rpc = vi.fn().mockResolvedValue({ data: rpcError ? null : { engine_id: boundEngine }, error: rpcError });
  // First maybeSingle = the conversations SELECT; any later one = the sticky-bound engine re-check's run read.
  const maybeSingle = vi
    .fn()
    .mockResolvedValueOnce({ data: existingRow, error: null })
    .mockResolvedValue({
      data: { id: "run-1", execution_kind: "conversation", conversation_id: existingRow?.id, workspace_id: "ws-9",
        engine_id: boundEngine, auth_mode: "managed", adapter_version: "1", created_at: "2026-10-30T00:00:00Z" },
      error: null,
    });
  const chain: Record<string, unknown> = {};
  const self = () => chain;
  Object.assign(chain, {
    select: vi.fn(self),
    eq: vi.fn(self),
    order: vi.fn(self),
    limit: vi.fn(self),
    maybeSingle,
    insert,
  });
  return { chain: { from: vi.fn(() => chain), rpc }, insert, maybeSingle, rpc };
}

describe("resolveOrCreateSupportConversation", () => {
  beforeEach(() => vi.clearAllMocks());

  it("returns the existing support conversation when one exists (no insert)", async () => {
    const { chain, insert } = makeTenant({ id: "conv-existing" });
    mockGetFreshTenantClient.mockResolvedValue(chain);

    const id = await resolveOrCreateSupportConversation("user-1");
    expect(id).toBe("conv-existing");
    expect(insert).not.toHaveBeenCalled();
  });

  it("creates a repo-less kind='support' row when none exists", async () => {
    const { chain, insert } = makeTenant(null);
    mockGetFreshTenantClient.mockResolvedValue(chain);

    const id = await resolveOrCreateSupportConversation("user-1");
    expect(typeof id).toBe("string");
    expect(insert).toHaveBeenCalledOnce();
    const row = insert.mock.calls[0][0];
    expect(row.kind).toBe("support");
    expect(row.repo_url).toBeNull();
    expect(row.workspace_id).toBe("ws-123");
    expect(row.user_id).toBe("user-1");
    expect(row.id).toBe(id);
  });

  it("forceNew skips the reuse SELECT and always inserts a fresh thread", async () => {
    // A reusable row EXISTS, but forceNew must ignore it and mint a new one.
    const { chain, insert, maybeSingle } = makeTenant({ id: "conv-wedged" });
    mockGetFreshTenantClient.mockResolvedValue(chain);

    const id = await resolveOrCreateSupportConversation("user-1", { forceNew: true });
    expect(maybeSingle).not.toHaveBeenCalled(); // reuse SELECT bypassed
    expect(insert).toHaveBeenCalledOnce();
    const row = insert.mock.calls[0][0];
    expect(row.id).toBe(id);
    expect(row.kind).toBe("support");
    expect(row.repo_url).toBeNull();
    expect(id).not.toBe("conv-wedged");
  });

  it("default (no opts) still reuses the existing thread", async () => {
    const { chain, insert, maybeSingle } = makeTenant({ id: "conv-existing" });
    mockGetFreshTenantClient.mockResolvedValue(chain);

    const id = await resolveOrCreateSupportConversation("user-1");
    expect(maybeSingle).toHaveBeenCalledOnce();
    expect(id).toBe("conv-existing");
    expect(insert).not.toHaveBeenCalled();
  });

  it("throws if the insert fails (honest-degrade upstream)", async () => {
    const { chain, insert } = makeTenant(null);
    insert.mockResolvedValue({ error: { message: "rls denied" } });
    mockGetFreshTenantClient.mockResolvedValue(chain);

    await expect(resolveOrCreateSupportConversation("user-1")).rejects.toThrow(/support conversation/i);
  });
});

describe("resolveOrCreateSupportConversation — engine binding before dispatch (#11591)", () => {
  beforeEach(() => vi.clearAllMocks());

  it("binds a newly inserted row (tenant client) with the resolved workspace", async () => {
    const { chain, insert, rpc } = makeTenant(null);
    mockGetFreshTenantClient.mockResolvedValue(chain);

    const id = await resolveOrCreateSupportConversation("user-1");

    expect(insert).toHaveBeenCalledOnce();
    expect(rpc).toHaveBeenCalledOnce();
    expect(rpc.mock.calls[0][0]).toBe("bind_agent_engine_run");
    expect(rpc.mock.calls[0][1]).toMatchObject({
      p_workspace_id: "ws-123",
      p_execution_kind: "conversation",
      p_conversation_id: id,
      p_created_by: "user-1",
    });
  });

  it.each(["pending", "legacy"])("binds a sticky %s row at its next message (CTO ruling: no thread keeps the subscription forever)", async (state) => {
    const { chain, rpc } = makeTenant({ id: "conv-old", engine_binding_state: state, workspace_id: "ws-9" });
    mockGetFreshTenantClient.mockResolvedValue(chain);

    await expect(resolveOrCreateSupportConversation("user-1")).resolves.toBe("conv-old");

    expect(rpc).toHaveBeenCalledOnce();
    expect(rpc.mock.calls[0][1]).toMatchObject({ p_workspace_id: "ws-9", p_conversation_id: "conv-old", p_created_by: "user-1" });
  });

  it("a sticky bound row is re-checked for its engine on every message (a non-Claude bind must not run on Claude)", async () => {
    const row = { id: "conv-old", engine_binding_state: "bound", workspace_id: "ws-9" };
    const ok = makeTenant(row);
    mockGetFreshTenantClient.mockResolvedValue(ok.chain);
    await expect(resolveOrCreateSupportConversation("user-1")).resolves.toBe("conv-old");

    const codex = makeTenant(row, null, "codex");
    mockGetFreshTenantClient.mockResolvedValue(codex.chain);
    await expect(resolveOrCreateSupportConversation("user-1")).rejects.toMatchObject({ code: "engine_dispatch_required" });
    expect(codex.rpc).not.toHaveBeenCalled();
  });

  it("never re-binds a sticky bound row, and never binds one whose workspace is unknown", async () => {
    for (const row of [
      { id: "conv-old", engine_binding_state: "bound", workspace_id: "ws-9" },
      { id: "conv-old", engine_binding_state: "pending", workspace_id: null },
    ]) {
      const { chain, rpc } = makeTenant(row);
      mockGetFreshTenantClient.mockResolvedValue(chain);
      await resolveOrCreateSupportConversation("user-1");
      expect(rpc).not.toHaveBeenCalled();
    }
  });

  it("a new row is bound only AFTER it is inserted", async () => {
    const { chain, insert, rpc } = makeTenant(null);
    mockGetFreshTenantClient.mockResolvedValue(chain);
    await resolveOrCreateSupportConversation("user-1");
    expect(insert.mock.invocationCallOrder[0]).toBeLessThan(rpc.mock.invocationCallOrder[0]);
  });

  it("a failed bind is mirrored (feature=support, op=bind) and does not fail the conversation", async () => {
    const { chain, rpc } = makeTenant(null, { message: "bind denied" });
    mockGetFreshTenantClient.mockResolvedValue(chain);

    await expect(resolveOrCreateSupportConversation("user-1")).resolves.toEqual(expect.any(String));

    expect(rpc).toHaveBeenCalledOnce();
    expect(mockReportSilentFallback).toHaveBeenCalledOnce();
    expect(mockReportSilentFallback.mock.calls[0][1]).toMatchObject({ feature: "support", op: "bind" });
  });

  it("a duplicate-key bind (a concurrent first message already bound it) is the desired state: not mirrored", async () => {
    const { chain, rpc } = makeTenant(
      { id: "conv-old", engine_binding_state: "pending", workspace_id: "ws-9" },
      { message: 'engine run bind failed: duplicate key value violates unique constraint "agent_engine_runs_conversation_uniq"' },
    );
    mockGetFreshTenantClient.mockResolvedValue(chain);

    await expect(resolveOrCreateSupportConversation("user-1")).resolves.toBe("conv-old");

    expect(rpc).toHaveBeenCalledOnce();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("a failed bind on a sticky legacy row refuses (it would otherwise serve the subscription); pending stays soft", async () => {
    const legacy = makeTenant({ id: "conv-old", engine_binding_state: "legacy", workspace_id: "ws-9" }, { message: "bind denied" });
    mockGetFreshTenantClient.mockResolvedValue(legacy.chain);
    await expect(resolveOrCreateSupportConversation("user-1")).rejects.toThrow("bind denied");
    expect(mockReportSilentFallback).toHaveBeenCalledOnce();

    const pending = makeTenant({ id: "conv-old", engine_binding_state: "pending", workspace_id: "ws-9" }, { message: "bind denied" });
    mockGetFreshTenantClient.mockResolvedValue(pending.chain);
    await expect(resolveOrCreateSupportConversation("user-1")).resolves.toBe("conv-old");
  });

  it("a bind that lands on a non-Claude engine stops the dispatch (assertLegacyEngineBinding, as ws-handler does)", async () => {
    const { chain } = makeTenant(null, null, "codex");
    mockGetFreshTenantClient.mockResolvedValue(chain);

    await expect(resolveOrCreateSupportConversation("user-1")).rejects.toMatchObject({ code: "engine_dispatch_required" });
  });
});
