import { describe, it, expect, vi, beforeEach } from "vitest";
import { resolveTeamMembershipPageData } from "@/server/team-membership-resolver";

// Mock the 2-key gate (FLAG_TEAM_WORKSPACE_INVITE + TEAM_WORKSPACE_ALLOWLIST_ORG_IDS).
// Tests stub via env vars so resolver exercises the real gate logic.

const ORG_ID = "00000000-0000-0000-0000-000000000aaa";
const USER_ID = "00000000-0000-0000-0000-000000000111";
const WORKSPACE_ID = "00000000-0000-0000-0000-000000000bbb";

interface MockRow {
  workspace_id: string;
  user_id: string;
  role: "owner" | "member";
  created_at: string;
}

interface ResolveOpts {
  user: { id: string; email: string; app_metadata: Record<string, unknown> } | null;
  members: MockRow[];
  emails: Record<string, { email: string; created_at: string }>;
}

function mockSupabaseClients(opts: ResolveOpts) {
  const userResp = { data: { user: opts.user }, error: null };
  const fromMock = vi.fn((table: string) => {
    if (table === "workspaces") {
      // Resolver queries: .select("id").eq("organization_id", orgId)
      // Returns first workspace_id matching the org.
      const wsId = opts.members[0]?.workspace_id ?? WORKSPACE_ID;
      return {
        select: () => ({
          eq: () =>
            Promise.resolve({
              data: opts.members.length > 0 ? [{ id: wsId }] : [],
              error: null,
            }),
        }),
      };
    }
    if (table === "workspace_members") {
      return {
        select: () => ({
          eq: () => ({
            order: () =>
              Promise.resolve({ data: opts.members, error: null }),
          }),
        }),
      };
    }
    if (table === "users") {
      return {
        select: () => ({
          in: () =>
            Promise.resolve({
              data: Object.entries(opts.emails).map(([id, row]) => ({
                id,
                email: row.email,
                created_at: row.created_at,
              })),
              error: null,
            }),
        }),
      };
    }
    throw new Error(`unmocked table: ${table}`);
  });
  const supabase = {
    auth: { getUser: () => Promise.resolve(userResp) },
  };
  const service = { from: fromMock };
  return { supabase, service };
}

describe("resolveTeamMembershipPageData", () => {
  beforeEach(() => {
    vi.unstubAllEnvs();
    vi.stubEnv("FLAG_TEAM_WORKSPACE_INVITE", "");
    vi.stubEnv("TEAM_WORKSPACE_ALLOWLIST_ORG_IDS", "");
  });

  it("AC-A: returns not-found when feature flag is OFF", async () => {
    vi.stubEnv("FLAG_TEAM_WORKSPACE_INVITE", "");
    vi.stubEnv("TEAM_WORKSPACE_ALLOWLIST_ORG_IDS", ORG_ID);
    const { supabase, service } = mockSupabaseClients({
      user: {
        id: USER_ID,
        email: "jean@jikigai.com",
        app_metadata: { current_organization_id: ORG_ID },
      },
      members: [],
      emails: {},
    });
    const result = await resolveTeamMembershipPageData(
      supabase as never,
      service as never,
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("not-found");
  });

  it("AC-A: returns not-found when org NOT in allowlist", async () => {
    vi.stubEnv("FLAG_TEAM_WORKSPACE_INVITE", "1");
    vi.stubEnv("TEAM_WORKSPACE_ALLOWLIST_ORG_IDS", "ffffffff-ffff-ffff-ffff-ffffffffffff");
    const { supabase, service } = mockSupabaseClients({
      user: {
        id: USER_ID,
        email: "jean@jikigai.com",
        app_metadata: { current_organization_id: ORG_ID },
      },
      members: [],
      emails: {},
    });
    const result = await resolveTeamMembershipPageData(
      supabase as never,
      service as never,
    );
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("not-found");
  });

  it("returns not-found when no current org claim", async () => {
    vi.stubEnv("FLAG_TEAM_WORKSPACE_INVITE", "1");
    vi.stubEnv("TEAM_WORKSPACE_ALLOWLIST_ORG_IDS", ORG_ID);
    const { supabase, service } = mockSupabaseClients({
      user: { id: USER_ID, email: "jean@jikigai.com", app_metadata: {} },
      members: [],
      emails: {},
    });
    const result = await resolveTeamMembershipPageData(
      supabase as never,
      service as never,
    );
    expect(result.ok).toBe(false);
  });

  it("returns ok with members + current-user when flag ON and in allowlist", async () => {
    vi.stubEnv("FLAG_TEAM_WORKSPACE_INVITE", "1");
    vi.stubEnv("TEAM_WORKSPACE_ALLOWLIST_ORG_IDS", ORG_ID);
    const otherUser = "00000000-0000-0000-0000-000000000222";
    const { supabase, service } = mockSupabaseClients({
      user: {
        id: USER_ID,
        email: "jean@jikigai.com",
        app_metadata: { current_organization_id: ORG_ID },
      },
      members: [
        {
          workspace_id: WORKSPACE_ID,
          user_id: USER_ID,
          role: "owner",
          created_at: "2026-01-01T00:00:00Z",
        },
        {
          workspace_id: WORKSPACE_ID,
          user_id: otherUser,
          role: "member",
          created_at: "2026-02-01T00:00:00Z",
        },
      ],
      emails: {
        [USER_ID]: { email: "jean@jikigai.com", created_at: "2025-01-01T00:00:00Z" },
        [otherUser]: { email: "harry@jikigai.com", created_at: "2025-02-01T00:00:00Z" },
      },
    });
    const result = await resolveTeamMembershipPageData(
      supabase as never,
      service as never,
    );
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data.organizationId).toBe(ORG_ID);
      expect(result.data.currentUserId).toBe(USER_ID);
      expect(result.data.members).toHaveLength(2);
      const owner = result.data.members.find((m) => m.role === "owner");
      expect(owner?.email).toBe("jean@jikigai.com");
    }
  });

  it("AC-FLOW4 surface: returns owner role for self so UI can disable remove-self", async () => {
    vi.stubEnv("FLAG_TEAM_WORKSPACE_INVITE", "1");
    vi.stubEnv("TEAM_WORKSPACE_ALLOWLIST_ORG_IDS", ORG_ID);
    const { supabase, service } = mockSupabaseClients({
      user: {
        id: USER_ID,
        email: "jean@jikigai.com",
        app_metadata: { current_organization_id: ORG_ID },
      },
      members: [
        {
          workspace_id: WORKSPACE_ID,
          user_id: USER_ID,
          role: "owner",
          created_at: "2026-01-01T00:00:00Z",
        },
      ],
      emails: {
        [USER_ID]: { email: "jean@jikigai.com", created_at: "2025-01-01T00:00:00Z" },
      },
    });
    const result = await resolveTeamMembershipPageData(
      supabase as never,
      service as never,
    );
    expect(result.ok).toBe(true);
    if (result.ok) {
      const self = result.data.members.find((m) => m.userId === USER_ID);
      expect(self?.isSelf).toBe(true);
      expect(self?.role).toBe("owner");
    }
  });
});
