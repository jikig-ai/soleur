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
  nextUrl: { pathname: string; clone(): { pathname: string } };
  method: string;
  headers: Headers;
  cookies: { getAll: () => never[]; set: () => void };
} {
  return {
    nextUrl: {
      pathname,
      clone() {
        return { pathname };
      },
    },
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

  test("query error fails open (does not block)", async () => {
    setupSupabaseClient(null, { message: "connection error" });

    const res = await middleware(makeNextRequest("/api/conversations", "POST") as never);

    // Fail-open: should NOT return 403
    expect(res.status).not.toBe(403);
  });
});
