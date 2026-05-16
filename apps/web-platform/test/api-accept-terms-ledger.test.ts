import { describe, test, expect, vi, beforeEach } from "vitest";

// Contract test for POST /api/accept-terms — verifies the route
// delegates ALL T&C consent writes to the public.accept_terms RPC.
//
// Plan AC4: the route handler does NOT early-return on already-current
// version; it always calls the RPC, which is a no-op for re-acceptance
// of the same version (Kieran P0-3). Idempotency lives in the SQL
// (`ON CONFLICT (user_id, version) DO NOTHING`) — see migration 044.
//
// This test cannot prove server-side atomicity (that's a Postgres
// transaction guarantee enforced inside the SECURITY DEFINER fn). It
// proves the route handler hands off a single RPC call with the
// correct argument shape — no direct .update("users") or .insert
// ("tc_acceptances") on the service client.

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted so factories see the mock fns
// ---------------------------------------------------------------------------

const {
  mockGetUser,
  mockUserFrom,
  mockServiceFrom,
  mockServiceRpc,
  mockReportSilentFallback,
  mockValidateOrigin,
  mockRejectCsrf,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockUserFrom: vi.fn(),
  mockServiceFrom: vi.fn(),
  mockServiceRpc: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockValidateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
  mockRejectCsrf: vi.fn(
    () => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  ),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockUserFrom,
  })),
  createServiceClient: vi.fn(() => ({
    from: mockServiceFrom,
    rpc: mockServiceRpc,
  })),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

vi.mock("@sentry/nextjs", () => ({
  withIsolationScope: (fn: () => unknown) => fn(),
  getCurrentScope: () => ({ setUser: vi.fn() }),
  captureException: vi.fn(),
  captureMessage: vi.fn(),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: mockRejectCsrf,
}));

vi.mock("@/server/userid-pseudonymize", () => ({
  hashUserIdValue: (id: string) => `hash:${id}`,
}));

// ---------------------------------------------------------------------------
// Import POST after mocks. TC_DOCUMENT_SHA + TC_VERSION come from
// @/lib/legal/tc-version — TC_DOCUMENT_SHA lands in Phase 3 of the plan.
// ---------------------------------------------------------------------------

import { POST } from "@/app/api/accept-terms/route";
import { TC_VERSION, TC_DOCUMENT_SHA } from "@/lib/legal/tc-version";

const USER_ID = "user-uuid-abc";

function makeRequest(): Request {
  return new Request("https://app.soleur.ai/api/accept-terms", {
    method: "POST",
    headers: { origin: "https://app.soleur.ai" },
  });
}

function setupAuthedUser(): void {
  mockGetUser.mockResolvedValue({
    data: { user: { id: USER_ID, email: "user@example.com" } },
  });
}

// Stub the user-scoped client's api_keys SELECT (for getRedirectDestination).
function setupApiKeysQuery(rows: Array<{ id: string }>): void {
  const limit = vi.fn().mockResolvedValue({ data: rows, error: null });
  const eq3 = vi.fn().mockReturnValue({ limit });
  const eq2 = vi.fn().mockReturnValue({ eq: eq3 });
  const eq1 = vi.fn().mockReturnValue({ eq: eq2 });
  const select = vi.fn().mockReturnValue({ eq: eq1 });
  mockUserFrom.mockReturnValue({ select });
}

describe("POST /api/accept-terms — RPC delegation contract", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Re-prime defaults after clearAllMocks wiped them.
    mockValidateOrigin.mockReturnValue({
      valid: true,
      origin: "https://app.soleur.ai",
    });
    mockRejectCsrf.mockReturnValue(
      new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
    );
    mockServiceRpc.mockResolvedValue({ data: null, error: null });
  });

  test("calls public.accept_terms RPC exactly once with (p_user_id, p_version, p_doc_sha)", async () => {
    setupAuthedUser();
    setupApiKeysQuery([{ id: "key-1" }]);

    const res = await POST(makeRequest());

    expect(res.status).toBe(200);
    expect(mockServiceRpc).toHaveBeenCalledTimes(1);
    expect(mockServiceRpc).toHaveBeenCalledWith(
      "accept_terms",
      expect.objectContaining({
        p_user_id: USER_ID,
        p_version: TC_VERSION,
        p_doc_sha: TC_DOCUMENT_SHA,
      }),
    );
  });

  test("does NOT write to users or tc_acceptances directly via service client", async () => {
    setupAuthedUser();
    setupApiKeysQuery([{ id: "key-1" }]);

    await POST(makeRequest());

    // The route may not call serviceClient.from at all (RPC-only path).
    // If it does, it must NOT target users or tc_acceptances.
    const fromCalls = mockServiceFrom.mock.calls.map((c) => c[0]);
    expect(
      fromCalls,
      `service client should not .from("users") or .from("tc_acceptances"); got ${JSON.stringify(fromCalls)}`,
    ).not.toContain("users");
    expect(fromCalls).not.toContain("tc_acceptances");
  });

  test("does NOT short-circuit on already-current version — RPC always called", async () => {
    // Even if the user's tc_accepted_version already equals TC_VERSION,
    // the route must call the RPC. The RPC handles the no-op
    // (ON CONFLICT DO NOTHING + same-value UPDATE). The old idempotency
    // SELECT must be gone (Kieran P0-3).
    setupAuthedUser();
    setupApiKeysQuery([{ id: "key-1" }]);

    // Simulate a service-client .from() that would return the existing
    // version if the route still SELECTed. With the new shape, no such
    // SELECT should happen, so even providing this mock is inert.
    mockServiceFrom.mockReturnValue({
      select: () => ({
        eq: () => ({
          single: () => Promise.resolve({
            data: { tc_accepted_version: TC_VERSION },
            error: null,
          }),
        }),
      }),
    });

    const res = await POST(makeRequest());

    expect(res.status).toBe(200);
    expect(mockServiceRpc).toHaveBeenCalledTimes(1);
    expect(mockServiceRpc).toHaveBeenCalledWith(
      "accept_terms",
      expect.objectContaining({
        p_user_id: USER_ID,
        p_version: TC_VERSION,
      }),
    );
  });

  test("surfaces RPC error to Sentry via reportSilentFallback and returns 500", async () => {
    setupAuthedUser();
    setupApiKeysQuery([]);
    mockServiceRpc.mockResolvedValue({
      data: null,
      error: { message: "db connection lost" },
    });

    const res = await POST(makeRequest());

    expect(res.status).toBe(500);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.objectContaining({ message: "db connection lost" }),
      expect.objectContaining({ feature: "accept-terms" }),
    );
  });

  test("returns 401 when getUser yields no user", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await POST(makeRequest());
    expect(res.status).toBe(401);
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  test("returns 403 when CSRF origin check fails", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: "https://evil" });
    const res = await POST(makeRequest());
    expect(res.status).toBe(403);
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });
});
