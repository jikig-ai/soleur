import { readFileSync } from "fs";
import { resolve } from "path";
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { NextRequest } from "next/server";
import { PUBLIC_PATHS, TC_EXEMPT_PATHS } from "@/lib/routes";

function isPublicPath(pathname: string): boolean {
  return PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"));
}

function isTcExemptPath(pathname: string): boolean {
  return TC_EXEMPT_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"));
}

describe("middleware path routing", () => {
  describe("public paths (no auth required)", () => {
    test("public paths are allowed without auth", () => {
      expect(isPublicPath("/login")).toBe(true);
      expect(isPublicPath("/signup")).toBe(true);
      expect(isPublicPath("/callback")).toBe(true);
      expect(isPublicPath("/api/webhooks/stripe")).toBe(true);
      expect(isPublicPath("/api/inngest")).toBe(true);
      expect(isPublicPath("/ws")).toBe(true);
      expect(isPublicPath("/manifest.webmanifest")).toBe(true);
      expect(isPublicPath("/robots.txt")).toBe(true);
    });

    test("/offline.html is public (SW navigate-fallback precache; #3002/Phase-2)", () => {
      // The middleware matcher does not exclude .html, so the static offline
      // shell must be in PUBLIC_PATHS or the SW would precache a 307→/login
      // body instead of the real page.
      expect(isPublicPath("/offline.html")).toBe(true);
      // Guard the exact-match boundary: a look-alike must NOT be public.
      expect(isPublicPath("/offline.htmlx")).toBe(false);
      expect(isPublicPath("/offline")).toBe(false);
    });

    test("/api/inngest is public (HMAC-gated by Inngest SDK, not Supabase)", () => {
      // ADR-030 I4: signature verification at /api/inngest is performed by
      // `inngest/next.serve` (signingKey from INNGEST_SIGNING_KEY).
      // Supabase middleware would redirect server→SDK sync to /login.
      // Regression guard for #4017 (PR-1 cron-daily-triage missed all scheduled fires).
      expect(isPublicPath("/api/inngest")).toBe(true);
    });

    test("/api/webhooks/resend-inbound is public (svix-signature-gated by route, not Supabase)", () => {
      // The Resend Inbound webhook (#5103) carries no session cookie —
      // Supabase middleware would 307→/login before the route's own svix
      // verification gate runs. Same regression class as #4017 (/api/inngest).
      // Exact-path PUBLIC_PATHS membership is asserted (not just prefix
      // coverage) so the ingress survives any future narrowing of the broad
      // /api/webhooks prefix.
      expect(isPublicPath("/api/webhooks/resend-inbound")).toBe(true);
      expect(PUBLIC_PATHS).toContain("/api/webhooks/resend-inbound");
    });

    test("/api/internal/kb-drift-ingest is public (HMAC-gated by route, not Supabase)", () => {
      // route.ts:97 verifies KB_DRIFT_INGEST_SIGNING_KEY HMAC before any DB write.
      // The nightly KB-drift walker cron carries no session cookie, so Supabase
      // middleware would 307→/login and the HMAC gate would never run, failing
      // the workflow's 2xx assertion. Same regression class as #4017 (/api/inngest).
      expect(isPublicPath("/api/internal/kb-drift-ingest")).toBe(true);
    });

    test("/api/internal/trigger-cron is public (Bearer-gated by route, not Supabase)", () => {
      // route.ts verifies INNGEST_MANUAL_TRIGGER_SECRET via length-guarded
      // timingSafeEqual before any dispatch. The operator/agent caller carries
      // no session cookie, so Supabase middleware would 307→/login and the
      // Bearer gate would never run (the post-merge AC4 curl would get a
      // redirect, not 202). Same regression class as #4017 / kb-drift-ingest.
      expect(isPublicPath("/api/internal/trigger-cron")).toBe(true);
    });

    test("/api/waitlist is public (anonymous marketing-waitlist capture, route-gated)", () => {
      // The shared-document banner (an anonymous, cookieless surface) POSTs the
      // visitor's email here. Without PUBLIC_PATHS membership, Supabase
      // middleware 307→/login before the route's own validateOrigin + honeypot +
      // rate-limit gates run, making the form unreachable. Same class as #4017.
      // Narrow exact path — the bare /api parent stays private.
      expect(isPublicPath("/api/waitlist")).toBe(true);
      expect(isPublicPath("/api")).toBe(false);
    });

    test("/api/internal/schedule-reminder is public (Bearer-gated by route, not Supabase)", () => {
      // Same class as trigger-cron: secret-gated, cookieless operator/agent
      // caller. Without this, Supabase middleware 307→/login before the route's
      // own timingSafeEqual gate runs. The bare /api/internal parent stays
      // private (narrow exact path — no /api/internal session-bypass).
      expect(isPublicPath("/api/internal/schedule-reminder")).toBe(true);
      expect(isPublicPath("/api/internal")).toBe(false);
    });

    test("public path sub-routes are allowed", () => {
      expect(isPublicPath("/api/webhooks/stripe")).toBe(true);
      expect(isPublicPath("/callback/")).toBe(true);
    });

    test("/ws is excluded from auth middleware", () => {
      // This was a bug: middleware intercepted /ws and redirected to /login,
      // breaking WebSocket connections through Cloudflare proxy
      expect(isPublicPath("/ws")).toBe(true);
    });
  });

  describe("T&C exempt paths (auth required, T&C check skipped)", () => {
    test("/accept-terms requires auth but skips T&C check", () => {
      expect(isTcExemptPath("/accept-terms")).toBe(true);
      expect(isPublicPath("/accept-terms")).toBe(false);
    });

    test("/api/accept-terms requires auth but skips T&C check", () => {
      expect(isTcExemptPath("/api/accept-terms")).toBe(true);
      expect(isPublicPath("/api/accept-terms")).toBe(false);
    });

    test("/api/auth/github-resolve/callback requires auth but skips T&C check", () => {
      expect(isTcExemptPath("/api/auth/github-resolve/callback")).toBe(true);
      expect(isPublicPath("/api/auth/github-resolve/callback")).toBe(false);
    });
  });

  describe("protected paths (auth + T&C required)", () => {
    test("dashboard paths require auth and T&C", () => {
      expect(isPublicPath("/dashboard")).toBe(false);
      expect(isTcExemptPath("/dashboard")).toBe(false);
      expect(isPublicPath("/setup-key")).toBe(false);
      expect(isTcExemptPath("/setup-key")).toBe(false);
    });
  });

  describe("prefix collision prevention", () => {
    test("paths that share a prefix with public paths are NOT public", () => {
      expect(isPublicPath("/login-admin")).toBe(false);
      expect(isPublicPath("/callback-admin")).toBe(false);
      expect(isPublicPath("/api/webhooks-internal")).toBe(false);
      expect(isPublicPath("/ws-debug")).toBe(false);
      // The narrow /api/internal/kb-drift-ingest entry must NOT session-bypass
      // a bare /api/internal or any sibling/future internal route (#4017 class).
      expect(isPublicPath("/api/internal")).toBe(false);
      expect(isPublicPath("/api/internal/other-future-route")).toBe(false);
      // /robots.txt is an exact-match leaf path; a sibling like /robots.txtx
      // must NOT be session-bypassed (the startsWith(p + "/") arm only matches
      // /robots.txt/..., not /robots.txtx). Pins #4587 AC4.
      expect(isPublicPath("/robots.txtx")).toBe(false);
    });

    test("paths that share a prefix with T&C exempt paths are NOT exempt", () => {
      expect(isTcExemptPath("/accept-terms-evil")).toBe(false);
    });
  });
});

