import { readFileSync } from "fs";
import { resolve } from "path";
import { describe, test, expect } from "vitest";
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
