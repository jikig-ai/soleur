import { describe, it, expect } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * Negative-space regression gate. The classifier's docblock forbids
 * `.toLowerCase()`, `.includes()`, regex `.test()`, `indexOf()`, and
 * splitting on `[`. This test asserts the source file does not regress
 * to substring or normalized matching.
 *
 * Standalone file (per cq-test-mocked-module-constant-import) so it can't
 * collide with any test that mocks node:fs.
 */
describe("provider-error-classifier does not normalize or substring-match", () => {
  const srcPath = resolve(
    __dirname,
    "../../../lib/auth/provider-error-classifier.ts",
  );

  it("can read the classifier source file", () => {
    expect(existsSync(srcPath)).toBe(true);
  });

  const rawSrc = existsSync(srcPath) ? readFileSync(srcPath, "utf8") : "";
  // Strip comments before matching so the docblock's mention of forbidden
  // idioms (`.toLowerCase()`, `.includes()`, etc.) does not falsely fail
  // these negative-space assertions.
  const src = rawSrc
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/.*$/gm, "$1");

  it("source file is non-trivial", () => {
    expect(rawSrc.length).toBeGreaterThan(300);
  });

  it("does not call .toLowerCase / .toUpperCase on the error code", () => {
    expect(src).not.toMatch(/\.toLowerCase\(/);
    expect(src).not.toMatch(/\.toUpperCase\(/);
  });

  it("does not substring-match on the error code", () => {
    expect(src).not.toMatch(/\.includes\(/);
    expect(src).not.toMatch(/\.indexOf\(/);
  });

  it("does not regex-test the error code", () => {
    expect(src).not.toMatch(/\.test\(\s*errorCode/);
    expect(src).not.toMatch(/\/access[_-]?denied\/[a-z]*\.test/i);
  });

  it("does not split on bracket characters", () => {
    expect(src).not.toMatch(/\.split\(\s*["']\[/);
  });

  it("uses Object.hasOwn for the table lookup (prevents prototype-chain hits)", () => {
    expect(src).toMatch(/Object\.hasOwn\(/);
  });
});
