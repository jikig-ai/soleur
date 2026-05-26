// Env vars BEFORE imports — the callback route's @supabase/ssr
// createServerClient throws at module-init unless these are set.
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "test-anon-key";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, test, expect, vi, beforeEach } from "vitest";
import { NextRequest } from "next/server";
import { TC_VERSION, TC_DOCUMENT_SHA } from "@/lib/legal/tc-version";

// Plan AC9 / Phase 8: end-to-end vitest covering the
// OAuth-callback → /accept-terms → POST /api/accept-terms flow with
// every Supabase dependency mocked. Cannot prove server-side atomicity
// (a Postgres transaction guarantee enforced inside SECURITY DEFINER
// SQL) — proves the route shape:
//
//   1. GET /(auth)/callback with NULL tc_accepted_version → redirect
//      to /accept-terms.
//   2. POST /api/accept-terms → calls public.accept_terms RPC exactly
//      once with (p_user_id, TC_VERSION, TC_DOCUMENT_SHA).
//
// Kieran P0-2: the assertion is "the route delegates to one RPC", not
// "the two writes are atomic". Atomicity is enforced by the SQL.

// ---------------------------------------------------------------------------
// Hoisted mocks
// ---------------------------------------------------------------------------

const {
  mockExchangeCodeForSession,
  mockGetUser,
  mockUserFromCallback,
  mockUserFromAcceptTerms,
  mockServiceFrom,
  mockServiceRpc,
  mockReportSilentFallback,
  mockValidateOrigin,
} = vi.hoisted(() => ({
  mockExchangeCodeForSession: vi.fn(),
  mockGetUser: vi.fn(),
  mockUserFromCallback: vi.fn(),
  mockUserFromAcceptTerms: vi.fn(),
  mockServiceFrom: vi.fn(),
  mockServiceRpc: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockValidateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: {
      getUser: mockGetUser,
      exchangeCodeForSession: mockExchangeCodeForSession,
    },
    from: (table: string) => {
      if (table === "api_keys") return mockUserFromCallback(table);
      return mockUserFromAcceptTerms(table);
    },
  })),
  createServiceClient: vi.fn(() => ({
    from: mockServiceFrom,
    rpc: mockServiceRpc,
  })),
}));

