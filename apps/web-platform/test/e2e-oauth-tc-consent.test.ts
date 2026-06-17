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
  mockUserHasEffectiveByokKey,
} = vi.hoisted(() => ({
  mockExchangeCodeForSession: vi.fn(),
  mockGetUser: vi.fn(),
  mockUserFromCallback: vi.fn(),
  mockUserFromAcceptTerms: vi.fn(),
  mockServiceFrom: vi.fn(),
  mockServiceRpc: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockValidateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
  mockUserHasEffectiveByokKey: vi.fn(),
}));

vi.mock("@/server/byok-resolver", () => ({
  userHasEffectiveByokKey: mockUserHasEffectiveByokKey,
}));

// ADR-044 PR-2 (#5462): the callback resolves the active workspace before
// reading repo_status from the `workspaces` table. Stub the resolver to the
// test user id (solo workspace id === user id per the N2 invariant) so the
// WORKSPACES read targets a row our service-client mock recognizes.
vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentWorkspaceId: vi.fn(async () => USER_ID),
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

function makeCallbackRequest(code: string, extraQuery = ""): NextRequest {
  return new NextRequest(
    new URL(
      `https://app.soleur.ai/callback?code=${encodeURIComponent(code)}${extraQuery}`,
    ),
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

/**
 * Wire the service clients for the fully-onboarded path. Post-ADR-044 PR-2
 * (#5462) the callback reads from THREE select shapes:
 *   - users.select(workspace_status, tc_accepted_version).single()  [provision]
 *   - users.select(setup_key_skipped_at).single()                   [skip flag]
 *   - workspaces.select(repo_status).maybeSingle()                  [repo status]
 * tcVersion drives the T&C gate; repoStatus drives connect-repo vs the terminal
 * hop. setup_key_skipped_at defaults null here (no skip).
 */
function stubServiceUsersFullyOnboarded(
  tcVersion: string | null,
  repoStatus: string,
): void {
  stubServiceUsersWithSkip(tcVersion, repoStatus, null);
}

/**
 * Like stubServiceUsersFullyOnboarded but lets the caller drive
 * `setup_key_skipped_at` (read from the `users` table via .single()), so the
 * keyless-SKIPPED branch can be exercised. A non-null `skippedAt` means the
 * user chose "Set up later". `repo_status` is now AUTHORITATIVE on the
 * `workspaces` row (ADR-044 PR-2) and is served via .maybeSingle().
 */
function stubServiceUsersWithSkip(
  tcVersion: string | null,
  repoStatus: string,
  skippedAt: string | null,
): void {
  mockServiceFrom.mockImplementation((table: string) => {
    if (table === "workspaces") {
      const maybeSingle = vi.fn().mockResolvedValue({
        data: { repo_status: repoStatus },
        error: null,
      });
      return {
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockReturnValue({ maybeSingle }),
        }),
      };
    }
    if (table !== "users") {
      return { select: vi.fn(), update: vi.fn(), upsert: vi.fn() };
    }
    const select = vi.fn((columns: string) => {
      if (
        typeof columns === "string" &&
        columns.includes("setup_key_skipped_at")
      ) {
        const single = vi.fn().mockResolvedValue({
          data: { setup_key_skipped_at: skippedAt },
          error: null,
        });
        return { eq: vi.fn().mockReturnValue({ single }) };
      }
      const single = vi.fn().mockResolvedValue({
        data: { workspace_status: "ready", tc_accepted_version: tcVersion },
        error: null,
      });
      return { eq: vi.fn().mockReturnValue({ single }) };
    });
    return { select, update: vi.fn(), upsert: vi.fn() };
  });
}

