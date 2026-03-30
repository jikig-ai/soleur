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
      expect(isPublicPath("/ws")).toBe(true);
      expect(isPublicPath("/manifest.webmanifest")).toBe(true);
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
