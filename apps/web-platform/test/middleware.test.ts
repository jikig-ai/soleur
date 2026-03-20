import { describe, test, expect } from "vitest";

// Test the middleware path routing logic directly (middleware uses Next.js
// internals that can't run outside the framework, so we test the routing logic).
// These arrays must mirror middleware.ts exactly.
const PUBLIC_PATHS = ["/login", "/signup", "/callback", "/api/webhooks", "/ws"];
const TC_EXEMPT_PATHS = ["/accept-terms", "/api/accept-terms"];

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