describe("CSP coverage invariant", () => {
  const middlewareSrc = readFileSync(
    resolve(__dirname, "../middleware.ts"),
    "utf-8",
  );

  // Extract the middleware function body (between first { and the config export)
  const funcBody = middlewareSrc.slice(
    middlewareSrc.indexOf("export async function middleware"),
    middlewareSrc.indexOf("export const config"),
  );

  // Extract only middleware-level return statements (indented with exactly
  // 2 or 4 spaces), excluding returns inside nested callbacks like cookies.getAll()
  const middlewareReturns = funcBody
    .split("\n")
    .filter((line) => /^ {2,4}return /.test(line))
    .map((line) => line.trim());

  test("every return statement uses withCspHeaders or redirectWithCookies (except /health)", () => {
    expect(middlewareReturns.length).toBeGreaterThanOrEqual(4);

    for (const stmt of middlewareReturns) {
      const hasCsp =
        stmt.includes("withCspHeaders") ||
        stmt.includes("redirectWithCookies");
      const isHealthCheck = stmt.includes("NextResponse.next()");

      expect(
        hasCsp || isHealthCheck,
        `Return statement missing CSP coverage: ${stmt}`,
      ).toBe(true);
    }
  });

  test("/health is the only exit path without CSP", () => {
    const noCspReturns = middlewareReturns.filter(
      (stmt) =>
        !stmt.includes("withCspHeaders") &&
        !stmt.includes("redirectWithCookies"),
    );

    // Only the health check should lack CSP
    expect(noCspReturns.length).toBe(1);
    expect(noCspReturns[0]).toContain("NextResponse.next()");
  });
});

