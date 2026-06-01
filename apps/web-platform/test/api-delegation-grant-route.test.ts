import { describe, test, expect, vi, beforeEach } from "vitest";

// fix (feat-one-shot-share-a-key-toggle-not-enabling): POST /api/workspace/
// delegations creates a BYOK delegation by calling the SECURITY DEFINER RPC
// grant_byok_delegation on the SERVICE-ROLE client. The route shipped (PR
// #4508) with named args that do not match migration 064's signature
// (p_daily_cap_cents / p_hourly_cap_cents / p_created_by_user_id, and
// p_expires_at omitted), so PostgREST fails function resolution → 400 → the
// "Share a key" toggle silently reverts. This test pins the exact 7-key
// canonical arg object (mirrors byok-grant.ts:173-180) so the regression
// cannot reappear. AC4.

const {
  mockGetUser,
  mockServiceRpc,
  mockMembershipMaybeSingle,
  mockValidateOrigin,
  mockRejectCsrf,
  mockIsByokDelegationsEnabled,
  mockResolveCurrentOrganizationId,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockServiceRpc: vi.fn(),
  mockMembershipMaybeSingle: vi.fn(),
  mockValidateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
  mockRejectCsrf: vi.fn(() => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 })),
  mockIsByokDelegationsEnabled: vi.fn(async () => true),
  mockResolveCurrentOrganizationId: vi.fn(async () => "org-1"),
}));

// Service client exposes both .from(...) (the workspace_members owner check)
// and .rpc(...) (grant_byok_delegation). The membership chain is recursive
// (.select/.eq return the chain) and terminates at .maybeSingle().
const membershipChain = {
  select: vi.fn(() => membershipChain),
  eq: vi.fn(() => membershipChain),
  maybeSingle: mockMembershipMaybeSingle,
};

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({ auth: { getUser: mockGetUser } })),
  createServiceClient: vi.fn(() => ({
    from: vi.fn(() => membershipChain),
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

import { POST } from "@/app/api/workspace/delegations/route";

const OWNER_ID = "owner-uuid";
const GRANTEE_ID = "grantee-uuid";
const WORKSPACE_ID = "workspace-uuid";
const DAILY_CAP = 2000;

function makeRequest(body: Record<string, unknown>): Request {
  return new Request("https://app.soleur.ai/api/workspace/delegations", {
    method: "POST",
    headers: { origin: "https://app.soleur.ai", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function validBody(overrides: Record<string, unknown> = {}) {
  return { workspaceId: WORKSPACE_ID, granteeUserId: GRANTEE_ID, dailyCapCents: DAILY_CAP, ...overrides };
}

beforeEach(() => {
  vi.clearAllMocks();
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
  mockRejectCsrf.mockReturnValue(new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }));
  mockIsByokDelegationsEnabled.mockResolvedValue(true);
  mockResolveCurrentOrganizationId.mockResolvedValue("org-1");
  mockGetUser.mockResolvedValue({ data: { user: { id: OWNER_ID, email: "owner@example.com" } } });
  mockMembershipMaybeSingle.mockResolvedValue({ data: { role: "owner" } });
  mockServiceRpc.mockResolvedValue({ data: "delegation-uuid", error: null });
});

describe("POST /api/workspace/delegations (grant — AC1/AC2/AC3/AC4)", () => {
  test("calls grant_byok_delegation with the exact 7-key canonical arg object", async () => {
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ delegationId: "delegation-uuid" });
    expect(mockServiceRpc).toHaveBeenCalledTimes(1);
    expect(mockServiceRpc).toHaveBeenCalledWith("grant_byok_delegation", {
      p_grantor_user_id: OWNER_ID,
      p_grantee_user_id: GRANTEE_ID,
      p_workspace_id: WORKSPACE_ID,
      p_daily_usd_cap_cents: DAILY_CAP,
      p_hourly_usd_cap_cents: DAILY_CAP, // AC2: defaults to daily when client omits hourly
      p_expires_at: null, // AC3: UI-created delegations never expire
      p_actor_user_id: OWNER_ID,
    });
    // Guard against the broken legacy names reappearing.
    const arg = mockServiceRpc.mock.calls[0][1] as Record<string, unknown>;
    expect(arg).not.toHaveProperty("p_daily_cap_cents");
    expect(arg).not.toHaveProperty("p_hourly_cap_cents");
    expect(arg).not.toHaveProperty("p_created_by_user_id");
  });

  test("honours an explicit hourlyCapCents when the client supplies one (AC2)", async () => {
    await POST(makeRequest(validBody({ hourlyCapCents: 500 })));
    expect(mockServiceRpc).toHaveBeenCalledWith(
      "grant_byok_delegation",
      expect.objectContaining({ p_hourly_usd_cap_cents: 500, p_daily_usd_cap_cents: DAILY_CAP }),
    );
  });

  test("403 not_owner when the caller is not the workspace owner", async () => {
    mockMembershipMaybeSingle.mockResolvedValue({ data: { role: "member" } });
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: "not_owner" });
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("403 not_owner when the caller is not a member at all", async () => {
    mockMembershipMaybeSingle.mockResolvedValue({ data: null });
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: "not_owner" });
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("400 missing_fields when a required field is absent", async () => {
    const res = await POST(makeRequest({ workspaceId: WORKSPACE_ID, granteeUserId: GRANTEE_ID }));
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "missing_fields" });
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("400 missing_fields when dailyCapCents is 0 (falsy guard, never reaches the RPC)", async () => {
    const res = await POST(makeRequest(validBody({ dailyCapCents: 0 })));
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "missing_fields" });
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(401);
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("404 when the flag is disabled", async () => {
    mockIsByokDelegationsEnabled.mockResolvedValue(false);
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(404);
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("403 (CSRF) when origin invalid", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: "https://evil.example" });
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(403);
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("400 with the RPC error message when the grant RPC fails", async () => {
    mockServiceRpc.mockResolvedValue({
      data: null,
      error: { message: "grant_byok_delegation: hourly_usd_cap_cents out of range" },
    });
    const res = await POST(makeRequest(validBody()));
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({
      error: "grant_byok_delegation: hourly_usd_cap_cents out of range",
    });
  });
});
