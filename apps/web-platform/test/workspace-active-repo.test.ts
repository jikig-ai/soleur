import { describe, it, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// GET /api/workspace/active-repo (ADR-044, #4543)
//
// Returns the ACTIVE workspace's repo (workspaces-only — never users.repo_url,
// the dual-ownership trap). Self-heals J5: when the current_workspace_id claim
// points at a workspace the user is no longer a member of, it resets the claim
// to the personal (solo) workspace and reports fellBackToSolo.
// ---------------------------------------------------------------------------

const USER_ID = "11111111-1111-1111-1111-111111111111";
// N2 invariant (ADR-038): the solo workspace id equals the user id.
const SOLO_WS = USER_ID;
const JOINED_WS = "22222222-2222-2222-2222-222222222222";

interface FixtureState {
  currentWorkspaceId: string | null;
  // membership lookup result, keyed by workspace id the user is a member of
  memberOf: Set<string>;
  // repo row per workspace id
  repoByWorkspace: Record<string, { repo_url: string | null; repo_status: string | null }>;
}

let state: FixtureState;
const mockRpc = vi.fn(async () => ({ data: null, error: null }));

function makeMaybeSingle(value: unknown) {
  return vi.fn(async () => ({ data: value, error: null }));
}

vi.mock("@/lib/supabase/server", () => {
  const mockFrom = vi.fn((table: string) => {
    if (table === "user_session_state") {
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: makeMaybeSingle({
              current_workspace_id: state.currentWorkspaceId,
            }),
          }),
        }),
      };
    }
    if (table === "workspace_members") {
      return {
        select: () => ({
          eq: (_col: string, wsId: string) => ({
            eq: () => ({
              maybeSingle: makeMaybeSingle(
                state.memberOf.has(wsId) ? { user_id: USER_ID } : null,
              ),
            }),
          }),
        }),
      };
    }
    if (table === "workspaces") {
      return {
        select: () => ({
          eq: (_col: string, wsId: string) => ({
            maybeSingle: makeMaybeSingle(state.repoByWorkspace[wsId] ?? null),
          }),
        }),
      };
    }
    throw new Error(`unexpected table ${table}`);
  });

  return {
    createClient: vi.fn(async () => ({
      auth: {
        getUser: vi.fn(async () => ({ data: { user: { id: USER_ID } } })),
      },
      rpc: mockRpc,
    })),
    createServiceClient: vi.fn(() => ({ from: mockFrom })),
  };
});

import { GET } from "@/app/api/workspace/active-repo/route";

describe("GET /api/workspace/active-repo", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    state = {
      currentWorkspaceId: null,
      memberOf: new Set([SOLO_WS]),
      repoByWorkspace: {
        [SOLO_WS]: { repo_url: "https://github.com/alice/solo", repo_status: "ready" },
        [JOINED_WS]: { repo_url: "https://github.com/bob/team", repo_status: "ready" },
      },
    };
  });

  it("J6: no claim → resolves the personal (solo) workspace repo", async () => {
    state.currentWorkspaceId = null;
    const res = await GET();
    const json = await res.json();
    expect(json.workspaceId).toBe(SOLO_WS);
    expect(json.repoName).toBe("alice/solo");
    expect(json.fellBackToSolo).toBe(false);
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("member of the active joined workspace → returns that workspace's repo, never users.repo_url", async () => {
    state.currentWorkspaceId = JOINED_WS;
    state.memberOf = new Set([SOLO_WS, JOINED_WS]);
    const res = await GET();
    const json = await res.json();
    expect(json.workspaceId).toBe(JOINED_WS);
    expect(json.repoName).toBe("bob/team");
    expect(json.fellBackToSolo).toBe(false);
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("J5: claim points at a workspace the user no longer belongs to → resets to solo + fellBackToSolo", async () => {
    state.currentWorkspaceId = JOINED_WS;
    state.memberOf = new Set([SOLO_WS]); // removed from JOINED_WS
    const res = await GET();
    const json = await res.json();
    expect(mockRpc).toHaveBeenCalledWith("set_current_workspace_id", {
      p_workspace_id: SOLO_WS,
    });
    expect(json.workspaceId).toBe(SOLO_WS);
    expect(json.repoName).toBe("alice/solo");
    expect(json.fellBackToSolo).toBe(true);
  });

  it("returns 401 when unauthenticated", async () => {
    const { createClient } = await import("@/lib/supabase/server");
    (createClient as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      auth: { getUser: vi.fn(async () => ({ data: { user: null } })) },
      rpc: mockRpc,
    });
    const res = await GET();
    expect(res.status).toBe(401);
  });
});