// ===========================================================================
// perf-dashboard-section-load-latency — Phase 1/2 middleware behavior suite.
// Positive-only verdict caches, the x-soleur-auth-user-id trust boundary, and
// Server-Timing stage emission. Mock shapes mirror
// middleware.revocation-redirect.test.ts (createServerClient with
// auth.getUser/auth.getSession/rpc/from spies + the edge-observability shim).
// ===========================================================================

const {
  mockGetUser,
  mockGetSession,
  mockRpc,
  mockFrom,
  mockReportEdgeSilentFallback,
  tcVersionRef,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockGetSession: vi.fn(),
  mockRpc: vi.fn(),
  mockFrom: vi.fn(),
  mockReportEdgeSilentFallback: vi.fn(),
  // Mutable so a single module instance can simulate a TC_VERSION BUMP between
  // requests: the middleware reads the live binding per request, so flipping
  // this ref mid-test reproduces a deploy-time bump without resetModules
  // (which would also wipe the module-scope verdict caches under test).
  tcVersionRef: { current: "9.9.9-test" },
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

vi.mock("@/lib/legal/tc-version", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/legal/tc-version")>();
  return {
    ...actual,
    get TC_VERSION() {
      return tcVersionRef.current;
    },
  };
});

import { middleware } from "@/middleware";

const SUPABASE_URL = "https://example.supabase.co";
const SUPABASE_ANON_KEY = "anon-key";

// The verdict caches are MODULE-SCOPED (they persist across tests in this
// file). Every test that exercises them therefore seeds a unique
// (jwt sub, iat) + user.id tuple so no case can be polluted by an earlier
// test's warm entries.
let credSeq = 0;
function freshCreds() {
  credSeq += 1;
  return {
    userId: `00000000-0000-0000-0000-${String(credSeq).padStart(12, "0")}`,
    iat: 1_700_000_000 + credSeq * 60,
  };
}

