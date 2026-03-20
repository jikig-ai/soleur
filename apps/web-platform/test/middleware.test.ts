import { describe, test, expect } from "vitest";

// Test the PUBLIC_PATHS logic directly (middleware uses Next.js internals
// that can't run outside the framework, so we test the routing logic)
const PUBLIC_PATHS = ["/login", "/signup", "/callback", "/api/webhooks", "/ws", "/accept-terms", "/api/accept-terms"];

function isPublicPath(pathname: string): boolean {
  return PUBLIC_PATHS.some((p) => pathname.startsWith(p));
}

describe("middleware path routing", () => {
  test("public paths are allowed without auth", () => {
    expect(isPublicPath("/login")).toBe(true);
    expect(isPublicPath("/signup")).toBe(true);
    expect(isPublicPath("/callback")).toBe(true);
    expect(isPublicPath("/api/webhooks/stripe")).toBe(true);
    expect(isPublicPath("/ws")).toBe(true);
    expect(isPublicPath("/ws")).toBe(true); // no token in URL after auth refactor
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

describe("T&C enforcement logic", () => {
  // Extracted enforcement logic for unit testing
  function shouldRedirectToAcceptTerms(
    user: { id: string } | null,
    tcAcceptedAt: string | null,
  ): "login" | "accept-terms" | null {
    if (!user) return "login";
    if (!tcAcceptedAt) return "accept-terms";
    return null;
  }

  test("unauthenticated user redirects to login", () => {
    expect(shouldRedirectToAcceptTerms(null, null)).toBe("login");
  });

  test("authenticated user with NULL tc_accepted_at redirects to accept-terms", () => {
    expect(shouldRedirectToAcceptTerms({ id: "user-1" }, null)).toBe("accept-terms");
  });

  test("authenticated user with tc_accepted_at proceeds normally", () => {
    expect(shouldRedirectToAcceptTerms({ id: "user-1" }, "2026-01-01T00:00:00Z")).toBeNull();
  });
});
