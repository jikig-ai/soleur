import { describe, it, expect, vi, beforeEach } from "vitest";
import { resolveTeamMembershipPageData } from "@/server/team-membership-resolver";
import { __resetFeatureFlagsForTests } from "@/lib/feature-flags/server";

// #4715 Phase 8: the resolver computes per-member hasEffectiveKey via
// userHasEffectiveByokKey (own-key signal, fail-closed). Mock the helper so the
// resolver doesn't hit the live api_keys/delegations tables. Default false
// (keyless) — individual tests override per user via mockImplementation.
const { mockUserHasEffectiveByokKey } = vi.hoisted(() => ({
  mockUserHasEffectiveByokKey: vi.fn(),
}));
vi.mock("@/server/byok-resolver", () => ({
  userHasEffectiveByokKey: mockUserHasEffectiveByokKey,
}));

// Flagsmith single-control gate. Tests stub via env vars so resolver exercises
// the real gate logic (env-fallback path when FLAGSMITH_ENVIRONMENT_KEY unset).

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
  sessionOrgId?: string | null;
  orgName?: string | null;
  // current_workspace_id from user_session_state (ADR-044 active workspace).
  // undefined → omit the field (resolveCurrentWorkspaceId falls back to user.id).
  sessionWorkspaceId?: string | null;
  // The (older) workspace the legacy unordered `workspaces[0]` path would have
  // picked — used to prove the resolver converged onto current_workspace_id and
  // no longer derives the id from the workspaces table.
  olderWorkspaceId?: string;
  // J5 self-heal: whether the caller is a member of the claimed workspace.
  // false → the membership probe returns null and the resolver falls back to
  // the caller's own solo workspace (user.id), never a sibling. Default true.
  ownerIsMemberOfClaimed?: boolean;
}

