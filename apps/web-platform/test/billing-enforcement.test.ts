import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const {
  mockGetUser,
  mockFrom,
  mockCreateServerClient,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockCreateServerClient: vi.fn(),
}));

vi.mock("@supabase/ssr", () => ({
  createServerClient: mockCreateServerClient,
}));

vi.mock("@/lib/csp", () => ({
  buildCspHeader: () => "default-src 'self'",
}));

vi.mock("@/lib/auth/resolve-origin", () => ({
  resolveOrigin: () => "https://app.soleur.ai",
}));

vi.mock("@/lib/legal/tc-version", () => ({
  TC_VERSION: "1.0.0",
}));

// ---------------------------------------------------------------------------
// Import middleware AFTER mocks
// ---------------------------------------------------------------------------

import { middleware } from "@/middleware";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function setupSupabaseClient(userData: Record<string, unknown> | null, userError: unknown = null) {
  const mockSingle = vi.fn().mockResolvedValue({
    data: userData,
    error: userError,
  });
  const mockEq = vi.fn().mockReturnValue({ single: mockSingle });
  const mockSelect = vi.fn().mockReturnValue({ eq: mockEq });
  mockFrom.mockReturnValue({ select: mockSelect });

  const supabase = {
    auth: { getUser: mockGetUser },
    from: mockFrom,
  };
  mockCreateServerClient.mockReturnValue(supabase);
  return { mockSelect, mockEq, mockSingle };
}

function makeNextRequest(pathname: string, method = "GET"): {
  nextUrl: URL & { clone(): URL };
  method: string;
  headers: Headers;
  cookies: { getAll: () => never[]; set: () => void };
} {
  // Real URL object so NextResponse.redirect(url) can stringify cleanly.
  // The clone() helper mirrors NextRequest's contract: returns a fresh
  // URL the middleware can mutate (.pathname, .search) without aliasing.
  const base = new URL(`https://app.soleur.ai${pathname}`);
  const nextUrl = Object.assign(base, {
    clone() {
      return new URL(base.href);
    },
  }) as URL & { clone(): URL };
  return {
    nextUrl,
    method,
    headers: new Headers({
      host: "app.soleur.ai",
      "x-forwarded-host": "app.soleur.ai",
      "x-forwarded-proto": "https",
    }),
    cookies: {
      getAll: () => [],
      set: () => {},
    },
  };
}

// ---------------------------------------------------------------------------
// Tests — billing enforcement in middleware
// ---------------------------------------------------------------------------

describe("Middleware billing enforcement", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetUser.mockResolvedValue({
      data: { user: { id: "user-123" } },
    });
  });

  test("unpaid user GET request passes through", async () => {
    setupSupabaseClient({
      tc_accepted_version: "1.0.0",
      subscription_status: "unpaid",
    });

    const res = await middleware(makeNextRequest("/dashboard") as never);

    // Should NOT be a 403 — GET is allowed for unpaid users
    expect(res.status).not.toBe(403);
  });

  test("unpaid user POST to /api/ returns 403", async () => {
    setupSupabaseClient({
      tc_accepted_version: "1.0.0",
      subscription_status: "unpaid",
    });

    const res = await middleware(makeNextRequest("/api/conversations", "POST") as never);

    expect(res.status).toBe(403);
    const body = await res.json();
    expect(body.error).toBe("subscription_suspended");
  });

  test("unpaid user POST to /api/billing/portal passes through", async () => {
    setupSupabaseClient({
      tc_accepted_version: "1.0.0",
      subscription_status: "unpaid",
    });

    const res = await middleware(makeNextRequest("/api/billing/portal", "POST") as never);

    expect(res.status).not.toBe(403);
  });

  test("unpaid user POST to /api/checkout passes through", async () => {
    setupSupabaseClient({
      tc_accepted_version: "1.0.0",
      subscription_status: "unpaid",
    });

    const res = await middleware(makeNextRequest("/api/checkout", "POST") as never);

    expect(res.status).not.toBe(403);
  });

  test("active user POST is unaffected", async () => {
    setupSupabaseClient({
      tc_accepted_version: "1.0.0",
      subscription_status: "active",
    });

    const res = await middleware(makeNextRequest("/api/conversations", "POST") as never);

    expect(res.status).not.toBe(403);
  });

  test("query error fails CLOSED — redirects to /accept-terms?error=db_unavailable (AC5)", async () => {
    setupSupabaseClient(null, { message: "connection error" });

    const res = await middleware(makeNextRequest("/api/conversations", "POST") as never);

    // Fail-closed per feat-oauth-tc-consent-3205 AC5. Returning 403
    // would now be wrong; redirecting to /accept-terms is the new
    // contract. Critically, NOT NextResponse.next() (which is what
    // the old fail-open did) — that would silently admit users
    // during a DB incident, an Art. 7(1) demonstrability breach.
    expect([307, 308]).toContain(res.status);
    const loc = res.headers.get("location");
    expect(loc).not.toBeNull();
    const url = new URL(loc!);
    expect(url.pathname).toBe("/accept-terms");
    expect(url.searchParams.get("error")).toBe("db_unavailable");
  });
});
