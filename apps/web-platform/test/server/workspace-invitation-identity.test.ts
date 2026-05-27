import { describe, it, expect, vi, beforeEach } from "vitest";

const {
  mockGetUser,
  mockServiceFrom,
  mockServiceRpc,
  mockValidateOrigin,
  mockAcceptInvitation,
  mockDeclineInvitation,
  mockSendEmail,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockServiceFrom: vi.fn(),
  mockServiceRpc: vi.fn(),
  mockValidateOrigin: vi.fn(),
  mockAcceptInvitation: vi.fn(),
  mockDeclineInvitation: vi.fn(),
  mockSendEmail: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(() => ({
    auth: { getUser: mockGetUser },
  })),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({
    from: mockServiceFrom,
    rpc: mockServiceRpc,
  })),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: vi.fn(),
}));

vi.mock("@/server/workspace-invitations", () => ({
  acceptWorkspaceInvitation: mockAcceptInvitation,
  declineWorkspaceInvitation: mockDeclineInvitation,
}));

vi.mock("@/server/notifications", () => ({
  sendInviteAcceptedEmail: mockSendEmail,
}));

function makeRequest(body: Record<string, unknown>): Request {
  return new Request("http://localhost:3000/api/workspace/accept-invite", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

function chainableMock(data: unknown) {
  const chain: Record<string, unknown> = {};
  const methods = ["select", "eq", "neq", "in", "is", "gt", "gte", "lt", "lte", "order", "limit"];
  for (const m of methods) {
    chain[m] = vi.fn(() => chain);
  }
  chain.single = vi.fn(() => ({
    then: (fn?: (v: unknown) => unknown) =>
      Promise.resolve({ data, error: null }).then(fn),
  }));
  chain.then = (fn?: (v: unknown) => unknown) =>
    Promise.resolve({ data, error: null }).then(fn);
  return chain;
}

const INVITATION_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const INVITEE_USER_ID = "11111111-2222-3333-4444-555555555555";
const INVITEE_EMAIL = "alice@example.com";
const ATTACKER_USER_ID = "99999999-8888-7777-6666-555555555555";
const ATTACKER_EMAIL = "mallory@evil.com";

const INVITATION_ROW = {
  inviter_user_id: "00000000-0000-0000-0000-000000000001",
  invitee_user_id: INVITEE_USER_ID,
  invitee_email: INVITEE_EMAIL,
  workspace_id: "ws-001",
  workspaces: [{ name: "Team Alpha" }],
};

const INVITATION_ROW_EMAIL_ONLY = {
  ...INVITATION_ROW,
  invitee_user_id: null,
};

beforeEach(() => {
  vi.clearAllMocks();
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "http://localhost:3000" });
  mockSendEmail.mockResolvedValue(undefined);
});

describe("accept-invite identity check", () => {
  let acceptPOST: (req: Request) => Promise<Response>;

  beforeEach(async () => {
    const mod = await import(
      "@/app/api/workspace/accept-invite/route"
    );
    acceptPOST = mod.POST;
  });

  it("returns 403 when authenticated user does not match invitee_user_id", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: ATTACKER_USER_ID, email: ATTACKER_EMAIL } },
    });
    mockServiceFrom.mockReturnValue(chainableMock(INVITATION_ROW));
    mockAcceptInvitation.mockResolvedValue({ ok: true, workspaceId: "ws-001", attestationId: "att-1" });

    const res = await acceptPOST(makeRequest({ invitationId: INVITATION_ID }));
    expect(res.status).toBe(403);

    const body = await res.json();
    expect(body.error).toBe("not_intended_invitee");
  });

  it("returns 403 when authenticated user email does not match invitee_email (invitee_user_id null)", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: ATTACKER_USER_ID, email: ATTACKER_EMAIL } },
    });
    mockServiceFrom.mockReturnValue(chainableMock(INVITATION_ROW_EMAIL_ONLY));
    mockAcceptInvitation.mockResolvedValue({ ok: true, workspaceId: "ws-001", attestationId: "att-1" });

    const res = await acceptPOST(makeRequest({ invitationId: INVITATION_ID }));
    expect(res.status).toBe(403);

    const body = await res.json();
    expect(body.error).toBe("not_intended_invitee");
  });

  it("proceeds to RPC when authenticated user matches invitee_user_id", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: INVITEE_USER_ID, email: INVITEE_EMAIL } },
    });
    mockServiceFrom.mockReturnValue(chainableMock(INVITATION_ROW));
    mockAcceptInvitation.mockResolvedValue({ ok: true, workspaceId: "ws-001", attestationId: "att-1" });
    mockSendEmail.mockResolvedValue(undefined);

    const res = await acceptPOST(makeRequest({ invitationId: INVITATION_ID }));
    expect(res.status).toBe(200);
    expect(mockAcceptInvitation).toHaveBeenCalledWith(INVITATION_ID, INVITEE_USER_ID);
  });

  it("proceeds to RPC when authenticated user email matches invitee_email (case-insensitive)", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: "different-id", email: "Alice@Example.COM" } },
    });
    mockServiceFrom.mockReturnValue(chainableMock(INVITATION_ROW_EMAIL_ONLY));
    mockAcceptInvitation.mockResolvedValue({ ok: true, workspaceId: "ws-001", attestationId: "att-1" });
    mockSendEmail.mockResolvedValue(undefined);

    const res = await acceptPOST(makeRequest({ invitationId: INVITATION_ID }));
    expect(res.status).toBe(200);
    expect(mockAcceptInvitation).toHaveBeenCalled();
  });

  it("returns RPC error status when not_intended_invitee comes from RPC (403)", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: INVITEE_USER_ID, email: INVITEE_EMAIL } },
    });
    mockServiceFrom.mockReturnValue(chainableMock(INVITATION_ROW));
    mockAcceptInvitation.mockResolvedValue({ ok: false, reason: "not_intended_invitee" });

    const res = await acceptPOST(makeRequest({ invitationId: INVITATION_ID }));
    expect(res.status).toBe(403);
  });
});

describe("decline-invite identity check", () => {
  let declinePOST: (req: Request) => Promise<Response>;

  beforeEach(async () => {
    const mod = await import(
      "@/app/api/workspace/decline-invite/route"
    );
    declinePOST = mod.POST;
  });

  it("returns 403 when authenticated user does not match invitee_user_id", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: ATTACKER_USER_ID, email: ATTACKER_EMAIL } },
    });
    mockServiceFrom.mockReturnValue(chainableMock(INVITATION_ROW));
    mockDeclineInvitation.mockResolvedValue({ ok: true });

    const res = await declinePOST(makeRequest({ invitationId: INVITATION_ID }));
    expect(res.status).toBe(403);

    const body = await res.json();
    expect(body.error).toBe("not_intended_invitee");
  });

  it("proceeds to RPC when authenticated user matches invitee_user_id", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: INVITEE_USER_ID, email: INVITEE_EMAIL } },
    });
    mockServiceFrom.mockReturnValue(chainableMock(INVITATION_ROW));
    mockDeclineInvitation.mockResolvedValue({ ok: true });

    const res = await declinePOST(makeRequest({ invitationId: INVITATION_ID }));
    expect(res.status).toBe(200);
    expect(mockDeclineInvitation).toHaveBeenCalledWith(INVITATION_ID, INVITEE_USER_ID);
  });
});