/** Wire the user-scoped api_keys SELECT to return a valid key (keyed user). */
function stubApiKeysPresent(): void {
  const limit = vi.fn().mockResolvedValue({ data: [{ id: "k1" }], error: null });
  const eq3 = vi.fn().mockReturnValue({ limit });
  const eq2 = vi.fn().mockReturnValue({ eq: eq3 });
  const eq1 = vi.fn().mockReturnValue({ eq: eq2 });
  mockUserFromCallback.mockReturnValue({
    select: vi.fn().mockReturnValue({ eq: eq1 }),
  });
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

// Stub the accept-terms session client's users SELECT for setup_key_skipped_at
// (getRedirectDestination reads the skip flag via the session client). Non
// "api_keys" tables route to mockUserFromAcceptTerms via the `from` dispatch.
function stubAcceptTermsSkipFlag(skippedAt: string | null): void {
  const maybeSingle = vi
    .fn()
    .mockResolvedValue({ data: { setup_key_skipped_at: skippedAt }, error: null });
  const eq = vi.fn().mockReturnValue({ maybeSingle });
  mockUserFromAcceptTerms.mockReturnValue({
    select: vi.fn().mockReturnValue({ eq }),
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
  mockServiceRpc.mockResolvedValue({ data: null, error: null });
  mockUserHasEffectiveByokKey.mockResolvedValue(true);
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

    // session client's users SELECT for the skip flag in getRedirectDestination.
    stubAcceptTermsSkipFlag(null);

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
    stubAcceptTermsSkipFlag(null);

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

describe("OAuth callback: next-param terminal hop (Phase 4)", () => {
  beforeEach(() => {
    mockExchangeCodeForSession.mockResolvedValue({ data: null, error: null });
    mockGetUser.mockResolvedValue({
      data: { user: { id: USER_ID, email: "u@example.com" } },
    });
  });

  test("fully-onboarded user with ?next=/invite/<token> lands on the invite", async () => {
    stubServiceUsersFullyOnboarded(TC_VERSION, "connected");
    stubApiKeysPresent();

    const res = await callbackGET(
      makeCallbackRequest("code-1", "&next=%2Finvite%2Ftok123"),
    );

    expect([307, 308]).toContain(res.status);
    expect(new URL(res.headers.get("location")!).pathname).toBe(
      "/invite/tok123",
    );
  });

  test("?next never bypasses the /accept-terms gate for an unaccepted-T&C user", async () => {
    // null tc_accepted_version → must still route to /accept-terms even with next.
    stubServiceUsersFullyOnboarded(null, "connected");
    stubApiKeysPresent();

    const res = await callbackGET(
      makeCallbackRequest("code-2", "&next=%2Finvite%2Ftok123"),
    );

    expect(new URL(res.headers.get("location")!).pathname).toBe(
      "/accept-terms",
    );
  });

  test("an open-redirect ?next is rejected and falls back to /dashboard", async () => {
    stubServiceUsersFullyOnboarded(TC_VERSION, "connected");
    stubApiKeysPresent();

    const res = await callbackGET(
      makeCallbackRequest("code-3", "&next=https%3A%2F%2Fevil.example"),
    );

    expect(new URL(res.headers.get("location")!).pathname).toBe("/dashboard");
  });
});

describe("OAuth callback: keyless invitee redirect precedence (#4715)", () => {
  beforeEach(() => {
    mockExchangeCodeForSession.mockResolvedValue({ data: null, error: null });
    mockGetUser.mockResolvedValue({
      data: { user: { id: USER_ID, email: "u@example.com" } },
    });
  });

  test("keyless, NOT skipped, ?next=/invite/<token> → /invite (invite outranks /setup-key)", async () => {
    // The live bug: this branch set redirectPath = "/setup-key" and DROPPED the
    // invite next-param entirely, stranding a keyless invitee at the onboarding
    // funnel. T&C is already recorded (tcVersion === TC_VERSION) so honoring the
    // invite target here does not bypass consent.
    mockUserHasEffectiveByokKey.mockResolvedValue(false);
    stubServiceUsersWithSkip(TC_VERSION, "connected", null);

    const res = await callbackGET(
      makeCallbackRequest("code-k1", "&next=%2Finvite%2Ftok123"),
    );

    expect(new URL(res.headers.get("location")!).pathname).toBe("/invite/tok123");
  });

  test("keyless, NOT skipped, no invite next → /setup-key (genuine new signup unchanged)", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(false);
    stubServiceUsersWithSkip(TC_VERSION, "connected", null);

    const res = await callbackGET(makeCallbackRequest("code-k2"));

    expect(new URL(res.headers.get("location")!).pathname).toBe("/setup-key");
  });

  test("keyless, NOT skipped, open-redirect ?next → /setup-key (rejected, not honored)", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(false);
    stubServiceUsersWithSkip(TC_VERSION, "connected", null);

    const res = await callbackGET(
      makeCallbackRequest("code-k3", "&next=https%3A%2F%2Fevil.example"),
    );

    // safeReturnTo nulls the hostile value upstream → nextParam is null →
    // isInviteReturnTarget(null) is false → /setup-key (no off-origin hop).
    expect(new URL(res.headers.get("location")!).pathname).toBe("/setup-key");
  });

  test("keyless but SKIPPED, ?next=/invite/<token> → /invite (branch untouched — regression guard)", async () => {
    // The keyless-SKIPPED branch already honored nextParam before #4715; this
    // locks that it still does (we must not double-patch an already-correct
    // branch).
    mockUserHasEffectiveByokKey.mockResolvedValue(false);
    stubServiceUsersWithSkip(TC_VERSION, "connected", "2026-01-01T00:00:00Z");

    const res = await callbackGET(
      makeCallbackRequest("code-k4", "&next=%2Finvite%2Ftok123"),
    );

    expect(new URL(res.headers.get("location")!).pathname).toBe("/invite/tok123");
  });
});
