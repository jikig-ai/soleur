import { describe, test, expect } from "vitest";
import { normalizeRepoUrl } from "@/lib/repo-url";

// RED phase for #2775 — `normalizeRepoUrl(raw)` helper.
//
// Contract (from plan 2026-04-22-refactor-drain-web-platform-code-review-2775-2776-2777-plan.md):
//   1. trim() leading/trailing whitespace
//   2. Lowercase scheme + host only (preserve owner/repo path case)
//   3. Strip trailing `.git` case-insensitively (suffix-anchored)
//   4. Strip trailing `/` (one or more)
//   5. Idempotent — normalize(normalize(x)) === normalize(x)
//   6. Empty/null/undefined → ""
//   7. Non-URL input passes through (trim only; no throw)

describe("normalizeRepoUrl", () => {
  test("empty string returns empty string", () => {
    expect(normalizeRepoUrl("")).toBe("");
  });

  test("null returns empty string", () => {
    expect(normalizeRepoUrl(null)).toBe("");
  });

  test("undefined returns empty string", () => {
    expect(normalizeRepoUrl(undefined)).toBe("");
  });

  test("trims leading/trailing whitespace", () => {
    expect(normalizeRepoUrl("  https://github.com/foo/bar  ")).toBe(
      "https://github.com/foo/bar",
    );
  });

  test("strips trailing .git (lowercase)", () => {
    expect(normalizeRepoUrl("https://github.com/foo/bar.git")).toBe(
      "https://github.com/foo/bar",
    );
  });

  test("strips trailing .GIT (uppercase) case-insensitively", () => {
    expect(normalizeRepoUrl("https://github.com/foo/bar.GIT")).toBe(
      "https://github.com/foo/bar",
    );
  });

  test("suffix-anchored .git strip — does NOT strip mid-string .git", () => {
    expect(normalizeRepoUrl("https://github.com/foo/bar.git.bak")).toBe(
      "https://github.com/foo/bar.git.bak",
    );
  });

  test("strips single trailing slash", () => {
    expect(normalizeRepoUrl("https://github.com/foo/bar/")).toBe(
      "https://github.com/foo/bar",
    );
  });

  test("strips multiple trailing slashes", () => {
    expect(normalizeRepoUrl("https://github.com/foo/bar///")).toBe(
      "https://github.com/foo/bar",
    );
  });

  test("combined: .git and trailing slash", () => {
    expect(normalizeRepoUrl("https://github.com/Owner/Repo.git/")).toBe(
      "https://github.com/Owner/Repo",
    );
  });

  test("strips repeated trailing .git (.git.git) in one pass — idempotence guard", () => {
    expect(normalizeRepoUrl("https://github.com/foo/bar.git.git")).toBe(
      "https://github.com/foo/bar",
    );
  });

  test("strips .git.git with trailing slash", () => {
    expect(normalizeRepoUrl("https://github.com/foo/bar.git.git/")).toBe(
      "https://github.com/foo/bar",
    );
  });

  test("lowercases scheme", () => {
    expect(normalizeRepoUrl("HTTPS://github.com/foo/bar")).toBe(
      "https://github.com/foo/bar",
    );
  });

  test("lowercases host only, preserves owner/repo path case", () => {
    expect(normalizeRepoUrl("HTTPS://GitHub.com/Foo/Bar")).toBe(
      "https://github.com/Foo/Bar",
    );
  });

  test("preserves path case for mixed-case owner/repo", () => {
    expect(normalizeRepoUrl("https://github.com/Anthropic-Labs/Foo.git")).toBe(
      "https://github.com/Anthropic-Labs/Foo",
    );
  });

  test("no change on already-canonical input", () => {
    expect(normalizeRepoUrl("https://github.com/foo/bar")).toBe(
      "https://github.com/foo/bar",
    );
  });

  test("non-URL pass-through (trimmed only)", () => {
    expect(normalizeRepoUrl("garbage")).toBe("garbage");
  });

  test("non-URL pass-through with trailing .git still strips", () => {
    // String-only ops apply even on non-URL strings for consistency:
    // trim → strip trailing slash → strip trailing .git.
    expect(normalizeRepoUrl("  garbage.git/  ")).toBe("garbage");
  });

  describe("idempotence", () => {
    const fixtures = [
      "",
      "https://github.com/foo/bar",
      "https://github.com/Owner/Repo.git/",
      "HTTPS://GitHub.com/Foo/Bar",
      "https://github.com/foo/bar.git.bak",
      "https://github.com/foo/bar.git.git",
      "https://github.com/foo/bar.GIT",
      "https://github.com/foo/bar///",
      "  https://github.com/foo/bar  ",
      "garbage",
    ];
    test.each(fixtures)("normalize(normalize(%s)) === normalize(%s)", (input) => {
      const once = normalizeRepoUrl(input);
      const twice = normalizeRepoUrl(once);
      expect(twice).toBe(once);
    });
  });
});
