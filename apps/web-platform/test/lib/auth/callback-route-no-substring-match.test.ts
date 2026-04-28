import { describe, it, expect } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * Negative-space regression gate. The callback route once classified
 * Supabase errors via `error.message?.includes("code verifier")` — a
 * substring match against a drift-prone string. When Supabase reformatted
 * the message in v2.49.0 the matcher silently fell through to "auth_failed"
 * and every OAuth user saw the wrong copy.
 *
 * This test asserts the substring matcher is gone so a refactor can't
 * silently bring it back.
 *
 * Standalone file (per cq-test-mocked-module-constant-import) to avoid
 * collision with any test that mocks node:fs.
 */
describe("callback route does not classify on error.message substring", () => {
  const routePath = resolve(__dirname, "../../../app/(auth)/callback/route.ts");
  // Guard against silent no-ops if the route file moves or is empty —
  // an unconditional readFileSync would either throw ENOENT (loud) or
  // succeed on an unrelated file (silent). existsSync + size assertion
  // makes the failure mode explicit.
  it("can read the route source file", () => {
    expect(existsSync(routePath)).toBe(true);
  });

  const src = existsSync(routePath) ? readFileSync(routePath, "utf8") : "";

  it("source file is non-trivial", () => {
    expect(src.length).toBeGreaterThan(500);
  });

  it("does not use error.message substring match for code_verifier_missing", () => {
    // Literal pre-fix idiom must not return.
    expect(src).not.toMatch(/error\.message\?\.includes\("code verifier"\)/);
    // Quote-flips and intermediate accessors.
    expect(src).not.toMatch(/\.message[^.]*\.includes\(["']code verifier/i);
    // Semantic equivalents the literal regex misses: toLowerCase().includes(),
    // indexOf, regex.test against error.message. Window of 80 chars between
    // ".message" and "code verifier" covers normal accessor chains and
    // common formatter line breaks.
    expect(src).not.toMatch(/error\.message[\s\S]{0,80}code\s*verifier/i);
    expect(src).not.toMatch(/\/code\s*verifier\/[a-z]*\.test\s*\(/i);
    expect(src).not.toMatch(
      /error\.message[^;]{0,80}\.indexOf\s*\(\s*["']code\s*verifier/i,
    );
  });

  it("delegates to classifyCallbackError", () => {
    expect(src).toMatch(/classifyCallbackError\(/);
  });
});
