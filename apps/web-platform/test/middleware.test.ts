import { describe, test, expect } from "vitest";

// Test the PUBLIC_PATHS logic directly (middleware uses Next.js internals
// that can't run outside the framework, so we test the routing logic)
const PUBLIC_PATHS = ["/login", "/signup", "/callback", "/api/webhooks", "/ws"];

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
    expect(isPublicPath("/ws?token=abc")).toBe(true);
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
});
