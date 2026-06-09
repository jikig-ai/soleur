import { describe, expect, it, vi, beforeEach } from "vitest";

// resolveActiveWorkspaceRepoMeta (Workstream B) composes:
//   - resolveActiveWorkspaceIdWithMembership (user_session_state +
//     workspace_members reads, self-scoped via .eq("user_id", userId))
//   - a service-role workspaces.repo_url read by active id
//   - resolveInstallationId (the membership-checked SECURITY DEFINER RPC),
//     imported DYNAMICALLY by the resolver → mock the module.
// All fixtures synthesized (cq-test-fixtures-synthesized-only).

const { mockResolveInstallationId } = vi.hoisted(() => ({
  mockResolveInstallationId: vi.fn(),
}));
vi.mock("@/server/resolve-installation-id", () => ({
  resolveInstallationId: mockResolveInstallationId,
}));

import { reportSilentFallback } from "@/server/observability";
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { resolveActiveWorkspaceRepoMeta } from "@/server/workspace-resolver";

const SOLO_USER = "11111111-1111-1111-1111-111111111111";
const SHARED_WS = "22222222-2222-2222-2222-222222222222";
const REPO_URL = "https://github.com/test-owner/test-repo";

/** A terminal thenable returning { data, error } for .single()/.maybeSingle(). */
function term(data: unknown, error: unknown = null) {
  return {
    then: (onfulfilled?: (v: unknown) => unknown) =>
      Promise.resolve({ data, error }).then(onfulfilled),
  };
}

/**
 * Strict per-table dispatcher. `tables` maps table name → terminal result;
 * every chain method (select/eq) returns the chain and terminals resolve the
 * mapped row. An unmapped table throws so a missing wiring fails loud (not a
 * silent any-query pass).
 */
function supabaseFor(tables: Record<string, { data: unknown; error?: unknown }>) {
  const fromSpy = vi.fn((table: string) => {
    if (!(table in tables)) {
      throw new Error(`unexpected table read: ${table}`);
    }
    const t = tables[table];
    const chain: Record<string, unknown> = {};
    chain.select = vi.fn(() => chain);
    chain.eq = vi.fn(() => chain);
    chain.maybeSingle = vi.fn(() => term(t.data, t.error ?? null));
    chain.single = vi.fn(() => term(t.data, t.error ?? null));
    return chain;
  });
  return { from: fromSpy } as unknown as Parameters<
    typeof resolveActiveWorkspaceRepoMeta
  >[1];
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("resolveActiveWorkspaceRepoMeta", () => {
  it("solo owner: resolves own active workspace's repo_url + installation", async () => {
    mockResolveInstallationId.mockResolvedValue(12345);
    // Solo: current_workspace_id null → solo (== userId); the membership probe
    // is skipped (activeWorkspaceId === userId). Only user_session_state +
    // workspaces are read.
    const supabase = supabaseFor({
      user_session_state: { data: { current_workspace_id: null } },
      workspaces: { data: { repo_url: REPO_URL } },
    });

    const result = await resolveActiveWorkspaceRepoMeta(SOLO_USER, supabase);

    expect(result).toEqual({
      ok: true,
      repoUrl: REPO_URL,
      githubInstallationId: 12345,
    });
    // The installation MUST be resolved for the SOLO active id (= userId),
    // never re-derived or read for a sibling.
    expect(mockResolveInstallationId).toHaveBeenCalledWith(SOLO_USER, SOLO_USER);
  });

  it("shared member: resolves the WORKSPACE's repo + installation (fixes #4543 dual-ownership)", async () => {
    mockResolveInstallationId.mockResolvedValue(67890);
    // Active claim is a shared (non-solo) workspace the caller IS a member of.
    const supabase = supabaseFor({
      user_session_state: { data: { current_workspace_id: SHARED_WS } },
      workspace_members: { data: { user_id: SOLO_USER } }, // membership confirmed
      workspaces: { data: { repo_url: REPO_URL } },
    });

    const result = await resolveActiveWorkspaceRepoMeta(SOLO_USER, supabase);

    expect(result).toEqual({
      ok: true,
      repoUrl: REPO_URL,
      githubInstallationId: 67890,
    });
    // Installation resolved for the SHARED workspace id (the owner's repo),
    // via the membership-checked RPC — NOT the caller's empty users row.
    expect(mockResolveInstallationId).toHaveBeenCalledWith(SOLO_USER, SHARED_WS);
  });

  it("non-member stale claim self-heals to SOLO (never a sibling)", async () => {
    mockResolveInstallationId.mockResolvedValue(12345);
    // Active claim is a workspace the caller is NOT a member of → membership
    // probe returns null → fall back to solo (= userId).
    const supabase = supabaseFor({
      user_session_state: { data: { current_workspace_id: SHARED_WS } },
      workspace_members: { data: null }, // not a member
      workspaces: { data: { repo_url: REPO_URL } },
    });

    const result = await resolveActiveWorkspaceRepoMeta(SOLO_USER, supabase);

    expect(result.ok).toBe(true);
    // Installation resolved for the SOLO id, never the sibling SHARED_WS.
    expect(mockResolveInstallationId).toHaveBeenCalledWith(SOLO_USER, SOLO_USER);
  });

  it("missing repo_url → 404 (no repository connected)", async () => {
    const supabase = supabaseFor({
      user_session_state: { data: { current_workspace_id: null } },
      workspaces: { data: { repo_url: null } },
    });

    const result = await resolveActiveWorkspaceRepoMeta(SOLO_USER, supabase);

    expect(result).toEqual({ ok: false, status: 404 });
    expect(mockResolveInstallationId).not.toHaveBeenCalled();
  });

  it("repo connected but no installation resolvable → 400", async () => {
    mockResolveInstallationId.mockResolvedValue(null);
    const supabase = supabaseFor({
      user_session_state: { data: { current_workspace_id: null } },
      workspaces: { data: { repo_url: REPO_URL } },
    });

    const result = await resolveActiveWorkspaceRepoMeta(SOLO_USER, supabase);

    expect(result).toEqual({ ok: false, status: 400 });
  });

  it("workspaces read error → 503 and mirrors to Sentry", async () => {
    const supabase = supabaseFor({
      user_session_state: { data: { current_workspace_id: null } },
      workspaces: { data: null, error: { message: "connection lost" } },
    });

    const result = await resolveActiveWorkspaceRepoMeta(SOLO_USER, supabase);

    expect(result).toEqual({ ok: false, status: 503 });
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "workspace-resolver",
        op: "resolveActiveWorkspaceRepoMeta.workspaces-read",
      }),
    );
    expect(mockResolveInstallationId).not.toHaveBeenCalled();
  });
});