function mockSupabaseClients(opts: ResolveOpts) {
  const userResp = { data: { user: opts.user }, error: null };
  const isMember = opts.ownerIsMemberOfClaimed !== false;
  const fromMock = vi.fn((table: string) => {
    if (table === "workspaces") {
      const wsId = opts.olderWorkspaceId ?? opts.members[0]?.workspace_id ?? WORKSPACE_ID;
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
            // Member-list path: .select().eq("workspace_id", ws).order(...)
            order: () =>
              Promise.resolve({ data: opts.members, error: null }),
            // J5 self-heal probe: .select().eq("workspace_id", ws).eq("user_id", u).maybeSingle()
            eq: () => ({
              maybeSingle: () =>
                Promise.resolve({
                  data: isMember ? { user_id: opts.user?.id } : null,
                  error: null,
                }),
            }),
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
    if (table === "organizations") {
      return {
        select: () => ({
          eq: () => ({
            single: () =>
              Promise.resolve({
                data: { name: opts.orgName ?? null },
                error: null,
              }),
          }),
        }),
      };
    }
    if (table === "user_session_state") {
      const orgId = opts.sessionOrgId !== undefined ? opts.sessionOrgId : null;
      const wsId = opts.sessionWorkspaceId;
      // Single row carries both columns; resolveCurrentOrganizationId reads
      // current_organization_id, resolveCurrentWorkspaceId reads
      // current_workspace_id (both via .select().eq("user_id").maybeSingle()).
      const row =
        orgId !== null || (wsId !== undefined && wsId !== null)
          ? {
              current_organization_id: orgId,
              ...(wsId !== undefined ? { current_workspace_id: wsId } : {}),
            }
          : null;
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: () => Promise.resolve({ data: row, error: null }),
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
    vi.stubEnv("FLAGSMITH_ENVIRONMENT_KEY", "");
    // Force the byok-delegations runtime flag OFF so the resolver's
    // `isByokDelegationsEnabled` branch (which queries the byok_delegations
    // table — not covered by this file's mockSupabaseClients) stays dormant.
    // Without this, `doppler run -c dev` injects FLAG_BYOK_DELEGATIONS=1 and
    // the resolver hits the mock's `unmocked table: byok_delegations` throw.
    // vi.unstubAllEnvs() cannot clear a process-inherited var; vi.stubEnv("")
    // overwrites it. See #4663 and the env-leak learning
    // 2026-05-20-vitest-unstub-does-not-clear-process-inherited-env-vars.
    vi.stubEnv("FLAG_BYOK_DELEGATIONS", "");
    __resetFeatureFlagsForTests();
    mockUserHasEffectiveByokKey.mockReset();
    mockUserHasEffectiveByokKey.mockResolvedValue(false);
  });

  it("AC-A: returns not-found when feature flag is OFF", async () => {
    vi.stubEnv("FLAG_TEAM_WORKSPACE_INVITE", "");
    const { supabase, service } = mockSupabaseClients({
      user: {
        id: USER_ID,
        email: "jean@jikigai.com",
        app_metadata: {},
      },
      sessionOrgId: ORG_ID,
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

  it("returns ok with members + current-user when flag ON", async () => {
    vi.stubEnv("FLAG_TEAM_WORKSPACE_INVITE", "1");
    const otherUser = "00000000-0000-0000-0000-000000000222";
    const { supabase, service } = mockSupabaseClients({
      user: {
        id: USER_ID,
        email: "jean@jikigai.com",
        app_metadata: {},
      },
      sessionOrgId: ORG_ID,
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

  it("#4715: per-member hasEffectiveKey — keyed member true, keyless member false", async () => {
    vi.stubEnv("FLAG_TEAM_WORKSPACE_INVITE", "1");
    const keyedMember = "00000000-0000-0000-0000-000000000333";
    const keylessMember = "00000000-0000-0000-0000-000000000444";
    // Own-key signal only — keyed only for keyedMember.
    mockUserHasEffectiveByokKey.mockImplementation(async (userId: string) =>
      userId === keyedMember,
    );
    const { supabase, service } = mockSupabaseClients({
      user: { id: USER_ID, email: "jean@jikigai.com", app_metadata: {} },
      sessionOrgId: ORG_ID,
      members: [
        { workspace_id: WORKSPACE_ID, user_id: USER_ID, role: "owner", created_at: "2026-01-01T00:00:00Z" },
        { workspace_id: WORKSPACE_ID, user_id: keyedMember, role: "member", created_at: "2026-02-01T00:00:00Z" },
        { workspace_id: WORKSPACE_ID, user_id: keylessMember, role: "member", created_at: "2026-03-01T00:00:00Z" },
      ],
      emails: {
        [USER_ID]: { email: "jean@jikigai.com", created_at: "2025-01-01T00:00:00Z" },
        [keyedMember]: { email: "keyed@x.com", created_at: "2025-02-01T00:00:00Z" },
        [keylessMember]: { email: "keyless@x.com", created_at: "2025-03-01T00:00:00Z" },
      },
    });
    const result = await resolveTeamMembershipPageData(supabase as never, service as never);
    expect(result.ok).toBe(true);
    if (result.ok) {
      const keyed = result.data.members.find((m) => m.userId === keyedMember);
      const keyless = result.data.members.find((m) => m.userId === keylessMember);
      expect(keyed?.hasEffectiveKey).toBe(true);
      expect(keyless?.hasEffectiveKey).toBe(false);
      // Fail-closed: helper invoked with onErrorReturn:false per member.
      expect(mockUserHasEffectiveByokKey).toHaveBeenCalledWith(
        keylessMember,
        expect.objectContaining({ onErrorReturn: false }),
      );
    }
  });

  // Symptoms 1 & 2 (persistence + share-failure): the owner page derived its
  // workspaceId from an UNORDERED `workspaces.organization_id=orgId [0]`, a third
  // resolution mechanism distinct from both getDefaultWorkspaceForUser and the
  // canonical resolveCurrentWorkspaceId. When an owner's org has >1 workspace,
  // the workspace the grant is WRITTEN to (and the toggle state READ from) could
  // diverge from the workspace the member CONSUMES from (#4767), so the persisted
  // delegation was invisible on reload. Fix: converge on resolveCurrentWorkspaceId.
  const OLDER_WORKSPACE_V = "00000000-0000-0000-0000-000000000ccc";

  it("AC3/AC5: resolves workspaceId via current_workspace_id (W), not the unordered older workspace (V)", async () => {
    vi.stubEnv("FLAG_TEAM_WORKSPACE_INVITE", "1");
    const otherUser = "00000000-0000-0000-0000-000000000222";
    const { supabase, service } = mockSupabaseClients({
      user: { id: USER_ID, email: "jean@jikigai.com", app_metadata: {} },
      sessionOrgId: ORG_ID,
      // Active workspace = the shared W; the org ALSO contains an older V that
      // the legacy unordered-[0] path would have picked.
      sessionWorkspaceId: WORKSPACE_ID,
      olderWorkspaceId: OLDER_WORKSPACE_V,
      members: [
        { workspace_id: WORKSPACE_ID, user_id: USER_ID, role: "owner", created_at: "2026-01-01T00:00:00Z" },
        { workspace_id: WORKSPACE_ID, user_id: otherUser, role: "member", created_at: "2026-02-01T00:00:00Z" },
      ],
      emails: {
        [USER_ID]: { email: "jean@jikigai.com", created_at: "2025-01-01T00:00:00Z" },
        [otherUser]: { email: "harry@jikigai.com", created_at: "2025-02-01T00:00:00Z" },
      },
    });
    const result = await resolveTeamMembershipPageData(supabase as never, service as never);
    expect(result.ok).toBe(true);
    if (result.ok) {
      // The id the page reads delegations from / passes to the grant POST body
      // is the canonical active workspace W, never the stale older V.
      expect(result.data.workspaceId).toBe(WORKSPACE_ID);
      expect(result.data.workspaceId).not.toBe(OLDER_WORKSPACE_V);
    }
  });

  it("AC4: fails closed to the caller's own solo workspace when not a member of the claimed workspace (never a sibling)", async () => {
    vi.stubEnv("FLAG_TEAM_WORKSPACE_INVITE", "1");
    const { supabase, service } = mockSupabaseClients({
      user: { id: USER_ID, email: "jean@jikigai.com", app_metadata: {} },
      sessionOrgId: ORG_ID,
      // current_workspace_id points at a sibling workspace W the caller is NOT a
      // member of (stale claim). The J5 self-heal must fall back to user.id solo.
      sessionWorkspaceId: WORKSPACE_ID,
      olderWorkspaceId: OLDER_WORKSPACE_V, // legacy [0] path would return V ≠ user.id (genuine RED)
      ownerIsMemberOfClaimed: false,
      members: [
        { workspace_id: USER_ID, user_id: USER_ID, role: "owner", created_at: "2026-01-01T00:00:00Z" },
      ],
      emails: {
        [USER_ID]: { email: "jean@jikigai.com", created_at: "2025-01-01T00:00:00Z" },
      },
    });
    const result = await resolveTeamMembershipPageData(supabase as never, service as never);
    expect(result.ok).toBe(true);
    if (result.ok) {
      // Never the sibling W — fall back to the caller's own solo workspace.
      expect(result.data.workspaceId).toBe(USER_ID);
      expect(result.data.workspaceId).not.toBe(WORKSPACE_ID);
    }
  });

  it("AC4 (NULL claim): a NULL current_workspace_id resolves to the owner's own solo workspace", async () => {
    vi.stubEnv("FLAG_TEAM_WORKSPACE_INVITE", "1");
    const { supabase, service } = mockSupabaseClients({
      user: { id: USER_ID, email: "jean@jikigai.com", app_metadata: {} },
      sessionOrgId: ORG_ID,
      sessionWorkspaceId: null, // owner never switched workspaces
      olderWorkspaceId: OLDER_WORKSPACE_V, // legacy [0] path would return V ≠ user.id (genuine RED)
      members: [
        { workspace_id: USER_ID, user_id: USER_ID, role: "owner", created_at: "2026-01-01T00:00:00Z" },
      ],
      emails: {
        [USER_ID]: { email: "jean@jikigai.com", created_at: "2025-01-01T00:00:00Z" },
      },
    });
    const result = await resolveTeamMembershipPageData(supabase as never, service as never);
    expect(result.ok).toBe(true);
    if (result.ok) {
      // N2 invariant: solo workspace_id === user_id. NULL claim → solo (user.id).
      expect(result.data.workspaceId).toBe(USER_ID);
    }
  });

  it("AC-FLOW4 surface: returns owner role for self so UI can disable remove-self", async () => {
    vi.stubEnv("FLAG_TEAM_WORKSPACE_INVITE", "1");
    const { supabase, service } = mockSupabaseClients({
      user: {
        id: USER_ID,
        email: "jean@jikigai.com",
        app_metadata: {},
      },
      sessionOrgId: ORG_ID,
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
