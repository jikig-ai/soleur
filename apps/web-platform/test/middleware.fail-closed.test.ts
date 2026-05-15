import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { NextRequest } from "next/server";
import { TC_EXEMPT_PATHS } from "@/lib/routes";

// Plan AC5 / AC10: middleware MUST NOT fail open on a Supabase
// SELECT-tc_accepted_version error. On non-exempt paths, redirect to
// /accept-terms?error=db_unavailable; the Sentry mirror via
// reportSilentFallback gives operations a paging signal. Exempt paths
// (TC_EXEMPT_PATHS) stay reachable so the user can still get to the
// /accept-terms page during a DB incident.
//
// Before this change (middleware.ts:133-138 on main), tcError was a
// silent fail-open: every authenticated request reached /dashboard
// during a Supabase outage, regardless of T&C state. That's a
// brand-survival single-user incident vector — the entire reason the
// residual-audit bundle exists.

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted so factories see the mock fns
// ---------------------------------------------------------------------------

const {
  mockGetUser,
  mockFrom,
  mockReportSilentFallback,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@supabase/ssr", () => ({
  createServerClient: vi.fn(() => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  })),
}));

vi.mock("@/lib/observability-edge", () => ({
  reportEdgeSilentFallback: mockReportSilentFallback,
}));

// ---------------------------------------------------------------------------
// Import middleware AFTER mocks
// ---------------------------------------------------------------------------

import { middleware } from "@/middleware";

const SUPABASE_URL = "https://example.supabase.co";
const SUPABASE_ANON_KEY = "anon-key";

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubEnv("NODE_ENV", "production");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", SUPABASE_URL);
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", SUPABASE_ANON_KEY);

  mockGetUser.mockResolvedValue({
    data: { user: { id: "user-1", email: "u@example.com" } },
    error: null,
  });

  // Default: users SELECT returns tcError != null (the "DB incident" shape).
  const single = vi.fn().mockResolvedValue({
    data: null,
    error: { message: "ECONNRESET", code: "53000" },
  });
  const eq = vi.fn().mockReturnValue({ single });
  const select = vi.fn().mockReturnValue({ eq });
  mockFrom.mockReturnValue({ select });
});

afterEach(() => {
  vi.unstubAllEnvs();
});

function makeRequest(pathname: string): NextRequest {
  return new NextRequest(new URL(`https://app.soleur.ai${pathname}`), {
    headers: { host: "app.soleur.ai" },
  });
}

describe("middleware tcError fail-closed (AC5 / AC10)", () => {
  test.each(TC_EXEMPT_PATHS)(
    "exempt path %s stays reachable on tcError (no redirect)",
    async (exemptPath) => {
      const res = await middleware(makeRequest(exemptPath));

      // Exempt paths short-circuit ABOVE the users SELECT (middleware.ts
      // line 126 — TC_EXEMPT_PATHS check guards the entire tcError
      // branch). They should never reach the DB query at all; if the
      // implementation regresses and queries the DB anyway, the
      // defense-in-depth branch in AC5 keeps the request alive.
      expect(res.status).not.toBe(307);
      expect(res.status).not.toBe(308);
      expect(res.headers.get("location")).toBeNull();
    },
  );

  test("non-exempt /dashboard redirects to /accept-terms?error=db_unavailable on tcError", async () => {
    const res = await middleware(makeRequest("/dashboard"));

    expect([307, 308]).toContain(res.status);
    const loc = res.headers.get("location");
    expect(loc, "redirect Location header missing").not.toBeNull();
    const url = new URL(loc!);
    expect(url.pathname).toBe("/accept-terms");
    expect(url.searchParams.get("error")).toBe("db_unavailable");
  });

  test("non-exempt /dashboard mirrors tcError to Sentry via reportSilentFallback", async () => {
    await middleware(makeRequest("/dashboard"));

    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.objectContaining({ message: "ECONNRESET" }),
      expect.objectContaining({ feature: "middleware" }),
    );
  });
});
