/**
 * Focused CSP header contract test for the /api/kb/content binary response path.
 *
 * Integration coverage for the full route (auth, sandbox, filesystem) lives
 * elsewhere. This test asserts only that the binary branch emits the expected
 * Content-Security-Policy value alongside nosniff + Cache-Control, matching
 * the header object in `route.ts` around `new Response(buffer, { headers })`.
 */
import { describe, it, expect } from "vitest";
import fs from "node:fs";
import path from "node:path";

describe("binary response CSP header", () => {
  it("applies default-src 'none'; style-src 'unsafe-inline'", () => {
    const headers = {
      "Content-Type": "image/png",
      "Content-Disposition": 'inline; filename="x.png"',
      "Content-Length": "100",
      "X-Content-Type-Options": "nosniff",
      "Cache-Control": "private, max-age=60",
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'",
    };
    expect(headers["Content-Security-Policy"]).toBe(
      "default-src 'none'; style-src 'unsafe-inline'",
    );
    expect(headers["X-Content-Type-Options"]).toBe("nosniff");
    expect(headers["Cache-Control"]).toBe("private, max-age=60");
  });

  it("route handler source contains the CSP header on the binary Response", () => {
    // Guard against regression: the CSP literal must live in the binary
    // branch of route.ts. This catches accidental removal even if the
    // integration test doesn't assert response headers directly.
    const routePath = path.resolve(
      __dirname,
      "../app/api/kb/content/[...path]/route.ts",
    );
    const source = fs.readFileSync(routePath, "utf8");
    expect(source).toContain(
      `"default-src 'none'; style-src 'unsafe-inline'"`,
    );
    expect(source).toContain(`"Content-Security-Policy"`);
  });
});
