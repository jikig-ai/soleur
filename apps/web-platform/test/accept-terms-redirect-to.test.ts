process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "test-anon-key";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, test, expect, vi, beforeEach } from "vitest";

// Phase 4b: POST /api/accept-terms honors a validated `redirectTo` as the
// terminal hop AFTER recording T&C, but only once a key exists (no key →
// /setup-key takes precedence). The redirect is re-validated server-side via
// safeReturnTo, so an open-redirect value falls back to /dashboard.

const { mockGetUser, mockServiceRpc, mockUserHasEffectiveByokKey } = vi.hoisted(
  () => ({
    mockGetUser: vi.fn(),
    mockServiceRpc: vi.fn(),
    mockUserHasEffectiveByokKey: vi.fn(),
  }),
);

// #4642 merged the redirect gate onto the effective-key helper: "keyed user"
// here means hasEffectiveKey=true (own valid key OR accepted delegation). The
// skip flag is read via the session client and defaults to null (not skipped).
vi.mock("@/server/byok-resolver", () => ({
  userHasEffectiveByokKey: mockUserHasEffectiveByokKey,
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: () =>
            Promise.resolve({ data: { setup_key_skipped_at: null }, error: null }),
        }),
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
    mockUserHasEffectiveByokKey.mockResolvedValue(true);
    const res = await POST(makeRequest({ redirectTo: "/invite/tok123" }));
    const json = await res.json();
    expect(json.redirect).toBe("/invite/tok123");
  });

  test("no-key user with redirectTo=/invite/<token> → lands on the invite (#4715: invite outranks /setup-key)", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(false);
    const res = await POST(makeRequest({ redirectTo: "/invite/tok123" }));
    const json = await res.json();
    // #4715 reverses the #4641 "carry forward onto /setup-key" behavior for
    // invite targets: a keyless invitee can't complete the key-purchase funnel,
    // so the validated invite next-hop now OUTRANKS the onboarding gate. T&C is
    // still recorded first (the accept_terms RPC runs before this redirect).
    expect(json.redirect).toBe("/invite/tok123");
    expect(json.redirect).not.toContain("setup-key");
  });

  test("no-key user with a non-invite redirectTo → /setup-key CARRIES the target forward (unchanged)", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(false);
    const res = await POST(makeRequest({ redirectTo: "/dashboard" }));
    const json = await res.json();
    // Non-invite targets still thread onto /setup-key so a genuine new signup
    // auto-returns after onboarding — only `/invite/` outranks the gate.
    expect(json.redirect).toBe(
      `/setup-key?redirectTo=${encodeURIComponent("/dashboard")}`,
    );
  });

  test("no-key user with no redirectTo → bare /setup-key (genuine new signup unchanged)", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(false);
    const res = await POST(makeRequest({}));
    const json = await res.json();
    expect(json.redirect).toBe("/setup-key");
  });

  test("no-key user with open-redirect redirectTo → bare /setup-key (rejected, not carried)", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(false);
    const res = await POST(makeRequest({ redirectTo: "https://evil.example" }));
    const json = await res.json();
    expect(json.redirect).toBe("/setup-key");
    // Distinguish "rejected" from "feature absent": the hostile value must NOT
    // be threaded — no ?redirectTo= query, no off-origin host.
    expect(json.redirect).not.toContain("redirectTo");
    expect(json.redirect).not.toContain("evil.example");
  });

  test("keyed user with no redirectTo → /dashboard (unchanged default)", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(true);
    const res = await POST(makeRequest({}));
    const json = await res.json();
    expect(json.redirect).toBe("/dashboard");
  });

  test("open-redirect redirectTo is rejected → /dashboard", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(true);
    const res = await POST(makeRequest({ redirectTo: "https://evil.example" }));
    const json = await res.json();
    expect(json.redirect).toBe("/dashboard");
  });
});

describe("POST /api/accept-terms — TR2 ordering (T&C before membership)", () => {
  test("accept_terms RPC error → 500 and NO redirect is produced (never /invite before consent)", async () => {
    // The redirect — including any /invite hop — is computed only AFTER the
    // accept_terms RPC succeeds. If the RPC fails, the route returns 500 and the
    // body carries no `redirect`, so an invitee can never reach /invite before
    // their T&C acceptance is durably recorded. `/invite` is in PUBLIC_PATHS so
    // the middleware T&C gate does NOT fire there — this ordering IS the consent
    // guarantee.
    mockUserHasEffectiveByokKey.mockResolvedValue(false);
    mockServiceRpc.mockResolvedValue({
      data: null,
      error: { message: "rpc failed" },
    });
    const res = await POST(makeRequest({ redirectTo: "/invite/tok123" }));
    expect(res.status).toBe(500);
    const json = await res.json();
    expect(json.redirect).toBeUndefined();
    expect(JSON.stringify(json)).not.toContain("/invite/");
  });
});

describe("POST /api/accept-terms — open-redirect reject vectors (no /invite/ bypass)", () => {
  // Each hostile value must be nulled by safeReturnTo BEFORE isInviteReturnTarget
  // sees it, so a keyless user falls to bare /setup-key — never an off-origin
  // hop and never a forged /invite/ target.
  const VECTORS: Array<[string, string]> = [
    ["protocol-relative", "//evil.example"],
    ["absolute URL", "https://evil.example"],
    ["backslash bypass", "/\\evil.example"],
    ["path traversal", "/dashboard/../secret"],
    // The critical one: a value that LOOKS like an invite target but smuggles a
    // protocol-relative host via percent-encoded separators. safeReturnTo runs
    // the dangerous-substring guards on the decoded form, so /invite/%2F%2Fevil
    // → /invite///evil → rejected.
    ["smuggled invite prefix", "/invite/%2F%2Fevil.example"],
  ];

  test.each(VECTORS)(
    "%s redirectTo is rejected → bare /setup-key (keyless), no leak",
    async (_label, hostile) => {
      mockUserHasEffectiveByokKey.mockResolvedValue(false);
      const res = await POST(makeRequest({ redirectTo: hostile }));
      const json = await res.json();
      expect(json.redirect).toBe("/setup-key");
      expect(json.redirect).not.toContain("evil");
      expect(json.redirect).not.toContain("redirectTo");
    },
  );
});
