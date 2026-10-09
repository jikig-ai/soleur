// middleware.csp.test.ts — CSP wire coverage demoted from
// e2e/smoke.e2e.ts (#9855 PR 1 pyramid audit). The e2e versions asserted
// these properties through `request.get()` against a booted dev server;
// every property they proved lives in `middleware()` itself, which is
// directly invocable here — no server boot, no browser.
//
// Coverage map (deleted e2e case -> surviving assertion):
//   "CSP header contains nonce and strict-dynamic"      -> "public path carries CSP with nonce + strict-dynamic"
//   "nonce changes between requests"                    -> "mints a fresh nonce per request"
//   "CSP hardening directives"                          -> "carries the hardening directives"
//   "/signup responds with CSP headers"                 -> same public-path arm (path-parameterised)
//   "connect-src uses x-forwarded-host when present"    -> "trusted x-forwarded-host lands in connect-src"
//   "connect-src rejects spoofed x-forwarded-host"      -> "spoofed x-forwarded-host is rejected"
//   "/health returns JSON without CSP header"           -> "health exit carries no CSP" (body is the route
//                                                        handler's job, not middleware's)
//   "/dashboard|/setup-key redirect unauthenticated"    -> the !user arm is already covered by
//                                                        middleware.bounded-legs.test.ts; re-asserted here
//                                                        only to pin CSP-on-redirect.
//
// What stays at e2e (and why): the nonce must appear on rendered <script>
// tags and the console must record zero CSP violations — those are browser
// DOM/console observables no server-side layer can see.

import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { NextRequest } from "next/server";

const { mockGetUser, mockGetSession, mockRpc, mockFrom } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockGetSession: vi.fn(),
  mockRpc: vi.fn(),
  mockFrom: vi.fn(),
}));

vi.mock("@supabase/ssr", () => ({
  createServerClient: vi.fn(() => ({
    auth: { getUser: mockGetUser, getSession: mockGetSession },
    rpc: (...args: unknown[]) => {
      const r = mockRpc(...args) as
        | { abortSignal?: unknown }
        | Promise<unknown>;
      return r &&
        typeof (r as { abortSignal?: unknown }).abortSignal === "function"
        ? r
        : { abortSignal: () => r };
    },
    from: mockFrom,
  })),
}));

vi.mock("@/lib/observability-edge", () => ({
  reportEdgeSilentFallback: vi.fn(),
}));

import { middleware } from "@/middleware";

const SUPABASE_URL = "https://example.supabase.co";
const SUPABASE_ANON_KEY = "anon-key";

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubEnv("NODE_ENV", "production");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", SUPABASE_URL);
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", SUPABASE_ANON_KEY);

  // Unauthenticated by default — drives the `!user` arm on protected paths.
  mockGetUser.mockResolvedValue({ data: { user: null }, error: null });
  mockGetSession.mockResolvedValue({ data: { session: null }, error: null });
  mockRpc.mockResolvedValue({ data: null, error: null });
});

afterEach(() => {
  vi.unstubAllEnvs();
});

function makeRequest(
  pathname: string,
  headers: Record<string, string> = {},
): NextRequest {
  return new NextRequest(new URL(`https://app.soleur.ai${pathname}`), {
    headers: { host: "app.soleur.ai", ...headers },
  });
}

function cspOf(res: Awaited<ReturnType<typeof middleware>>): string {
  const csp = res.headers.get("content-security-policy");
  expect(csp, "middleware response missing Content-Security-Policy").toBeTruthy();
  return csp!;
}

describe("middleware CSP wire (demoted from e2e/smoke.e2e.ts)", () => {
  test.each(["/login", "/signup"])(
    "public path %s carries CSP with nonce + strict-dynamic",
    async (path) => {
      const res = await middleware(makeRequest(path));
      const csp = cspOf(res);
      expect(csp).toContain("nonce-");
      expect(csp).toContain("strict-dynamic");
    },
  );

  test("public path CSP carries the hardening directives", async () => {
    const csp = cspOf(await middleware(makeRequest("/login")));
    for (const directive of [
      "frame-ancestors 'none'",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'",
      "upgrade-insecure-requests",
    ]) {
      expect(csp).toContain(directive);
    }
  });

  test("mints a fresh nonce per request (not cached)", async () => {
    const nonceOf = (csp: string) => csp.match(/'nonce-([^']+)'/)![1];
    const n1 = nonceOf(cspOf(await middleware(makeRequest("/login"))));
    const n2 = nonceOf(cspOf(await middleware(makeRequest("/login"))));
    expect(n1).toBeTruthy();
    expect(n2).toBeTruthy();
    expect(n1).not.toBe(n2);
  });

  test("minted nonce is forwarded to SSR via the x-nonce request header", async () => {
    const res = await middleware(makeRequest("/login"));
    const nonce = cspOf(res).match(/'nonce-([^']+)'/)![1];
    // Next.js exposes middleware request-header writes as
    // x-middleware-request-* on the response — this pins "the nonce the SSR
    // renderer sees IS the nonce in the CSP", the request-side half of the
    // e2e nonce-on-script-tag assertion.
    expect(res.headers.get("x-middleware-request-x-nonce")).toBe(nonce);
  });

  // #1075 regression: the dev-env arms below discriminate "forwarded host
  // consulted" from "forwarded host ignored" — every rejection path in
  // resolveOrigin falls back to app.soleur.ai, so asserting on the trusted
  // prod host is vacuous (fallback produces the same appHost). Instead the
  // forwarded value is an allowlisted DEV origin (http://localhost:3000,
  // validate-origin.ts buildDevOrigins) distinct from the fallback: the
  // ws://localhost:3000 connect-src token appears only when x-forwarded-*
  // wins resolution. Host is deliberately a non-allowlisted value.
  test("trusted x-forwarded-host lands in connect-src (regression for #1075)", async () => {
    vi.stubEnv("NODE_ENV", "development");
    const res = await middleware(
      makeRequest("/login", {
        host: "internal.invalid:3000",
        "x-forwarded-host": "localhost:3000",
        "x-forwarded-proto": "http",
      }),
    );
    expect(cspOf(res)).toContain("ws://localhost:3000");
  });

  test("control: same request without x-forwarded-host falls back to app.soleur.ai", async () => {
    vi.stubEnv("NODE_ENV", "development");
    const res = await middleware(
      makeRequest("/login", { host: "internal.invalid:3000" }),
    );
    const csp = cspOf(res);
    expect(csp).not.toContain("ws://localhost:3000");
    expect(csp).toContain("ws://app.soleur.ai");
  });

  test("spoofed x-forwarded-host is rejected", async () => {
    const res = await middleware(
      makeRequest("/login", { "x-forwarded-host": "evil.com" }),
    );
    expect(cspOf(res)).not.toContain("evil.com");
  });

  test("/health is the CSP-free passthrough", async () => {
    const res = await middleware(makeRequest("/health"));
    expect(res.headers.get("content-security-policy")).toBeNull();
  });

  test.each(["/dashboard", "/setup-key"])(
    "unauthenticated %s redirects to /login and still carries CSP",
    async (path) => {
      const res = await middleware(makeRequest(path));
      expect(res.status).toBe(307);
      expect(res.headers.get("location")).toContain("/login");
      cspOf(res);
    },
  );
});
