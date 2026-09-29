/**
 * GitHub API egress URL guard tests (CodeQL js/request-forgery, alert #234)
 *
 * Pins the contract of server/github-url.ts — every credential-bearing GitHub
 * API request must resolve to https://api.github.com and only there — plus the
 * egress census: no `fetch(` site in github-api.ts / github-app.ts may take a
 * raw `${GITHUB_API}`-concatenated argument.
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, test, expect } from "vitest";

import {
  githubApiUrl,
  assertGithubApiAbsoluteUrl,
} from "../server/github-url";

describe("githubApiUrl", () => {
  describe("rejects a path that could rebind the request authority", () => {
    test.each([
      ["@evil.example/x", "no leading slash — @ rebinds userinfo/host"],
      [".evil.example", "no leading slash — suffix-joins the host"],
      ["evil.example/x", "no leading slash"],
      ["//evil.example/x", "scheme-relative — rebinds host entirely"],
    ])("rejects %j (%s)", (path) => {
      expect(() => githubApiUrl(path)).toThrow(/egress denied/);
    });
  });

  describe("rejects dot-segments the URL parser would resolve silently", () => {
    test.each([
      "/repos/o/../../x",
      "/a/%2e%2e/b",
      "/a/.%2E/b",
      "/a/%2E./b",
      "/a/..?state=open",
      "/a/./b",
    ])("rejects %j", (path) => {
      expect(() => githubApiUrl(path)).toThrow(/egress denied/);
    });
  });

  describe("rejects structurally unsafe path bytes", () => {
    test.each([
      ["/repos/o/r/x\\..", "backslash folds to / under WHATWG"],
      ["/repos/o/r#frag", "fragment truncates the path"],
      ["/a/\x01b", "control character"],
      ["/a/\u2028b", "unicode line separator"],
      ["", "empty"],
      [`/${"a".repeat(4097)}`, "over-length"],
    ])("rejects %j (%s)", (path) => {
      expect(() => githubApiUrl(path)).toThrow(/egress denied/);
    });
  });

  describe("accepts every current call-site path shape", () => {
    test.each([
      "/repos/o/r/issues",
      "/graphql",
      "/repos/o/r/issues?state=open&per_page=50",
      "/repos/o/r/git/ref/heads/feat/x",
      "/app/installations/12345",
      "/orgs/some-org/members/some-login",
    ])("accepts %j", (path) => {
      expect(githubApiUrl(path)).toBe(`https://api.github.com${path}`);
    });
  });
});

describe("assertGithubApiAbsoluteUrl", () => {
  test.each([
    "https://evil.example/x",
    "https://api.github.com@evil.example/x",
    "https://api.github.com.evil.example/x",
    "http://api.github.com/x",
    "https://api.github.com:444/x",
    "https://user:pw@api.github.com/x",
    "https://api.github.com/a/../b",
    "https://api.github.com/a/%2e%2e/b",
    "not a url",
  ])("rejects %j", (url) => {
    expect(() => assertGithubApiAbsoluteUrl(url)).toThrow(/egress denied/);
  });

  test("refusals carry the pinned error code taxonomy", () => {
    let caught: unknown;
    try {
      assertGithubApiAbsoluteUrl("https://evil.example/x");
    } catch (err) {
      caught = err;
    }
    expect(caught).toMatchObject({ code: "github_api_egress_denied" });
  });

  test.each([
    "https://api.github.com/repos/o/r",
    "https://api.github.com/app/installations?per_page=100",
    "https://api.github.com/app",
  ])("accepts %j", (url) => {
    expect(assertGithubApiAbsoluteUrl(url)).toBe(url);
  });
});

// ---------------------------------------------------------------------------
// Egress census — every `fetch(` site in the credential-bearing modules must
// take a guard-produced first argument: the `url` identifier (each enclosing
// scope asserts it before the call), an inline `assertGithubApiAbsoluteUrl(`,
// or the one named compile-time literal. A new raw-`${GITHUB_API}` fetch site
// — or a `fetch(` that escapes `await` (`return fetch(`, `void fetch(`,
// `.then`-chained) — fails this test.
// ---------------------------------------------------------------------------

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
// `(?<![\w.])` excludes `mockFetch(`, `fetchWithRetry(` (no paren after
// `fetch`), and member access like `globalThis.fetch(`.
const FETCH_SITE = /(?<![\w.])fetch\s*\(/g;
const NAMED_EXEMPTION = "`https://api.github.com/app`";

// A `//` that is not part of `://` starts a line comment — a `fetch(` inside
// one is prose, not a call site, and comment text inside a fetch's argument
// list is not part of its first argument.
const LINE_COMMENT = /(^|[^:])\/\/.*$/;

function isCommentSite(src: string, index: number): boolean {
  const lineStart = src.lastIndexOf("\n", index) + 1;
  return LINE_COMMENT.test(src.slice(lineStart, index));
}

function fetchSiteHeads(rel: string): string[] {
  const src = readFileSync(join(APP_ROOT, rel), "utf8");
  return [...src.matchAll(FETCH_SITE)]
    .filter((m) => !isCommentSite(src, m.index))
    .map((m) =>
      src
        .slice(m.index + m[0].length, m.index + m[0].length + 160)
        .split("\n")
        .map((line) => line.replace(LINE_COMMENT, "$1"))
        .join("\n")
        .trimStart(),
    );
}

describe("GitHub API egress census", () => {
  test.each([
    ["server/github-api.ts", 2],
    ["server/github-app.ts", 2],
    ["server/release-notes.ts", 1],
    ["server/inngest/functions/cron-weekly-release-digest.ts", 1],
  ])("%s: all %i fetch sites take a guarded url", (rel, expectedCount) => {
    const heads = fetchSiteHeads(rel);
    expect(heads.length).toBe(expectedCount);
    for (const head of heads) {
      const guarded =
        /^url[,\s)]/.test(head) ||
        head.startsWith("assertGithubApiAbsoluteUrl(") ||
        head.startsWith(NAMED_EXEMPTION);
      expect(guarded, `${rel} fetch() first arg ${JSON.stringify(head.slice(0, 60))}`).toBe(true);
    }
  });
});
