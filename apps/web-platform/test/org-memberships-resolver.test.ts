import { describe, it, expect, vi, beforeEach } from "vitest";

// AC7 (feat-one-shot-workspace-untitled-name): the org-memberships resolver is
// the ACTUAL source of the "Untitled" sentinel — it substitutes
// UNTITLED_FALLBACK only when an org name is NULL, and passes real names
// through verbatim. Migration 091 backfills names so the fallback is
// defense-in-depth; this test pins both arms so a regression that drops the
// fallback (or that mis-substitutes a real name) is caught.

const { mockResolveCurrentOrg } = vi.hoisted(() => ({
  mockResolveCurrentOrg: vi.fn(),
}));

vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentOrganizationId: mockResolveCurrentOrg,
}));

import { resolveOrgMemberships } from "@/server/org-memberships-resolver";
import { UNTITLED_FALLBACK } from "@/lib/workspace-name";

const USER_ID = "u1";

function makeSupabase() {
  return {
    auth: {
      getUser: async () => ({ data: { user: { id: USER_ID } }, error: null }),
    },
  };
}

// org-1 has a real name, org-2 has a NULL name (pre-091 / unreachable post-091).
function makeService() {
  return {
    from: (table: string) => {
      if (table === "workspace_members") {
        return {
          select: (_cols: string) => ({
            // memberships lookup (.eq user_id)
            eq: async () => ({
              data: [
                { workspace_id: "ws-1", role: "owner" },
                { workspace_id: "ws-2", role: "member" },
              ],
              error: null,
            }),
            // member-count lookup (.in workspace_id)
            in: async () => ({
              data: [
                { workspace_id: "ws-1", user_id: "u1" },
                { workspace_id: "ws-1", user_id: "u2" },
                { workspace_id: "ws-2", user_id: "u1" },
              ],
              error: null,
            }),
          }),
        };
      }
      if (table === "workspaces") {
        return {
          select: (_cols: string) => ({
            in: async () => ({
              data: [
                { id: "ws-1", organization_id: "org-1" },
                { id: "ws-2", organization_id: "org-2" },
              ],
              error: null,
            }),
          }),
        };
      }
      if (table === "organizations") {
        return {
          select: (_cols: string) => ({
            in: async () => ({
              data: [
                { id: "org-1", name: "jikigai" },
                { id: "org-2", name: null },
              ],
              error: null,
            }),
          }),
        };
      }
      throw new Error(`unexpected table ${table}`);
    },
  };
}

describe("resolveOrgMemberships — AC7 name fallback", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockResolveCurrentOrg.mockResolvedValue("org-1");
  });

  it("passes a real org name through verbatim", async () => {
    const summaries = await resolveOrgMemberships(
      makeSupabase() as never,
      makeService() as never,
    );
    const org1 = summaries.find((s) => s.organizationId === "org-1");
    expect(org1?.organizationName).toBe("jikigai");
    expect(org1?.organizationName).not.toBe(UNTITLED_FALLBACK);
  });

  it("substitutes UNTITLED_FALLBACK only when the stored name is NULL", async () => {
    const summaries = await resolveOrgMemberships(
      makeSupabase() as never,
      makeService() as never,
    );
    const org2 = summaries.find((s) => s.organizationId === "org-2");
    expect(org2?.organizationName).toBe(UNTITLED_FALLBACK);
  });
});
