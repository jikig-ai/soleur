import { describe, test, expect, vi, beforeEach } from "vitest";

// Phase 3 (feat-byok-delegation-consent, #4625): POST /api/workspace/
// delegations/withdraw. Auth + CSRF + flag-gated. Sends ONLY the
// delegationId; the SECURITY DEFINER RPC withdraw_byok_delegation_consent
// derives the user from auth.uid() (NO p_user_id — SS-F3). The route must
// call the RPC on the USER-scoped client (so auth.uid() resolves), never
// the service client. AC13.

const {
  mockGetUser,
  mockUserRpc,
  mockServiceRpc,
  mockValidateOrigin,
  mockRejectCsrf,
  mockIsByokDelegationsEnabled,
  mockResolveCurrentOrganizationId,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockUserRpc: vi.fn(),
  mockServiceRpc: vi.fn(),
  mockValidateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
  mockRejectCsrf: vi.fn(() => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 })),
  mockIsByokDelegationsEnabled: vi.fn(async () => true),
  mockResolveCurrentOrganizationId: vi.fn(async () => "org-1"),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({ auth: { getUser: mockGetUser }, rpc: mockUserRpc })),
  createServiceClient: vi.fn(() => ({ rpc: mockServiceRpc })),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: mockRejectCsrf,
}));

vi.mock("@/lib/feature-flags/server", () => ({
  isByokDelegationsEnabled: mockIsByokDelegationsEnabled,
}));

vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentOrganizationId: mockResolveCurrentOrganizationId,
}));

import { POST } from "@/app/api/workspace/delegations/withdraw/route";

const USER_ID = "grantee-uuid";
const DELEGATION_ID = "delegation-uuid";

function makeRequest(body: Record<string, unknown>): Request {
  return new Request("https://app.soleur.ai/api/workspace/delegations/withdraw", {
    method: "POST",
    headers: { origin: "https://app.soleur.ai", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
  mockRejectCsrf.mockReturnValue(new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }));
  mockIsByokDelegationsEnabled.mockResolvedValue(true);
  mockResolveCurrentOrganizationId.mockResolvedValue("org-1");
  mockGetUser.mockResolvedValue({ data: { user: { id: USER_ID, email: "g@example.com" } } });
  mockUserRpc.mockResolvedValue({ data: null, error: null });
});

describe("POST /api/workspace/delegations/withdraw (AC13)", () => {
  test("calls withdraw_byok_delegation_consent with ONLY p_delegation_id, on the user client", async () => {
    const res = await POST(makeRequest({ delegationId: DELEGATION_ID }));
    expect(res.status).toBe(200);
    expect(mockUserRpc).toHaveBeenCalledTimes(1);
    expect(mockUserRpc).toHaveBeenCalledWith(
      "withdraw_byok_delegation_consent",
      { p_delegation_id: DELEGATION_ID },
    );
    // Must NOT route through the service client (would lose auth.uid()).
    expect(mockServiceRpc).not.toHaveBeenCalled();
    // Must NOT pass any p_user_id (SS-F3).
    const arg = mockUserRpc.mock.calls[0][1] as Record<string, unknown>;
    expect(arg).not.toHaveProperty("p_user_id");
  });

  test("401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await POST(makeRequest({ delegationId: DELEGATION_ID }));
    expect(res.status).toBe(401);
    expect(mockUserRpc).not.toHaveBeenCalled();
  });

  test("404 when the flag is disabled", async () => {
    mockIsByokDelegationsEnabled.mockResolvedValue(false);
    const res = await POST(makeRequest({ delegationId: DELEGATION_ID }));
    expect(res.status).toBe(404);
  });

  test("400 when delegationId missing", async () => {
    const res = await POST(makeRequest({}));
    expect(res.status).toBe(400);
    expect(mockUserRpc).not.toHaveBeenCalled();
  });

  test("403 (CSRF) when origin invalid", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: "https://evil.example" });
    const res = await POST(makeRequest({ delegationId: DELEGATION_ID }));
    expect(res.status).toBe(403);
  });

  test("404 not_grantee when RPC raises P0002 (grantee-only check)", async () => {
    mockUserRpc.mockResolvedValue({
      data: null,
      error: { code: "P0002", message: "delegation not found for caller (grantee-only)" },
    });
    const res = await POST(makeRequest({ delegationId: DELEGATION_ID }));
    expect(res.status).toBe(404);
  });
});
