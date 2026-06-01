import { describe, expect, it, vi } from "vitest";
import { randomUUID } from "crypto";
import { resolveActiveWorkspaceKbRoot } from "@/server/workspace-resolver";
import { mockQueryChain, type MockQueryChain } from "../helpers/mock-supabase";

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

const ROOT = "/tmp/soleur-test-workspaces";
process.env.WORKSPACES_ROOT = ROOT;

/**
 * Build a supabase-shape stub whose `.from(table)` dispatches to a per-table
 * mock chain. The KB-access resolver reads several tables in one pass
 * (user_session_state → workspace_members → workspaces → organizations →
 * users), so a single shared chain (the workspace-resolver.test.ts pattern)
 * cannot express the distinct row shapes each table returns.
 */
function supabaseMulti(byTable: Record<string, MockQueryChain>) {
  const from = vi.fn((table: string) => {
    const chain = byTable[table];
    if (!chain) {
      throw new Error(
        `unexpected .from("${table}") — resolver queried a table the test did not stub`,
      );
    }
    return chain;
  });
  return { from } as unknown as Parameters<typeof resolveActiveWorkspaceKbRoot>[1];
}

describe("resolveActiveWorkspaceKbRoot — active-workspace KB read scoping (ADR-044, #4543)", () => {
  it("member with a shared-workspace claim resolves the SHARED workspace dir (not the caller's solo row)", async () => {
    const userId = randomUUID();
    const sharedWs = randomUUID();
    const orgId = randomUUID();
    const ownerId = randomUUID();

    const supabase = supabaseMulti({
      user_session_state: mockQueryChain({ current_workspace_id: sharedWs }),
      workspace_members: mockQueryChain({ user_id: userId }), // is a member
      workspaces: mockQueryChain({ repo_status: "ready", organization_id: orgId }),
      organizations: mockQueryChain({ owner_user_id: ownerId }),
      users: mockQueryChain({ workspace_status: "ready" }), // owner's row
    });

    const result = await resolveActiveWorkspaceKbRoot(userId, supabase);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.activeWorkspaceId).toBe(sharedWs);
    expect(result.workspacePath).toBe(`${ROOT}/${sharedWs}`);
    expect(result.kbRoot).toBe(`${ROOT}/${sharedWs}/knowledge-base`);
    expect(result.repoStatus).toBe("ready");
  });

  it("null claim falls back to the SOLO workspace (= userId); reads the caller's OWN readiness, no org hop", async () => {
    const userId = randomUUID();

    const supabase = supabaseMulti({
      user_session_state: mockQueryChain({ current_workspace_id: null }),
      // NO organizations / workspace_members stub — solo must not query them.
      workspaces: mockQueryChain({ repo_status: "ready", organization_id: userId }),
      users: mockQueryChain({ workspace_status: "ready" }),
    });

    const result = await resolveActiveWorkspaceKbRoot(userId, supabase);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.activeWorkspaceId).toBe(userId);
    expect(result.kbRoot).toBe(`${ROOT}/${userId}/knowledge-base`);
  });

  it("a claim pointing at a workspace the caller is NOT a member of falls back to SOLO — never reads the sibling (IDOR / cross-tenant guard)", async () => {
    const userId = randomUUID();
    const siblingWs = randomUUID();

    const supabase = supabaseMulti({
      user_session_state: mockQueryChain({ current_workspace_id: siblingWs }),
      workspace_members: mockQueryChain(null), // NOT a member of siblingWs
      workspaces: mockQueryChain({ repo_status: "ready", organization_id: userId }),
      users: mockQueryChain({ workspace_status: "ready" }),
    });

    const result = await resolveActiveWorkspaceKbRoot(userId, supabase);

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.activeWorkspaceId).toBe(userId); // solo, NOT siblingWs
    expect(result.kbRoot).toBe(`${ROOT}/${userId}/knowledge-base`);
    expect(result.kbRoot).not.toContain(siblingWs);
  });

  it("returns 404 when the active workspace's repo is not_connected", async () => {
    const userId = randomUUID();

    const supabase = supabaseMulti({
      user_session_state: mockQueryChain({ current_workspace_id: null }),
      workspaces: mockQueryChain({ repo_status: "not_connected", organization_id: userId }),
    });

    const result = await resolveActiveWorkspaceKbRoot(userId, supabase);

    expect(result).toEqual({ ok: false, status: 404 });
  });

  it("returns 503 when the active workspace is connected but not yet ready (solo own readiness)", async () => {
    const userId = randomUUID();

    const supabase = supabaseMulti({
      user_session_state: mockQueryChain({ current_workspace_id: null }),
      workspaces: mockQueryChain({ repo_status: "ready", organization_id: userId }),
      users: mockQueryChain({ workspace_status: "provisioning" }),
    });

    const result = await resolveActiveWorkspaceKbRoot(userId, supabase);

    expect(result).toEqual({ ok: false, status: 503 });
  });

  it("for a member, readiness is gated on the OWNER's workspace_status (503 when the owner's workspace is still provisioning)", async () => {
    const userId = randomUUID();
    const sharedWs = randomUUID();
    const orgId = randomUUID();
    const ownerId = randomUUID();

    const supabase = supabaseMulti({
      user_session_state: mockQueryChain({ current_workspace_id: sharedWs }),
      workspace_members: mockQueryChain({ user_id: userId }),
      workspaces: mockQueryChain({ repo_status: "ready", organization_id: orgId }),
      organizations: mockQueryChain({ owner_user_id: ownerId }),
      users: mockQueryChain({ workspace_status: "provisioning" }), // owner not ready
    });

    const result = await resolveActiveWorkspaceKbRoot(userId, supabase);

    expect(result).toEqual({ ok: false, status: 503 });
  });
});
