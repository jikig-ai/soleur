import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { NextRequest } from "next/server";

// #4307 plan §2.5 / AC1+AC2+AC3+AC8, hardened by the 2026-06-15
// session-disconnect fix. Verifies the middleware revocation gate:
//   * genuine revoked=true → redirect to /login?revoked=<reason> with
//     cleared sb-* cookies (dual-shape, F8) + Cache-Control: no-store
//     (security boundary — UNCHANGED, AC2).
//   * transient `check_my_revocation` RPC error → GRACE: the otherwise-valid
//     session is allowed through (NO 503, NO logout); op
//     `revocation_gate.transient_grace` is emitted so operators see DB
//     degradation without SSH (AC1). Previously fail-CLOSED to 503-for-all.
//   * malformed / no-iat JWT (getUser() already validated the session) →
//     GRACE: allowed through (NO logout); op `malformed_jwt` / `no_iat`
//     still emitted. Previously fail-CLOSED to /login?revoked=session-error.
//   * PUBLIC_PATHS (/login) skip the gate.

const {
  mockGetUser,
  mockGetSession,
  mockRpc,
  mockFrom,
  mockReportEdgeSilentFallback,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockGetSession: vi.fn(),
  mockRpc: vi.fn(),
  mockFrom: vi.fn(),
  mockReportEdgeSilentFallback: vi.fn(),
}));

vi.mock("@supabase/ssr", () => ({
  createServerClient: vi.fn(() => ({
    auth: { getUser: mockGetUser, getSession: mockGetSession },
    rpc: mockRpc,
    from: mockFrom,
  })),
}));

vi.mock("@/lib/observability-edge", () => ({
  reportEdgeSilentFallback: mockReportEdgeSilentFallback,
}));

import { middleware } from "@/middleware";

const SUPABASE_URL = "https://example.supabase.co";
const SUPABASE_ANON_KEY = "anon-key";
const USER_ID = "00000000-0000-0000-0000-000000000001";

function makeJwt(iatSeconds: number): string {
  const header = btoa(JSON.stringify({ alg: "ES256", typ: "JWT" }))
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
  const payload = btoa(
    JSON.stringify({ iat: iatSeconds, sub: USER_ID, aud: "authenticated" }),
  )
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
  return `${header}.${payload}.signature`;
}

function makeRequest(pathname: string, cookies: Record<string, string> = {}): NextRequest {
  const req = new NextRequest(new URL(`https://app.soleur.ai${pathname}`), {
    headers: { host: "app.soleur.ai" },
  });
  for (const [name, value] of Object.entries(cookies)) {
    req.cookies.set(name, value);
  }
  return req;
}

