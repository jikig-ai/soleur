// resolveOrCreateSupportConversation — B2 repo-less support conversation
// resolve-or-create for the SSE route (ADR-113). Deterministic — the tenant
// client + workspace resolver are mocked.

import { vi, describe, it, expect, beforeEach } from "vitest";

const { mockGetFreshTenantClient, mockResolveCurrentWorkspaceId } = vi.hoisted(() => ({
  mockGetFreshTenantClient: vi.fn(),
  mockResolveCurrentWorkspaceId: vi.fn(async () => "ws-123"),
}));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: mockGetFreshTenantClient,
}));
vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentWorkspaceId: mockResolveCurrentWorkspaceId,
}));

import { resolveOrCreateSupportConversation } from "@/server/support-conversation";

/** A chainable supabase mock. `existingRow` = what the resolve SELECT returns. */
function makeTenant(existingRow: { id: string } | null) {
  const insert = vi.fn().mockResolvedValue({ error: null });
  const chain: Record<string, unknown> = {};
  const self = () => chain;
  Object.assign(chain, {
    select: vi.fn(self),
    eq: vi.fn(self),
    order: vi.fn(self),
    limit: vi.fn(self),
    maybeSingle: vi.fn().mockResolvedValue({ data: existingRow, error: null }),
    insert,
  });
  return { chain: { from: vi.fn(() => chain) }, insert };
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

  it("throws if the insert fails (honest-degrade upstream)", async () => {
    const { chain, insert } = makeTenant(null);
    insert.mockResolvedValue({ error: { message: "rls denied" } });
    mockGetFreshTenantClient.mockResolvedValue(chain);

    await expect(resolveOrCreateSupportConversation("user-1")).rejects.toThrow(/support conversation/i);
  });
});
