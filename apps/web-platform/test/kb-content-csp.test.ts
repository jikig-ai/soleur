/**
 * Behavioral contract test for the CSP emitted on the binary branch of
 * /api/kb/content/[...path]/route.ts. Imports the exported constant and
 * asserts the policy's directive-level guarantees so the test survives
 * cosmetic reformatting of the literal string.
 */
import { describe, it, expect } from "vitest";
import { KB_BINARY_RESPONSE_CSP } from "@/app/api/kb/content/[...path]/route";

function parseCsp(policy: string): Map<string, string[]> {
  const directives = new Map<string, string[]>();
  for (const raw of policy.split(";")) {
    const trimmed = raw.trim();
    if (!trimmed) continue;
    const [name, ...sources] = trimmed.split(/\s+/);
    directives.set(name.toLowerCase(), sources);
  }
  return directives;
}

describe("KB_BINARY_RESPONSE_CSP", () => {
  const directives = parseCsp(KB_BINARY_RESPONSE_CSP);

  it("locks default-src to 'none'", () => {
    expect(directives.get("default-src")).toEqual(["'none'"]);
  });

  it("allows inline styles only (required by react-pdf viewer)", () => {
    expect(directives.get("style-src")).toEqual(["'unsafe-inline'"]);
  });

  it("blocks framing via frame-ancestors 'none'", () => {
    // CSP frame-ancestors has no default fallback — must be explicit, or any
    // origin can iframe user-uploaded SVG/PDF.
    expect(directives.get("frame-ancestors")).toEqual(["'none'"]);
  });

  it("does not allow script, img, connect, or object sources", () => {
    for (const directive of [
      "script-src",
      "img-src",
      "connect-src",
      "object-src",
    ]) {
      expect(directives.has(directive)).toBe(false);
    }
  });
});
