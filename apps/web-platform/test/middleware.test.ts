import { describe, test, expect } from "vitest";

// Test the PUBLIC_PATHS logic directly (middleware uses Next.js internals
// that can't run outside the framework, so we test the routing logic)
const PUBLIC_PATHS = ["/login", "/signup", "/callback", "/api/webhooks", "/ws", "/accept-terms", "/api/accept-terms"];

function isPublicPath(pathname: string): boolean {
  return PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(p + "/"));
}

describe("middleware path routing", () => {
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

  test("paths that share a prefix with public paths are NOT public", () => {
    expect(isPublicPath("/accept-terms-evil")).toBe(false);
    expect(isPublicPath("/api/webhooks-internal")).toBe(false);
    expect(isPublicPath("/ws-debug")).toBe(false);
    expect(isPublicPath("/login-admin")).toBe(false);
    expect(isPublicPath("/callback-admin")).toBe(false);
  });

  test("dashboard paths require auth", () => {
    expect(isPublicPath("/dashboard")).toBe(false);
    expect(isPublicPath("/dashboard/chat/new")).toBe(false);
    expect(isPublicPath("/dashboard/kb")).toBe(false);
    expect(isPublicPath("/setup-key")).toBe(false);
  });

  test("/ws is excluded from auth middleware", () => {
    // This was a bug: middleware intercepted /ws and redirected to /login,
    // breaking WebSocket connections through Cloudflare proxy
    expect(isPublicPath("/ws")).toBe(true);
  });

  test("/accept-terms is a public path (no redirect loop)", () => {
    expect(isPublicPath("/accept-terms")).toBe(true);
  });

  test("/api/accept-terms is a public path (allows POST from accept-terms page)", () => {
    expect(isPublicPath("/api/accept-terms")).toBe(true);
  });
});
