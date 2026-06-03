import { describe, test, expect, vi, beforeEach } from "vitest";

// POST /api/workspace/rename (feat-one-shot-workspace-untitled-name).
// Mirrors transfer-ownership's auth chain: CSRF → auth → page-data resolve →
// flag gate → org-match → owner-check → renameOrganization. Owner-only
// (single-user-incident threshold): non-owner and cross-org callers are
// rejected before the RPC runs; RPC failure reasons map to 400/403/404/500.

const {
  mockGetUser,
  mockValidateOrigin,
  mockRejectCsrf,
  mockResolvePageData,
  mockIsTeamWorkspaceInviteEnabled,
  mockRename,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockValidateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
  mockRejectCsrf: vi.fn(() => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 })),
  mockResolvePageData: vi.fn(),
  mockIsTeamWorkspaceInviteEnabled: vi.fn(async () => true),
  mockRename: vi.fn(),
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

vi.mock("@/server/workspace-membership", () => ({
  renameOrganization: mockRename,
}));

import { POST } from "@/app/api/workspace/rename/route";

const OWNER_ID = "owner-uuid";
const WORKSPACE_ID = "ws-uuid";
const ORG_ID = "org-uuid";

function makeRequest(body: Record<string, unknown>): Request {
  return new Request("https://app.soleur.ai/api/workspace/rename", {
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
      organizationName: "My Workspace",
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
  mockRename.mockResolvedValue({ ok: true });
});

describe("POST /api/workspace/rename", () => {
  test("200 happy path — owner renames; RPC called with org, name, caller", async () => {
    const res = await POST(makeRequest({ organizationId: ORG_ID, name: "Acme Studio" }));
    expect(res.status).toBe(200);
    expect(mockRename).toHaveBeenCalledWith({
      organizationId: ORG_ID,
      name: "Acme Studio",
      callerUserId: OWNER_ID,
    });
  });

  test("403 (CSRF) when origin invalid", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: "https://evil.example" });
    const res = await POST(makeRequest({ organizationId: ORG_ID, name: "Acme" }));
    expect(res.status).toBe(403);
    expect(mockRename).not.toHaveBeenCalled();
  });

  test("401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await POST(makeRequest({ organizationId: ORG_ID, name: "Acme" }));
    expect(res.status).toBe(401);
    expect(mockRename).not.toHaveBeenCalled();
  });

  test("404 when the flag is disabled", async () => {
    mockIsTeamWorkspaceInviteEnabled.mockResolvedValue(false);
    const res = await POST(makeRequest({ organizationId: ORG_ID, name: "Acme" }));
    expect(res.status).toBe(404);
    expect(mockRename).not.toHaveBeenCalled();
  });

  test("404 when page-data resolution fails", async () => {
    mockResolvePageData.mockResolvedValue({ ok: false, reason: "no-membership" });
    const res = await POST(makeRequest({ organizationId: ORG_ID, name: "Acme" }));
    expect(res.status).toBe(404);
    expect(mockRename).not.toHaveBeenCalled();
  });

  test("400 when name missing", async () => {
    const res = await POST(makeRequest({ organizationId: ORG_ID }));
    expect(res.status).toBe(400);
    expect(mockRename).not.toHaveBeenCalled();
  });

  test("400 when name is whitespace-only", async () => {
    const res = await POST(makeRequest({ organizationId: ORG_ID, name: "   " }));
    expect(res.status).toBe(400);
    expect(mockRename).not.toHaveBeenCalled();
  });

  test("400 when name exceeds 60 chars", async () => {
    const res = await POST(makeRequest({ organizationId: ORG_ID, name: "x".repeat(61) }));
    expect(res.status).toBe(400);
    expect(mockRename).not.toHaveBeenCalled();
  });

  test("403 org_mismatch when body org != caller's org", async () => {
    const res = await POST(makeRequest({ organizationId: "other-org", name: "Acme" }));
    expect(res.status).toBe(403);
    expect(mockRename).not.toHaveBeenCalled();
  });

  test("403 not_owner when caller is a member, not owner", async () => {
    mockResolvePageData.mockResolvedValue({
      ok: true,
      data: {
        workspaceId: WORKSPACE_ID,
        organizationId: ORG_ID,
        organizationName: "My Workspace",
        currentUserId: OWNER_ID,
        members: [{ userId: OWNER_ID, role: "member" }],
      },
    });
    const res = await POST(makeRequest({ organizationId: ORG_ID, name: "Acme" }));
    expect(res.status).toBe(403);
    expect(mockRename).not.toHaveBeenCalled();
  });

  test("403 when RPC reports caller_not_owner", async () => {
    mockRename.mockResolvedValue({ ok: false, reason: "caller_not_owner" });
    const res = await POST(makeRequest({ organizationId: ORG_ID, name: "Acme" }));
    expect(res.status).toBe(403);
  });

  test("400 when RPC reports invalid_name", async () => {
    mockRename.mockResolvedValue({ ok: false, reason: "invalid_name" });
    const res = await POST(makeRequest({ organizationId: ORG_ID, name: "Acme" }));
    expect(res.status).toBe(400);
  });

  test("404 when RPC reports not_found", async () => {
    mockRename.mockResolvedValue({ ok: false, reason: "not_found" });
    const res = await POST(makeRequest({ organizationId: ORG_ID, name: "Acme" }));
    expect(res.status).toBe(404);
  });

  test("500 when RPC reports rpc_failed", async () => {
    mockRename.mockResolvedValue({ ok: false, reason: "rpc_failed" });
    const res = await POST(makeRequest({ organizationId: ORG_ID, name: "Acme" }));
    expect(res.status).toBe(500);
  });

  test("name is trimmed before forwarding to the RPC wrapper", async () => {
    await POST(makeRequest({ organizationId: ORG_ID, name: "  Acme Studio  " }));
    expect(mockRename).toHaveBeenCalledWith({
      organizationId: ORG_ID,
      name: "Acme Studio",
      callerUserId: OWNER_ID,
    });
  });
});
