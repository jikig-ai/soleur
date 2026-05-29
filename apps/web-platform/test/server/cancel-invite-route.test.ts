import { describe, test, expect, vi, beforeEach } from "vitest";

// POST /api/workspace/cancel-invite (feat-cancel-pending-invite, #4634, TR5).
// Mirrors remove-member's auth chain: CSRF → auth → page-data resolve → flag
// gate → workspace-match → owner-check → revokeWorkspaceInvitation. Owner-only
// (single-user-incident threshold): non-owner and cross-workspace callers are
// rejected before the RPC runs; terminal-state reasons map to 404/409.

const {
  mockGetUser,
  mockValidateOrigin,
  mockRejectCsrf,
  mockResolvePageData,
  mockIsTeamWorkspaceInviteEnabled,
  mockRevoke,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockValidateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
  mockRejectCsrf: vi.fn(() => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 })),
  mockResolvePageData: vi.fn(),
  mockIsTeamWorkspaceInviteEnabled: vi.fn(async () => true),
  mockRevoke: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({ auth: { getUser: mockGetUser } })),
  createServiceClient: vi.fn(() => ({})),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: mockRejectCsrf,
}));

vi.mock("@/lib/feature-flags/server", () => ({
  isTeamWorkspaceInviteEnabled: mockIsTeamWorkspaceInviteEnabled,
}));

vi.mock("@/server/team-membership-resolver", () => ({
  resolveTeamMembershipPageData: mockResolvePageData,
}));

vi.mock("@/server/workspace-invitations", () => ({
  revokeWorkspaceInvitation: mockRevoke,
}));

import { POST } from "@/app/api/workspace/cancel-invite/route";

const OWNER_ID = "owner-uuid";
const WORKSPACE_ID = "ws-uuid";
const ORG_ID = "org-uuid";
const INVITATION_ID = "inv-uuid";

function makeRequest(body: Record<string, unknown>): Request {
  return new Request("https://app.soleur.ai/api/workspace/cancel-invite", {
    method: "POST",
    headers: { origin: "https://app.soleur.ai", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function ownerPageData() {
  return {
    ok: true,
    data: {
      workspaceId: WORKSPACE_ID,
      organizationId: ORG_ID,
      currentUserId: OWNER_ID,
      members: [{ userId: OWNER_ID, role: "owner" }],
    },
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
  mockRejectCsrf.mockReturnValue(new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }));
  mockIsTeamWorkspaceInviteEnabled.mockResolvedValue(true);
  mockGetUser.mockResolvedValue({ data: { user: { id: OWNER_ID, email: "o@example.com" } } });
  mockResolvePageData.mockResolvedValue(ownerPageData());
  mockRevoke.mockResolvedValue({ ok: true });
});

describe("POST /api/workspace/cancel-invite", () => {
  test("200 happy path — owner revokes, RPC called with invitation + caller", async () => {
    const res = await POST(makeRequest({ workspaceId: WORKSPACE_ID, invitationId: INVITATION_ID }));
    expect(res.status).toBe(200);
    expect(mockRevoke).toHaveBeenCalledWith(INVITATION_ID, OWNER_ID);
  });

  test("403 (CSRF) when origin invalid", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: "https://evil.example" });
    const res = await POST(makeRequest({ workspaceId: WORKSPACE_ID, invitationId: INVITATION_ID }));
    expect(res.status).toBe(403);
    expect(mockRevoke).not.toHaveBeenCalled();
  });

  test("401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await POST(makeRequest({ workspaceId: WORKSPACE_ID, invitationId: INVITATION_ID }));
    expect(res.status).toBe(401);
    expect(mockRevoke).not.toHaveBeenCalled();
  });

  test("404 when the flag is disabled", async () => {
    mockIsTeamWorkspaceInviteEnabled.mockResolvedValue(false);
    const res = await POST(makeRequest({ workspaceId: WORKSPACE_ID, invitationId: INVITATION_ID }));
    expect(res.status).toBe(404);
    expect(mockRevoke).not.toHaveBeenCalled();
  });

  test("404 when team-membership page-data resolution fails", async () => {
    mockResolvePageData.mockResolvedValue({ ok: false, reason: "no-membership" });
    const res = await POST(makeRequest({ workspaceId: WORKSPACE_ID, invitationId: INVITATION_ID }));
    expect(res.status).toBe(404);
    expect(mockRevoke).not.toHaveBeenCalled();
  });

  test("400 when invitationId missing", async () => {
    const res = await POST(makeRequest({ workspaceId: WORKSPACE_ID }));
    expect(res.status).toBe(400);
    expect(mockRevoke).not.toHaveBeenCalled();
  });

  test("403 workspace_mismatch when body workspace != caller's workspace", async () => {
    const res = await POST(makeRequest({ workspaceId: "other-ws", invitationId: INVITATION_ID }));
    expect(res.status).toBe(403);
    expect(mockRevoke).not.toHaveBeenCalled();
  });

  test("403 not_owner when caller is a member, not owner", async () => {
    mockResolvePageData.mockResolvedValue({
      ok: true,
      data: {
        workspaceId: WORKSPACE_ID,
        organizationId: ORG_ID,
        currentUserId: OWNER_ID,
        members: [{ userId: OWNER_ID, role: "member" }],
      },
    });
    const res = await POST(makeRequest({ workspaceId: WORKSPACE_ID, invitationId: INVITATION_ID }));
    expect(res.status).toBe(403);
    expect(mockRevoke).not.toHaveBeenCalled();
  });

  test("404 when RPC reports invitation_not_found", async () => {
    mockRevoke.mockResolvedValue({ ok: false, reason: "invitation_not_found" });
    const res = await POST(makeRequest({ workspaceId: WORKSPACE_ID, invitationId: INVITATION_ID }));
    expect(res.status).toBe(404);
  });

  test("409 when RPC reports a terminal state (already_accepted)", async () => {
    mockRevoke.mockResolvedValue({ ok: false, reason: "already_accepted" });
    const res = await POST(makeRequest({ workspaceId: WORKSPACE_ID, invitationId: INVITATION_ID }));
    expect(res.status).toBe(409);
  });

  test("500 when RPC reports rpc_failed", async () => {
    mockRevoke.mockResolvedValue({ ok: false, reason: "rpc_failed" });
    const res = await POST(makeRequest({ workspaceId: WORKSPACE_ID, invitationId: INVITATION_ID }));
    expect(res.status).toBe(500);
  });
});
