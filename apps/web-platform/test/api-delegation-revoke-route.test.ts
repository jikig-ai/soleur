import { describe, test, expect, vi, beforeEach } from "vitest";

// fix (feat-one-shot-key-delegation-state-persistence): DELETE /api/workspace/
// delegations revokes a BYOK delegation by calling the SECURITY DEFINER RPC
// revoke_byok_delegation on the SERVICE-ROLE client. The route shipped with
// named args that do NOT match migration 064's signature
// (064:495-498 → p_delegation_id / p_actor_user_id / p_reason); it sent the
// legacy p_revoked_by_user_id / p_revocation_reason instead, so PostgREST
// fails function resolution (PGRST202) → 400 → the "Share a key" toggle can
// never be turned OFF (it snaps back on). This is the identical defect class
// #4761 fixed for the GRANT path, left unfixed on revoke. This test pins the
// exact 3-key canonical arg object (mirrors scripts/byok-revoke.ts:154-158)
// so the regression cannot reappear. AC1 + AC2.

const {
  mockGetUser,
  mockServiceRpc,
  mockDelegationMaybeSingle,
  mockValidateOrigin,
  mockRejectCsrf,
  mockIsByokDelegationsEnabled,
  mockResolveCurrentOrganizationId,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockServiceRpc: vi.fn(),
  mockDelegationMaybeSingle: vi.fn(),
  mockValidateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
  mockRejectCsrf: vi.fn(() => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 })),
  mockIsByokDelegationsEnabled: vi.fn(async () => true),
  mockResolveCurrentOrganizationId: vi.fn(async () => "org-1"),
}));

// Service client exposes both .from(...) (the byok_delegations ownership probe)
// and .rpc(...) (revoke_byok_delegation). The probe chain is recursive
// (.select/.eq return the chain) and terminates at .maybeSingle().
const delegationChain = {
  select: vi.fn(() => delegationChain),
  eq: vi.fn(() => delegationChain),
  maybeSingle: mockDelegationMaybeSingle,
};

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({ auth: { getUser: mockGetUser } })),
  createServiceClient: vi.fn(() => ({
    from: vi.fn(() => delegationChain),
    rpc: mockServiceRpc,
  })),
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

// byok-delegation-ui-resolver is imported by the route module (GET path);
// stub it so the module loads without a real DB client.
vi.mock("@/server/byok-delegation-ui-resolver", () => ({
  resolveGrantorDelegations: vi.fn(async () => []),
}));

import { DELETE } from "@/app/api/workspace/delegations/route";

const OWNER_ID = "owner-uuid";
const GRANTEE_ID = "grantee-uuid";
const DELEGATION_ID = "delegation-uuid";

function makeRequest(body: Record<string, unknown>): Request {
  return new Request("https://app.soleur.ai/api/workspace/delegations", {
    method: "DELETE",
    headers: { origin: "https://app.soleur.ai", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function validBody(overrides: Record<string, unknown> = {}) {
  return { delegationId: DELEGATION_ID, reason: "grantor_revoke", ...overrides };
}

beforeEach(() => {
  vi.clearAllMocks();
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
  mockRejectCsrf.mockReturnValue(new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }));
  mockIsByokDelegationsEnabled.mockResolvedValue(true);
  mockResolveCurrentOrganizationId.mockResolvedValue("org-1");
  mockGetUser.mockResolvedValue({ data: { user: { id: OWNER_ID, email: "owner@example.com" } } });
  // The grantor owns this delegation → passes the ownership probe.
  mockDelegationMaybeSingle.mockResolvedValue({
    data: { grantor_user_id: OWNER_ID, grantee_user_id: GRANTEE_ID },
  });
  mockServiceRpc.mockResolvedValue({ error: null });
});

describe("DELETE /api/workspace/delegations (revoke — AC1/AC2)", () => {
  test("calls revoke_byok_delegation with the exact 3-key canonical arg object", async () => {
    const res = await DELETE(makeRequest(validBody()));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expect(mockServiceRpc).toHaveBeenCalledTimes(1);
    expect(mockServiceRpc).toHaveBeenCalledWith("revoke_byok_delegation", {
      p_delegation_id: DELEGATION_ID,
      p_actor_user_id: OWNER_ID,
      p_reason: "grantor_revoke",
    });
    // Guard against the broken legacy names reappearing (064:495-498 vs route).
    const arg = mockServiceRpc.mock.calls[0][1] as Record<string, unknown>;
    expect(arg).not.toHaveProperty("p_revoked_by_user_id");
    expect(arg).not.toHaveProperty("p_revocation_reason");
  });

  test("defaults p_reason to grantor_revoke when the client omits reason", async () => {
    await DELETE(makeRequest({ delegationId: DELEGATION_ID }));
    expect(mockServiceRpc).toHaveBeenCalledWith(
      "revoke_byok_delegation",
      expect.objectContaining({ p_reason: "grantor_revoke", p_actor_user_id: OWNER_ID }),
    );
  });

  test("forwards a grantee_decline reason verbatim", async () => {
    await DELETE(makeRequest(validBody({ reason: "grantee_decline" })));
    expect(mockServiceRpc).toHaveBeenCalledWith(
      "revoke_byok_delegation",
      expect.objectContaining({ p_reason: "grantee_decline" }),
    );
  });

  test("400 missing_delegation_id when delegationId absent", async () => {
    const res = await DELETE(makeRequest({ reason: "grantor_revoke" }));
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "missing_delegation_id" });
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("400 invalid_reason for a reserved/trigger-only reason", async () => {
    const res = await DELETE(makeRequest(validBody({ reason: "admin_revoke" })));
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "invalid_reason" });
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("403 forbidden when caller is neither grantor nor grantee", async () => {
    mockDelegationMaybeSingle.mockResolvedValue({
      data: { grantor_user_id: "someone-else", grantee_user_id: "another-user" },
    });
    const res = await DELETE(makeRequest(validBody()));
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: "forbidden" });
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("403 forbidden when the delegation does not exist", async () => {
    mockDelegationMaybeSingle.mockResolvedValue({ data: null });
    const res = await DELETE(makeRequest(validBody()));
    expect(res.status).toBe(403);
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await DELETE(makeRequest(validBody()));
    expect(res.status).toBe(401);
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("404 when the flag is disabled", async () => {
    mockIsByokDelegationsEnabled.mockResolvedValue(false);
    const res = await DELETE(makeRequest(validBody()));
    expect(res.status).toBe(404);
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("403 (CSRF) when origin invalid", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: "https://evil.example" });
    const res = await DELETE(makeRequest(validBody()));
    expect(res.status).toBe(403);
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("400 with the RPC error message when the revoke RPC fails", async () => {
    mockServiceRpc.mockResolvedValue({
      error: { message: "revoke_byok_delegation: delegation not found" },
    });
    const res = await DELETE(makeRequest(validBody()));
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({
      error: "revoke_byok_delegation: delegation not found",
    });
  });
});
