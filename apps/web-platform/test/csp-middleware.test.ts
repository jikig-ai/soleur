import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { NextRequest } from "next/server";

// Demoted from e2e/smoke.e2e.ts (#9855) — the e2e file asserted these over a
// booted dev server via `request.get`, but every property here is middleware
// WIRING, invocable offline: per-route CSP header presence, nonce generation
// and rotation, `x-forwarded-host` handling in connect-src, `/health` CSP
// absence, and unauthenticated redirects. `test/csp.test.ts` covers
// `buildCspHeader` directive CONTENT exhaustively; this file covers the
// middleware layer around it (the same invocation pattern as
// middleware.no-store.test.ts). The two assertions that DO need a browser —
// nonce on rendered script tags and the console CSP-violation listener —
// remain in e2e/smoke.e2e.ts.

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
      const r = mockRpc(...args) as { abortSignal?: unknown } | Promise<unknown>;
      return r && typeof (r as { abortSignal?: unknown }).abortSignal === "function"
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

function makeRequest(pathname: string, headers: Record<string, string> = {}): NextRequest {
  return new NextRequest(new URL(`https://app.soleur.ai${pathname}`), {
    headers: { host: "app.soleur.ai", ...headers },
  });
}

function extractNonceFromCsp(csp: string): string | null {
  const match = csp.match(/'nonce-([^']+)'/);
  return match ? match[1] : null;
}

beforeEach(() => {
  vi.clearAllMocks();
  // Production shape — the e2e ran under NODE_ENV=development (ws:// in
  // connect-src); in vitest we assert the prod wss:// form, which exercises
  // the same resolveOrigin -> appHost wiring.
  vi.stubEnv("NODE_ENV", "production");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://example.supabase.co");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "anon-key");

  // No session, no user — protected paths take the `!user` arm.
  mockGetUser.mockResolvedValue({ data: { user: null }, error: null });
  mockGetSession.mockResolvedValue({ data: { session: null }, error: null });
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("CSP nonce propagation (public paths)", () => {
  test("/login carries CSP with strict-dynamic and a nonce", async () => {
    const res = await middleware(makeRequest("/login"));
    const csp = res.headers.get("content-security-policy");

    expect(csp).toBeTruthy();
    expect(csp).toContain("strict-dynamic");

    const nonce = extractNonceFromCsp(csp!);
    expect(nonce).toBeTruthy();
    expect(nonce!.length).toBeGreaterThan(0);
  });

  test("nonce rotates between invocations (not cached)", async () => {
    const res1 = await middleware(makeRequest("/login"));
    const res2 = await middleware(makeRequest("/login"));

    const nonce1 = extractNonceFromCsp(res1.headers.get("content-security-policy")!);
    const nonce2 = extractNonceFromCsp(res2.headers.get("content-security-policy")!);

    expect(nonce1).toBeTruthy();
    expect(nonce2).toBeTruthy();
    expect(nonce1).not.toBe(nonce2);
  });

  test("/signup carries CSP with a nonce", async () => {
    const res = await middleware(makeRequest("/signup"));
    const csp = res.headers.get("content-security-policy");
    expect(csp).toBeTruthy();
    expect(csp).toContain("nonce-");
  });
});

describe("CSP hardening directives", () => {
  test("/login CSP contains all hardening directives", async () => {
    const res = await middleware(makeRequest("/login"));
    const csp = res.headers.get("content-security-policy")!;
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
});

describe("CSP connect-src via x-forwarded-host (regression for #1075)", () => {
  test("accepted forwarded host lands in connect-src", async () => {
    const res = await middleware(
      makeRequest("/login", { "x-forwarded-host": "app.soleur.ai" }),
    );
    const csp = res.headers.get("content-security-policy")!;
    // resolveOrigin accepts https://app.soleur.ai (PRODUCTION_ORIGINS), so
    // the host reaches connect-src in prod wss:// form — not the internal
    // bind address.
    expect(csp).toContain("wss://app.soleur.ai");
  });

  test("spoofed x-forwarded-host is rejected from connect-src", async () => {
    const res = await middleware(
      makeRequest("/login", { "x-forwarded-host": "evil.com" }),
    );
    const csp = res.headers.get("content-security-policy")!;
    // resolveOrigin falls back to https://app.soleur.ai — the spoofed host
    // must not reach the directive.
    expect(csp).not.toContain("evil.com");
  });
});

describe("/health bypass", () => {
  test("/health carries no CSP header", async () => {
    const res = await middleware(makeRequest("/health"));
    expect(res.headers.get("content-security-policy")).toBeNull();
    // The early return also never constructs a Supabase client.
    expect(mockGetUser).not.toHaveBeenCalled();
  });
});

describe("unauthenticated redirects", () => {
  test("/dashboard redirects unauthenticated to /login", async () => {
    const res = await middleware(makeRequest("/dashboard"));
    expect(res.status).toBe(307);
    expect(res.headers.get("location")).toContain("/login");
  });

  test("/setup-key redirects unauthenticated to /login", async () => {
    const res = await middleware(makeRequest("/setup-key"));
    expect(res.status).toBe(307);
    expect(res.headers.get("location")).toContain("/login");
  });
});
