import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { NextRequest } from "next/server";
import { TC_VERSION } from "@/lib/legal/tc-version";

// GAP G (ADR-067 staleTimes amendment): defeat bfcache for authenticated
// documents. The middleware sets `Cache-Control: no-store` on the authenticated
// passthrough response ONLY for top-level document navigations
// (`Sec-Fetch-Dest: document`) — so a browser Back cannot restore a rendered
// authenticated page after sign-out, while API/RSC responses and the client
// Router Cache (which is NOT governed by Cache-Control — the perf win survives)
// are untouched. Public paths short-circuit before this branch and keep their
// bfcache eligibility.

const { mockGetUser, mockGetSession, mockRpc, mockFrom } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockGetSession: vi.fn(),
  mockRpc: vi.fn(),
  mockFrom: vi.fn(),
}));

vi.mock("@supabase/ssr", () => ({
  createServerClient: vi.fn(() => ({
    auth: { getUser: mockGetUser, getSession: mockGetSession },
    rpc: mockRpc,
    from: mockFrom,
  })),
}));

vi.mock("@/lib/observability-edge", () => ({
  reportEdgeSilentFallback: vi.fn(),
}));

import { middleware } from "@/middleware";

const SUPABASE_URL = "https://example.supabase.co";
const SUPABASE_ANON_KEY = "anon-key";
const USER_ID = "00000000-0000-0000-0000-000000000001";

function makeJwt(iatSeconds: number): string {
  const b64 = (o: unknown) =>
    btoa(JSON.stringify(o)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
  return `${b64({ alg: "ES256", typ: "JWT" })}.${b64({ iat: iatSeconds, sub: USER_ID, aud: "authenticated" })}.sig`;
}

function makeRequest(pathname: string, headers: Record<string, string> = {}): NextRequest {
  return new NextRequest(new URL(`https://app.soleur.ai${pathname}`), {
    headers: { host: "app.soleur.ai", ...headers },
  });
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
  mockGetSession.mockResolvedValue({
    data: { session: { access_token: makeJwt(Math.floor(Date.now() / 1000) - 60) } },
    error: null,
  });
  mockRpc.mockResolvedValue({
    data: [{ revoked: false, workspace_id: null, reason: null }],
    error: null,
  });
  // T&C matched + active subscription so the request reaches the authenticated
  // passthrough (the GAP G branch), not a /accept-terms or billing redirect.
  const single = vi.fn().mockResolvedValue({
    data: { tc_accepted_version: TC_VERSION, subscription_status: "active" },
    error: null,
  });
  mockFrom.mockReturnValue({
    select: vi.fn().mockReturnValue({ eq: vi.fn().mockReturnValue({ single }) }),
  });
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("middleware GAP G — no-store on authenticated documents", () => {
  test("authenticated DOCUMENT navigation (Sec-Fetch-Dest: document) → Cache-Control: no-store", async () => {
    const res = await middleware(
      makeRequest("/dashboard/settings", { "sec-fetch-dest": "document" }),
    );
    // Reached the authenticated passthrough (not a redirect).
    expect(res.status).not.toBe(302);
    expect(res.headers.get("cache-control")).toMatch(/no-store/);
  });

  test("authenticated NON-document fetch (Sec-Fetch-Dest: empty, RSC/API) → NOT no-store (Router Cache + API caching untouched)", async () => {
    const res = await middleware(
      makeRequest("/dashboard/settings", { "sec-fetch-dest": "empty" }),
    );
    expect(res.status).not.toBe(302);
    expect(res.headers.get("cache-control") ?? "").not.toMatch(/no-store/);
  });

  test("PUBLIC path document navigation (/login) is NOT forced no-store (public-page bfcache preserved)", async () => {
    const res = await middleware(
      makeRequest("/login", { "sec-fetch-dest": "document" }),
    );
    // Public paths short-circuit before the GAP G branch.
    expect(res.headers.get("cache-control") ?? "").not.toMatch(/no-store/);
  });
});
