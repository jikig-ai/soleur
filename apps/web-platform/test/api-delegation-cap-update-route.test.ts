import { describe, test, expect, vi, beforeEach } from "vitest";

// PATCH /api/workspace/delegations updates a BYOK delegation's daily/hourly cap
// in place via the SECURITY DEFINER RPC update_byok_delegation_cap (migration
// 094) — the WORM Shape-3 cap-update flip (064:332-353). Before this, the owner
// could only set a cap at grant time; changing it required revoke + re-grant
// (resetting spend accounting). PostgREST resolves rpc() by argument NAME — the
// 4-key arg object MUST match the function signature exactly or resolution
// fails (PGRST202 → 400). This test pins the canonical arg object + the
// ownership-probe + flag/auth/CSRF gates (#4779-followup).

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

vi.mock("@/server/byok-delegation-ui-resolver", () => ({
  resolveGrantorDelegations: vi.fn(async () => []),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { PATCH } from "@/app/api/workspace/delegations/route";

const OWNER_ID = "owner-uuid";
const GRANTEE_ID = "grantee-uuid";
const DELEGATION_ID = "delegation-uuid";

function makeRequest(body: Record<string, unknown>): Request {
  return new Request("https://app.soleur.ai/api/workspace/delegations", {
    method: "PATCH",
    headers: { origin: "https://app.soleur.ai", "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

function validBody(overrides: Record<string, unknown> = {}) {
  return { delegationId: DELEGATION_ID, dailyCapCents: 5000, ...overrides };
}

beforeEach(() => {
  vi.clearAllMocks();
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
  mockRejectCsrf.mockReturnValue(new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }));
  mockIsByokDelegationsEnabled.mockResolvedValue(true);
  mockResolveCurrentOrganizationId.mockResolvedValue("org-1");
  mockGetUser.mockResolvedValue({ data: { user: { id: OWNER_ID, email: "owner@example.com" } } });
  // Caller is the grantor + creator, not revoked → passes the ownership probe.
  mockDelegationMaybeSingle.mockResolvedValue({
    data: { grantor_user_id: OWNER_ID, created_by_user_id: OWNER_ID, revoked_at: null },
    error: null,
  });
  mockServiceRpc.mockResolvedValue({ error: null });
});

describe("PATCH /api/workspace/delegations (cap update)", () => {
  test("calls update_byok_delegation_cap with the exact 4-key canonical arg object", async () => {
    const res = await PATCH(makeRequest(validBody()));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    expect(mockServiceRpc).toHaveBeenCalledTimes(1);
    expect(mockServiceRpc).toHaveBeenCalledWith("update_byok_delegation_cap", {
      p_delegation_id: DELEGATION_ID,
      p_daily_usd_cap_cents: 5000,
      // null → the RPC PRESERVES the existing hourly cap (clamped to new daily);
      // the UI exposes only a daily stepper and must not silently raise hourly.
      p_hourly_usd_cap_cents: null,
      p_actor_user_id: OWNER_ID,
    });
  });

  test("forwards an explicit hourly cap when provided", async () => {
    await PATCH(makeRequest(validBody({ hourlyCapCents: 1000 })));
    expect(mockServiceRpc).toHaveBeenCalledWith(
      "update_byok_delegation_cap",
      expect.objectContaining({ p_hourly_usd_cap_cents: 1000, p_daily_usd_cap_cents: 5000 }),
    );
  });

  test("400 missing_fields when delegationId absent", async () => {
    const res = await PATCH(makeRequest({ dailyCapCents: 5000 }));
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "missing_fields" });
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("400 missing_fields when dailyCapCents absent", async () => {
    const res = await PATCH(makeRequest({ delegationId: DELEGATION_ID }));
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "missing_fields" });
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("403 forbidden when caller is neither grantor nor creator", async () => {
    mockDelegationMaybeSingle.mockResolvedValue({
      data: { grantor_user_id: "someone-else", created_by_user_id: "someone-else", revoked_at: null },
      error: null,
    });
    const res = await PATCH(makeRequest(validBody()));
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: "forbidden" });
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("403 forbidden when the delegation does not exist", async () => {
    mockDelegationMaybeSingle.mockResolvedValue({ data: null, error: null });
    const res = await PATCH(makeRequest(validBody()));
    expect(res.status).toBe(403);
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("503 when the ownership probe errors transiently (not a misleading 403)", async () => {
    mockDelegationMaybeSingle.mockResolvedValue({ data: null, error: { message: "timeout" } });
    const res = await PATCH(makeRequest(validBody()));
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ error: "probe_failed" });
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("400 with the RPC error message when the cap-update RPC fails (e.g. already revoked)", async () => {
    mockServiceRpc.mockResolvedValue({
      error: { message: "update_byok_delegation_cap: delegation already revoked" },
    });
    const res = await PATCH(makeRequest(validBody()));
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({
      error: "update_byok_delegation_cap: delegation already revoked",
    });
  });

  test("401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await PATCH(makeRequest(validBody()));
    expect(res.status).toBe(401);
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("404 when the flag is disabled", async () => {
    mockIsByokDelegationsEnabled.mockResolvedValue(false);
    const res = await PATCH(makeRequest(validBody()));
    expect(res.status).toBe(404);
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("403 (CSRF) when origin invalid", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: "https://evil.example" });
    const res = await PATCH(makeRequest(validBody()));
    expect(res.status).toBe(403);
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });
});
