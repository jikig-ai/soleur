process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "test-anon-key";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, test, expect, vi, beforeEach } from "vitest";

// Phase 4b: POST /api/accept-terms honors a validated `redirectTo` as the
// terminal hop AFTER recording T&C, but only once a key exists (no key →
// /setup-key takes precedence). The redirect is re-validated server-side via
// safeReturnTo, so an open-redirect value falls back to /dashboard.

const { mockGetUser, mockServiceRpc, mockApiKeysLimit } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockServiceRpc: vi.fn(),
  mockApiKeysLimit: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: () => ({
      select: () => ({
        eq: () => ({ eq: () => ({ eq: () => ({ limit: mockApiKeysLimit }) }) }),
      }),
    }),
  })),
  createServiceClient: vi.fn(() => ({ rpc: mockServiceRpc })),
}));

vi.mock("@sentry/nextjs", () => ({
  withIsolationScope: (fn: () => unknown) => fn(),
  getCurrentScope: () => ({ setUser: vi.fn() }),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

vi.mock("@/server/userid-pseudonymize", () => ({
  hashUserIdValue: (id: string) => `hash:${id}`,
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: () => ({ valid: true, origin: "https://app.soleur.ai" }),
  rejectCsrf: () =>
    new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
}));

import { POST } from "@/app/api/accept-terms/route";

const USER_ID = "user-accept-terms";

function makeRequest(body: unknown): Request {
  return new Request("https://app.soleur.ai/api/accept-terms", {
    method: "POST",
    headers: { origin: "https://app.soleur.ai", "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  mockGetUser.mockResolvedValue({ data: { user: { id: USER_ID } } });
  mockServiceRpc.mockResolvedValue({ data: null, error: null });
});

describe("POST /api/accept-terms — redirectTo threading", () => {
  test("keyed user with redirectTo=/invite/<token> → lands on the invite", async () => {
    mockApiKeysLimit.mockResolvedValue({ data: [{ id: "k1" }], error: null });
    const res = await POST(makeRequest({ redirectTo: "/invite/tok123" }));
    const json = await res.json();
    expect(json.redirect).toBe("/invite/tok123");
  });

  test("no-key user with redirectTo → /setup-key CARRIES the target forward (auto-return after onboarding)", async () => {
    mockApiKeysLimit.mockResolvedValue({ data: [], error: null });
    const res = await POST(makeRequest({ redirectTo: "/invite/tok123" }));
    const json = await res.json();
    // Onboarding still takes precedence, but the invite target is threaded
    // onto setup-key so a brand-new invitee auto-returns to /invite after
    // key + repo setup (T&C-first ordering preserved).
    expect(json.redirect).toBe(
      `/setup-key?redirectTo=${encodeURIComponent("/invite/tok123")}`,
    );
  });

  test("no-key user with no redirectTo → bare /setup-key (genuine new signup unchanged)", async () => {
    mockApiKeysLimit.mockResolvedValue({ data: [], error: null });
    const res = await POST(makeRequest({}));
    const json = await res.json();
    expect(json.redirect).toBe("/setup-key");
  });

  test("no-key user with open-redirect redirectTo → bare /setup-key (rejected, not carried)", async () => {
    mockApiKeysLimit.mockResolvedValue({ data: [], error: null });
    const res = await POST(makeRequest({ redirectTo: "https://evil.example" }));
    const json = await res.json();
    expect(json.redirect).toBe("/setup-key");
  });

  test("keyed user with no redirectTo → /dashboard (unchanged default)", async () => {
    mockApiKeysLimit.mockResolvedValue({ data: [{ id: "k1" }], error: null });
    const res = await POST(makeRequest({}));
    const json = await res.json();
    expect(json.redirect).toBe("/dashboard");
  });

  test("open-redirect redirectTo is rejected → /dashboard", async () => {
    mockApiKeysLimit.mockResolvedValue({ data: [{ id: "k1" }], error: null });
    const res = await POST(makeRequest({ redirectTo: "https://evil.example" }));
    const json = await res.json();
    expect(json.redirect).toBe("/dashboard");
  });
});