function makeJwt(iatSeconds: number, sub: string): string {
  const b64 = (o: unknown) =>
    btoa(JSON.stringify(o)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
  return `${b64({ alg: "ES256", typ: "JWT" })}.${b64({ iat: iatSeconds, sub, aud: "authenticated" })}.sig`;
}

function makeAuthRequest(
  pathname: string,
  opts: {
    headers?: Record<string, string>;
    cookies?: Record<string, string>;
    method?: string;
  } = {},
): NextRequest {
  const req = new NextRequest(new URL(`https://app.soleur.ai${pathname}`), {
    method: opts.method ?? "GET",
    headers: { host: "app.soleur.ai", ...opts.headers },
  });
  for (const [name, value] of Object.entries(opts.cookies ?? {})) {
    req.cookies.set(name, value);
  }
  return req;
}

/** Wire an authenticated session: getUser → userId, getSession → JWT(sub,iat). */
function seedAuth(userId: string, iat: number) {
  mockGetUser.mockResolvedValue({
    data: { user: { id: userId, email: `${userId}@example.com` } },
    error: null,
  });
  mockGetSession.mockResolvedValue({
    data: { session: { access_token: makeJwt(iat, userId), user: { id: userId } } },
    error: null,
  });
}

/** Wire the T&C users select. Returns a spy on the terminal .single(). */
function seedTcRow(row: { tc_accepted_version: string; subscription_status: string } | { error: { message: string; code: string } }) {
  const single = vi.fn().mockResolvedValue(
    "error" in row ? { data: null, error: row.error } : { data: row, error: null },
  );
  const eq = vi.fn().mockReturnValue({ single });
  const select = vi.fn().mockReturnValue({ eq });
  mockFrom.mockReturnValue({ select });
  return { single, select, eq };
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubEnv("NODE_ENV", "production");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", SUPABASE_URL);
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", SUPABASE_ANON_KEY);
  tcVersionRef.current = "9.9.9-test";
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("verdict caches — positive-only, ≤MW_VERDICT_TTL_MS (Guard 2)", () => {
  test("warm (sub,iat) revocation verdict → second request runs ZERO check_my_revocation RPCs", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    mockRpc.mockResolvedValue({
      data: [{ revoked: false, workspace_id: null, reason: null }],
      error: null,
    });
    const { single } = seedTcRow({
      tc_accepted_version: tcVersionRef.current,
      subscription_status: "active",
    });

    const first = await middleware(makeAuthRequest("/dashboard"));
    const second = await middleware(makeAuthRequest("/dashboard"));

    expect(first.status).not.toBe(302);
    expect(second.status).not.toBe(302);
    // The RPC ran once (cold miss) and the warm verdict served request 2.
    expect(mockRpc).toHaveBeenCalledTimes(1);
    // Same for the T&C row: one select serves both requests.
    expect(single).toHaveBeenCalledTimes(1);
    // Authentication itself is NEVER cached — getUser ran per request.
    expect(mockGetUser).toHaveBeenCalledTimes(2);
  });

  test("a TC-exempt path emits the exempt T&C descriptor", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    mockRpc.mockResolvedValue({
      data: [{ revoked: false, workspace_id: null, reason: null }],
      error: null,
    });
    const { single } = seedTcRow({
      tc_accepted_version: tcVersionRef.current,
      subscription_status: "active",
    });

    const res = await middleware(
      makeAuthRequest("/accept-terms", { headers: { "sec-fetch-dest": "document" } }),
    );

    expect(res.status).not.toBe(302);
    const timing = res.headers.get("server-timing") ?? "";
    expect(timing).toContain("mw-tc");
    expect(timing).toMatch(/mw-tc;dur=[0-9.]+;desc=exempt/);
    // The exempt path must never consult the users table.
    expect(single).not.toHaveBeenCalled();
  });

  test("TC_VERSION bump ignores a cached row — read-time version check re-queries + redirects to /accept-terms", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    mockRpc.mockResolvedValue({
      data: [{ revoked: false, workspace_id: null, reason: null }],
      error: null,
    });
    tcVersionRef.current = "1.0.0";
    const { single } = seedTcRow({
      tc_accepted_version: "1.0.0",
      subscription_status: "active",
    });

    const first = await middleware(makeAuthRequest("/dashboard"));
    expect(first.status).not.toBe(302);
    expect(single).toHaveBeenCalledTimes(1); // miss → row read + cached

    // Deploy-time version bump: the same cached row must be IGNORED because
    // its stored tc_accepted_version no longer equals the live TC_VERSION.
    tcVersionRef.current = "2.0.0";
    const second = await middleware(makeAuthRequest("/dashboard"));

    // The cached entry failed the read-time version check → re-queried, and
    // the stale version on the row triggers the re-acceptance redirect.
    expect(single).toHaveBeenCalledTimes(2);
    const loc = second.headers.get("location") ?? "";
    expect(loc).toContain("/accept-terms");
  });

  test("an 'unpaid' row is never cached — the next request re-queries the users table", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    mockRpc.mockResolvedValue({
      data: [{ revoked: false, workspace_id: null, reason: null }],
      error: null,
    });
    const { single } = seedTcRow({
      tc_accepted_version: tcVersionRef.current,
      subscription_status: "unpaid",
    });

    // GET requests pass for unpaid users (read-only posture) — but the row
    // must NOT be stored, so the paid-flip lands instantly.
    const first = await middleware(makeAuthRequest("/dashboard"));
    const second = await middleware(makeAuthRequest("/dashboard"));
    expect(first.status).not.toBe(403);
    expect(second.status).not.toBe(403);
    expect(single).toHaveBeenCalledTimes(2);
  });

  test("unpaid non-GET still 403s (billing posture preserved under caching)", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    mockRpc.mockResolvedValue({
      data: [{ revoked: false, workspace_id: null, reason: null }],
      error: null,
    });
    seedTcRow({
      tc_accepted_version: tcVersionRef.current,
      subscription_status: "unpaid",
    });

    const res = await middleware(
      makeAuthRequest("/dashboard/settings", { method: "POST" }),
    );
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: "subscription_suspended" });
  });
});

