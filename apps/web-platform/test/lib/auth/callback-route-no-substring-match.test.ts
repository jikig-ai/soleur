import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
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
  const src = readFileSync(routePath, "utf8");

  it("does not use error.message substring match for code_verifier_missing", () => {
    expect(src).not.toMatch(/error\.message\?\.includes\("code verifier"\)/);
    expect(src).not.toMatch(/\.message[^.]*\.includes\(["']code verifier/i);
  });

  it("delegates to classifyCallbackError", () => {
    expect(src).toMatch(/classifyCallbackError\(/);
  });
});
