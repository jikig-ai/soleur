import { describe, it, expect } from "vitest";
import { kbGithubUrlPath, kbPathSegments } from "@/server/kb-github-path";

// The guard for every request-derived KB path interpolated into a GitHub API
// URL. fetch's URL parser resolves `%2e%2e`/`.%2e` as `..` and `\` as `/`, and a
// raw `?`/`#` starts a query/fragment, so the guard's job is: no dot segments
// in any spelling, and every other character sent as a literal name.
describe("kbGithubUrlPath", () => {
  it.each([
    "",
    "/abs",
    "a/",
    "a//b",
    ".",
    "..",
    "a/./b",
    "a/../b",
    "%2e%2e/x",
    "x/%2E%2e/y",
    "x/.%2e/y",
    "x/%2e/y",
    "x\u0000y",
    "x\u0001y",
    "x\u007fy",
    "x y",
    "x y",
  ])("refuses %j", (rel) => {
    expect(kbGithubUrlPath(rel)).toBeNull();
  });

  it("refuses a path longer than maxLength", () => {
    expect(kbGithubUrlPath("a".repeat(11), 10)).toBeNull();
    expect(kbGithubUrlPath("a".repeat(10), 10)).toBe(`knowledge-base/${"a".repeat(10)}`);
  });

  it.each([
    ["engineering/architecture/diagrams", "knowledge-base/engineering/architecture/diagrams"],
    ["My Docs/café.pdf", "knowledge-base/My%20Docs/caf%C3%A9.pdf"],
    ["C# notes?.png", "knowledge-base/C%23%20notes%3F.png"],
    ["a\\..\\b", "knowledge-base/a%5C..%5Cb"],
    ["50%/x", "knowledge-base/50%25/x"],
    ["...", "knowledge-base/..."],
    [".hidden/v1.2", "knowledge-base/.hidden/v1.2"],
  ])("encodes %j per segment", (rel, expected) => {
    expect(kbGithubUrlPath(rel)).toBe(expected);
  });

  it("every accepted output stays under /contents/knowledge-base/ with no query or fragment", () => {
    for (const rel of ["a b/c", "C# notes?.png", "a\\..\\b", "50%/x", "x/%252e%252e"]) {
      const out = kbGithubUrlPath(rel);
      expect(out).not.toBeNull();
      const url = new URL(`https://api.github.com/repos/o/r/contents/${out}`);
      expect(url.pathname.startsWith("/repos/o/r/contents/knowledge-base/")).toBe(true);
      expect(url.search).toBe("");
      expect(url.hash).toBe("");
    }
  });

  it("kbPathSegments returns the raw segments for JSON bodies", () => {
    expect(kbPathSegments("My Docs/café.pdf")).toEqual(["My Docs", "café.pdf"]);
  });
});