describe("x-soleur-auth-user-id trust boundary", () => {
  test("delete-before-any-return (Guard 1 row 5): a forged inbound header on a PUBLIC path never forwards", async () => {
    const res = await middleware(
      makeAuthRequest("/login", {
        headers: { "x-soleur-auth-user-id": "forged-client-value" },
      }),
    );
    // Public paths early-return BEFORE auth — but the strip runs first, so the
    // forwarded request headers (snapshotted into x-middleware-request-*) must
    // NOT carry the forged value.
    expect(
      res.headers.get("x-middleware-request-x-soleur-auth-user-id"),
    ).toBeNull();
    // And the auth gate never ran for a public path.
    expect(mockGetUser).not.toHaveBeenCalled();
  });

  test("a forged inbound header on an authenticated path is overwritten by the VERIFIED user.id", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    mockRpc.mockResolvedValue({
      data: [{ revoked: false, workspace_id: null, reason: null }],
      error: null,
    });
    seedTcRow({
      tc_accepted_version: tcVersionRef.current,
      subscription_status: "active",
    });

    const res = await middleware(
      makeAuthRequest("/dashboard", {
        headers: { "x-soleur-auth-user-id": "forged-client-value" },
      }),
    );

    expect(res.status).not.toBe(302);
    // The forwarded value is middleware-minted — the spoof is gone.
    expect(
      res.headers.get("x-middleware-request-x-soleur-auth-user-id"),
    ).toBe(userId);
  });

  test("the forwarded header equals the verified identity on a clean request", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    mockRpc.mockResolvedValue({
      data: [{ revoked: false, workspace_id: null, reason: null }],
      error: null,
    });
    seedTcRow({
      tc_accepted_version: tcVersionRef.current,
      subscription_status: "active",
    });

    const res = await middleware(makeAuthRequest("/dashboard"));

    expect(res.status).not.toBe(302);
    expect(
      res.headers.get("x-middleware-request-x-soleur-auth-user-id"),
    ).toBe(userId);
  });

  test("delete-before-any-return source pin (Guard 1 row 5)", () => {
    // Belt-and-suspenders with the behavioral cases above: the strip is
    // ordering-load-bearing, so pin the source ordering itself — the delete
    // must precede the PUBLIC_PATHS early return.
    const src = readFileSync(resolve(__dirname, "../middleware.ts"), "utf-8");
    const deleteIdx = src.indexOf('requestHeaders.delete("x-soleur-auth-user-id")');
    const publicReturnIdx = src.indexOf("PUBLIC_PATHS.some");
    expect(deleteIdx, "x-soleur-auth-user-id strip missing from middleware.ts").toBeGreaterThanOrEqual(0);
    expect(publicReturnIdx).toBeGreaterThanOrEqual(0);
    expect(
      deleteIdx,
      "strip must run BEFORE the PUBLIC_PATHS early return so a forged header on /login never forwards",
    ).toBeLessThan(publicReturnIdx);
  });
});

describe("Server-Timing stage emission (authenticated document responses)", () => {
  test("emits mw-auth / mw-revoke / mw-tc durations on a successful document passthrough", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    mockRpc.mockResolvedValue({
      data: [{ revoked: false, workspace_id: null, reason: null }],
      error: null,
    });
    seedTcRow({
      tc_accepted_version: tcVersionRef.current,
      subscription_status: "active",
    });

    const res = await middleware(
      makeAuthRequest("/dashboard/settings", {
        headers: { "sec-fetch-dest": "document" },
      }),
    );

    expect(res.status).not.toBe(302);
    const timing = res.headers.get("server-timing") ?? "";
    expect(timing).toMatch(/mw-auth;dur=[0-9.]+/);
    expect(timing).toMatch(/mw-revoke;dur=[0-9.]+;desc=miss/);
    expect(timing).toMatch(/mw-tc;dur=[0-9.]+;desc=miss/);
  });

  test("a warm second request reports desc=hit on the cached stages", async () => {
    const { userId, iat } = freshCreds();
    seedAuth(userId, iat);
    mockRpc.mockResolvedValue({
      data: [{ revoked: false, workspace_id: null, reason: null }],
      error: null,
    });
    seedTcRow({
      tc_accepted_version: tcVersionRef.current,
      subscription_status: "active",
    });

    await middleware(
      makeAuthRequest("/dashboard", { headers: { "sec-fetch-dest": "document" } }),
    );
    const res = await middleware(
      makeAuthRequest("/dashboard", { headers: { "sec-fetch-dest": "document" } }),
    );

    const timing = res.headers.get("server-timing") ?? "";
    expect(timing).toMatch(/mw-revoke;dur=[0-9.]+;desc=hit/);
    expect(timing).toMatch(/mw-tc;dur=[0-9.]+;desc=hit/);
  });
});