function mockTcSelectOk() {
  // For non-revoked / passthrough cases, the downstream T&C SELECT runs.
  // Default it to a valid row so the request can return 200 (or T&C redirect).
  const single = vi.fn().mockResolvedValue({
    data: { tc_accepted_version: "v0", subscription_status: "active" },
    error: null,
  });
  const eq = vi.fn().mockReturnValue({ single });
  const select = vi.fn().mockReturnValue({ eq });
  mockFrom.mockReturnValue({ select });
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubEnv("NODE_ENV", "production");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", SUPABASE_URL);
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", SUPABASE_ANON_KEY);

  mockGetUser.mockResolvedValue({
    data: { user: { id: USER_ID, email: "u@example.com" } },
    error: null,
  });
  const iat = Math.floor(Date.now() / 1000) - 60;
  mockGetSession.mockResolvedValue({
    data: { session: { access_token: makeJwt(iat) } },
    error: null,
  });
  // Default: not revoked.
  mockRpc.mockResolvedValue({
    data: [{ revoked: false, workspace_id: null, reason: null }],
    error: null,
  });
  mockTcSelectOk();
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("middleware #4307 revocation gate", () => {
  test("revoked=removed → 302 /login?revoked=removed with no-store + cleared sb-* cookies", async () => {
    mockRpc.mockResolvedValue({
      data: [
        {
          revoked: true,
          workspace_id: "11111111-1111-1111-1111-111111111111",
          reason: "removed",
        },
      ],
      error: null,
    });

    const req = makeRequest("/dashboard", {
      "sb-access-token": "old.access.tok",
      "sb-refresh-token": "old.refresh",
    });
    const res = await middleware(req);

    expect(res.status).toBe(302);
    const location = res.headers.get("location");
    expect(location).toContain("/login");
    expect(location).toContain("revoked=removed");
    expect(res.headers.get("cache-control")).toMatch(/no-store/);
    // Both cookies cleared (maxAge=0 ⇒ Max-Age=0 in serialized set-cookie).
    const setCookies = res.headers.getSetCookie();
    expect(setCookies.some((c) => c.startsWith("sb-access-token=") && /Max-Age=0/.test(c))).toBe(true);
    expect(setCookies.some((c) => c.startsWith("sb-refresh-token=") && /Max-Age=0/.test(c))).toBe(true);
  });

  test("revoked=role-changed → /login?revoked=role-changed", async () => {
    mockRpc.mockResolvedValue({
      data: [
        {
          revoked: true,
          workspace_id: "11111111-1111-1111-1111-111111111111",
          reason: "role-changed",
        },
      ],
      error: null,
    });
    const res = await middleware(makeRequest("/dashboard"));
    expect(res.status).toBe(302);
    expect(res.headers.get("location")).toContain("revoked=role-changed");
  });

  test("F8 dual-shape cookie clear: NEXT_PUBLIC_COOKIE_DOMAIN set → both Domain-less AND Domain= cookie clears", async () => {
    vi.stubEnv("NEXT_PUBLIC_COOKIE_DOMAIN", ".soleur.ai");
    mockRpc.mockResolvedValue({
      data: [{ revoked: true, workspace_id: null, reason: "removed" }],
      error: null,
    });
    const req = makeRequest("/dashboard", { "sb-access-token": "tok" });
    const res = await middleware(req);
    const setCookies = res.headers.getSetCookie();
    const accessTokenClears = setCookies.filter((c) => c.startsWith("sb-access-token=") && /Max-Age=0/.test(c));
    expect(accessTokenClears.length).toBe(2);
    expect(accessTokenClears.some((c) => /Domain=\.soleur\.ai/i.test(c))).toBe(true);
    expect(accessTokenClears.some((c) => !/Domain=/i.test(c))).toBe(true);
  });

  test("transient check_my_revocation RPC error → GRACE (no 503, no logout) + transient_grace mirror (AC1)", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: "ECONNRESET", code: "53000" },
    });
    const res = await middleware(makeRequest("/dashboard"));
    // A transient DB blip must NOT 503-for-all and must NOT log the user out:
    // the otherwise-valid session grace-falls-through to the normal flow and
    // re-checks on the next request.
    expect(res.status).not.toBe(503);
    expect(res.headers.get("location") ?? "").not.toContain("revoked=");
    // Operators still see the degradation without SSH via a distinct op slug.
    expect(mockReportEdgeSilentFallback).toHaveBeenCalledWith(
      expect.objectContaining({ message: "ECONNRESET" }),
      expect.objectContaining({ op: "revocation_gate.transient_grace" }),
    );
  });

  test("no-iat JWT (getUser validated) → GRACE (no logout) + no_iat mirror", async () => {
    const header = btoa(JSON.stringify({ alg: "ES256" })).replace(/=/g, "");
    const payload = btoa(JSON.stringify({ sub: USER_ID })).replace(/=/g, "");
    mockGetSession.mockResolvedValue({
      data: { session: { access_token: `${header}.${payload}.sig` } },
      error: null,
    });
    const res = await middleware(makeRequest("/dashboard"));
    // getUser() already validated the session upstream; a missing-iat decode
    // is a decoder hiccup, NOT a revocation — do not force a logout.
    expect(res.status).not.toBe(503);
    expect(res.headers.get("location") ?? "").not.toContain("revoked=");
    expect(mockReportEdgeSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "revocation_gate.no_iat" }),
    );
    // The revocation RPC is never reached without a usable iat.
    expect(mockRpc).not.toHaveBeenCalled();
  });

  test("malformed JWT (only 2 segments) → GRACE (no logout) + malformed_jwt mirror", async () => {
    mockGetSession.mockResolvedValue({
      data: { session: { access_token: "only.twoparts" } },
      error: null,
    });
    const res = await middleware(makeRequest("/dashboard"));
    expect(res.status).not.toBe(503);
    expect(res.headers.get("location") ?? "").not.toContain("revoked=");
    expect(mockReportEdgeSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "revocation_gate.malformed_jwt" }),
    );
    expect(mockRpc).not.toHaveBeenCalled();
  });

  test("not revoked → revocation gate falls through to T&C check (NOT redirected to /login)", async () => {
    const res = await middleware(makeRequest("/dashboard"));
    // T&C SELECT default returns v0/active; current TC_VERSION is unlikely
    // to be "v0", so the middleware redirects to /accept-terms. The key
    // assertion is that it does NOT 302 to /login?revoked=...
    const location = res.headers.get("location") ?? "";
    expect(location).not.toContain("revoked=");
  });

  test("/login is in PUBLIC_PATHS — revocation gate skipped, mockRpc never called", async () => {
    const res = await middleware(makeRequest("/login"));
    // Public paths short-circuit before getUser/RPC.
    expect(mockRpc).not.toHaveBeenCalled();
    // Should NOT be a 302 to /login (already there).
    expect(res.status).not.toBe(302);
  });
});
