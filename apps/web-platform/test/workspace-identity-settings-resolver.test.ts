import { describe, it, expect, beforeEach, vi } from "vitest";

// Resolver for the General settings page's workspace-identity controls
// (#4916 follow-up). Unlike resolveTeamMembershipPageData, this resolver does
// NOT consult the team-workspace-invite flag — so the logo + rename controls are
// reachable on General even when the Members/Team tab is gated OFF (AC7
// reachability fix). It resolves the SAME workspace the upload route writes to
// (plain resolveCurrentWorkspaceId — no self-heal divergence).

const RESOLVED_WS = "11111111-1111-1111-1111-111111111111";
const ORG_ID = "22222222-2222-2222-2222-222222222222";

const { mockResolveWs, mockTeamFlag } = vi.hoisted(() => ({
  mockResolveWs: vi.fn(),
  mockTeamFlag: vi.fn(),
}));

vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentWorkspaceId: mockResolveWs,
}));

// The whole point of AC7: the General resolver must NOT gate on this flag.
vi.mock("@/lib/feature-flags/server", () => ({
  isTeamWorkspaceInviteEnabled: mockTeamFlag,
}));

let resolveWorkspaceIdentityForSettings: typeof import("@/server/workspace-identity-resolver").resolveWorkspaceIdentityForSettings;

beforeEach(async () => {
  vi.clearAllMocks();
  mockResolveWs.mockResolvedValue(RESOLVED_WS);
  mockTeamFlag.mockResolvedValue(false); // flag OFF — must NOT block resolution
  ({ resolveWorkspaceIdentityForSettings } = await import(
    "@/server/workspace-identity-resolver"
  ));
});

const USER = { id: "user-1" };

function makeSupabase(isOwner: boolean) {
  return {
    auth: { getUser: vi.fn(async () => ({ data: { user: USER }, error: null })) },
    rpc: vi.fn(async () => ({ data: isOwner, error: null })),
  };
}

// Recursive structural mock: every chain method returns the same object; the
// terminal maybeSingle resolves per-table from a fixture map.
function makeService(rows: Record<string, unknown>) {
  return {
    from: (table: string) => {
      const chain: Record<string, unknown> = {};
      for (const m of ["select", "eq"]) chain[m] = () => chain;
      chain.maybeSingle = async () => ({ data: rows[table] ?? null, error: null });
      return chain;
    },
  };
}

describe("resolveWorkspaceIdentityForSettings (General page — AC6/AC7/AC8)", () => {
  it("resolves identity for the active workspace WITHOUT consulting the team flag (reachability)", async () => {
    const supabase = makeSupabase(true);
    const service = makeService({
      workspaces: { organization_id: ORG_ID, logo_path: `${RESOLVED_WS}/logo.webp` },
      organizations: { name: "Acme" },
    });
    const result = await resolveWorkspaceIdentityForSettings(
      supabase as never,
      service as never,
    );
    expect(result).toEqual({
      workspaceId: RESOLVED_WS,
      organizationId: ORG_ID,
      organizationName: "Acme",
      isOwner: true,
      hasLogo: true,
    });
    // AC7: the team-invite flag must never gate the General identity controls.
    expect(mockTeamFlag).not.toHaveBeenCalled();
  });

  it("reports isOwner=false for a non-owner (drives the disabled owner-gated control, AC8)", async () => {
    const supabase = makeSupabase(false);
    const service = makeService({
      workspaces: { organization_id: ORG_ID, logo_path: null },
      organizations: { name: "Acme" },
    });
    const result = await resolveWorkspaceIdentityForSettings(
      supabase as never,
      service as never,
    );
    expect(result?.isOwner).toBe(false);
    expect(result?.hasLogo).toBe(false);
  });

  it("returns null when no workspace row exists (renders nothing, no crash)", async () => {
    const supabase = makeSupabase(true);
    const service = makeService({}); // workspaces → null
    const result = await resolveWorkspaceIdentityForSettings(
      supabase as never,
      service as never,
    );
    expect(result).toBeNull();
  });

  it("returns null for an unauthenticated caller", async () => {
    const supabase = {
      auth: { getUser: vi.fn(async () => ({ data: { user: null }, error: null })) },
      rpc: vi.fn(),
    };
    const service = makeService({});
    const result = await resolveWorkspaceIdentityForSettings(
      supabase as never,
      service as never,
    );
    expect(result).toBeNull();
  });
});