// The callback route uses @supabase/ssr directly (not via
// @/lib/supabase/server). Same mock surface, different module path.
vi.mock("@supabase/ssr", () => ({
  createServerClient: vi.fn(() => ({
    auth: {
      getUser: mockGetUser,
      exchangeCodeForSession: mockExchangeCodeForSession,
    },
    from: (table: string) => {
      if (table === "api_keys") return mockUserFromCallback(table);
      return mockUserFromAcceptTerms(table);
    },
  })),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

vi.mock("@sentry/nextjs", () => ({
  withIsolationScope: (fn: () => unknown) => fn(),
  getCurrentScope: () => ({ setUser: vi.fn() }),
  captureException: vi.fn(),
  captureMessage: vi.fn(),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: vi.fn(
    () => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  ),
}));

vi.mock("@/server/userid-pseudonymize", () => ({
  hashUserIdValue: (id: string) => `hash:${id}`,
}));

vi.mock("@/lib/auth/resolve-origin", () => ({
  resolveOrigin: () => "https://app.soleur.ai",
}));

// ---------------------------------------------------------------------------
// Import routes after mocks
// ---------------------------------------------------------------------------

import { GET as callbackGET } from "@/app/(auth)/callback/route";
import { POST as acceptTermsPOST } from "@/app/api/accept-terms/route";

const USER_ID = "user-uuid-e2e";

function makeCallbackRequest(code: string): NextRequest {
  return new NextRequest(
    new URL(`https://app.soleur.ai/callback?code=${encodeURIComponent(code)}`),
    {
      method: "GET",
      headers: {
        "x-forwarded-host": "app.soleur.ai",
        "x-forwarded-proto": "https",
        host: "app.soleur.ai",
      },
    },
  );
}

function makeAcceptTermsRequest(): Request {
  return new Request("https://app.soleur.ai/api/accept-terms", {
    method: "POST",
    headers: { origin: "https://app.soleur.ai" },
  });
}

/**
 * Wire mockServiceFrom("users") to a chain that produces a known
 * tc_accepted_version. The callback route's ensureWorkspaceProvisioned
 * helper does serviceClient.from("users").select(...).eq(...).single().
 */
function stubServiceUsersSelect(tcVersion: string | null): void {
  mockServiceFrom.mockImplementation((table: string) => {
    if (table !== "users") {
      return { select: vi.fn(), update: vi.fn(), upsert: vi.fn() };
    }
    const single = vi.fn().mockResolvedValue({
      data: { workspace_status: "ready", tc_accepted_version: tcVersion },
      error: null,
    });
    const eq = vi.fn().mockReturnValue({ single });
    const select = vi.fn().mockReturnValue({ eq });
    return { select, update: vi.fn(), upsert: vi.fn() };
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
  mockServiceRpc.mockResolvedValue({ data: null, error: null });
});

describe("E2E: OAuth → /accept-terms → RPC (AC9)", () => {
  test("GET /callback with null tc_accepted_version → redirects to /accept-terms", async () => {
    mockExchangeCodeForSession.mockResolvedValue({ data: null, error: null });
    mockGetUser.mockResolvedValue({
      data: { user: { id: USER_ID, email: "u@example.com" } },
    });
    stubServiceUsersSelect(null); // null tc_accepted_version → redirect to /accept-terms

    const res = await callbackGET(makeCallbackRequest("oauth-code-xyz"));

    expect([307, 308]).toContain(res.status);
    const loc = res.headers.get("location");
    expect(loc, "callback should redirect").not.toBeNull();
    expect(new URL(loc!).pathname).toBe("/accept-terms");
  });

  test("POST /api/accept-terms → calls accept_terms RPC exactly once with (p_user_id, TC_VERSION, TC_DOCUMENT_SHA)", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: USER_ID, email: "u@example.com" } },
    });

    // user-scoped client's api_keys SELECT for getRedirectDestination.
    const limit = vi.fn().mockResolvedValue({ data: [{ id: "k1" }], error: null });
    const eq3 = vi.fn().mockReturnValue({ limit });
    const eq2 = vi.fn().mockReturnValue({ eq: eq3 });
    const eq1 = vi.fn().mockReturnValue({ eq: eq2 });
    mockUserFromCallback.mockReturnValue({
      select: vi.fn().mockReturnValue({ eq: eq1 }),
    });

    const res = await acceptTermsPOST(makeAcceptTermsRequest());

    expect(res.status).toBe(200);
    expect(mockServiceRpc).toHaveBeenCalledTimes(1);
    expect(mockServiceRpc).toHaveBeenCalledWith("accept_terms", {
      p_user_id: USER_ID,
      p_version: TC_VERSION,
      p_doc_sha: TC_DOCUMENT_SHA,
    });

    // Atomicity guarantee lives in SECURITY DEFINER SQL — the route
    // contract is only "delegates to one RPC". Do not assert two
    // separate writes here (Kieran P0-2).
    const fromCalls = mockServiceFrom.mock.calls.map((c) => c[0]);
    expect(fromCalls).not.toContain("tc_acceptances");
  });

  test("full flow: callback redirect → accept-terms POST → RPC called once", async () => {
    // (1) callback: user has no consent yet → redirect to /accept-terms
    mockExchangeCodeForSession.mockResolvedValue({ data: null, error: null });
    mockGetUser.mockResolvedValue({
      data: { user: { id: USER_ID, email: "u@example.com" } },
    });
    stubServiceUsersSelect(null);

    const cbRes = await callbackGET(makeCallbackRequest("code-1"));
    expect(new URL(cbRes.headers.get("location")!).pathname).toBe("/accept-terms");

    // (2) user clicks "I agree" → POST /api/accept-terms
    const limit = vi.fn().mockResolvedValue({ data: [{ id: "k1" }], error: null });
    const eq3 = vi.fn().mockReturnValue({ limit });
    const eq2 = vi.fn().mockReturnValue({ eq: eq3 });
    const eq1 = vi.fn().mockReturnValue({ eq: eq2 });
    mockUserFromCallback.mockReturnValue({
      select: vi.fn().mockReturnValue({ eq: eq1 }),
    });

    const atRes = await acceptTermsPOST(makeAcceptTermsRequest());
    expect(atRes.status).toBe(200);
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
});
