import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { resolve } from "path";
import { existsSync } from "fs";
import githubStats from "../docs/_data/githubStats.js";

const __resetCache = githubStats.__resetCache;

const GITHUB_STATS_DATA = resolve(
  import.meta.dir,
  "../docs/_data/githubStats.js",
);

// Bun test runs all files in a single OS process — capture originals and restore
// to avoid leaking env mutations to sibling test files.
// See: knowledge-base/project/learnings/test-failures/2026-04-18-bun-test-env-var-leak-across-files-single-process.md
const ORIGINAL_CI = process.env.CI;
const ORIGINAL_GH_TOKEN = process.env.GITHUB_TOKEN;
const ORIGINAL_FETCH = globalThis.fetch;

function restoreEnv() {
  if (ORIGINAL_CI === undefined) delete process.env.CI;
  else process.env.CI = ORIGINAL_CI;
  if (ORIGINAL_GH_TOKEN === undefined) delete process.env.GITHUB_TOKEN;
  else process.env.GITHUB_TOKEN = ORIGINAL_GH_TOKEN;
  globalThis.fetch = ORIGINAL_FETCH;
}

describe("githubStats.js data file", () => {
  beforeEach(() => {
    delete process.env.CI;
    delete process.env.GITHUB_TOKEN;
    __resetCache();
  });

  afterEach(() => {
    restoreEnv();
    __resetCache();
  });

  test("file exists", () => {
    expect(existsSync(GITHUB_STATS_DATA)).toBe(true);
  });

  test("returns stars/forks/contributors/openIssues shape on success", async () => {
    globalThis.fetch = (async (url: string) => {
      if (url.includes("/contributors")) {
        return new Response("[{}]", {
          status: 200,
          headers: {
            link: '<https://api.github.com/repositories/1/contributors?per_page=1&page=5>; rel="last"',
          },
        });
      }
      return new Response(
        JSON.stringify({
          stargazers_count: 42,
          forks_count: 3,
          open_issues_count: 12,
        }),
        { status: 200 },
      );
    }) as typeof fetch;

    const data = await githubStats();
    expect(data).toEqual({
      stars: 42,
      forks: 3,
      openIssues: 12,
      contributors: 5,
    });
  });

  test("sends Authorization header when GITHUB_TOKEN is set", async () => {
    process.env.GITHUB_TOKEN = "secret-token";
    const seenHeaders: Array<Record<string, string>> = [];
    globalThis.fetch = (async (url: string, init?: RequestInit) => {
      seenHeaders.push((init?.headers as Record<string, string>) ?? {});
      if (url.includes("/contributors")) {
        return new Response("[{}]", { status: 200 });
      }
      return new Response(
        JSON.stringify({
          stargazers_count: 1,
          forks_count: 0,
          open_issues_count: 0,
        }),
        { status: 200 },
      );
    }) as typeof fetch;

    await githubStats();
    // Both fetch calls must carry Authorization with the token.
    expect(seenHeaders).toHaveLength(2);
    for (const headers of seenHeaders) {
      expect(headers.Authorization).toBe("Bearer secret-token");
    }
  });

  test("dev-mode falls back to nulls when GitHub API errors (CI unset)", async () => {
    globalThis.fetch = (async () => {
      throw new Error("network down");
    }) as typeof fetch;

    const data = await githubStats();
    expect(data).toEqual({
      stars: null,
      forks: null,
      openIssues: null,
      contributors: null,
    });
  });

  test("CI mode fails fast when GitHub API errors", async () => {
    process.env.CI = "true";
    globalThis.fetch = (async () => {
      throw new Error("boom");
    }) as typeof fetch;

    await expect(githubStats()).rejects.toThrow(
      /GitHub stats unreachable in CI/,
    );
  });

  test("CI mode fails fast on HTTP 401 (invalid token)", async () => {
    process.env.CI = "true";
    process.env.GITHUB_TOKEN = "expired-token";
    globalThis.fetch = (async () => {
      return new Response("Bad credentials", {
        status: 401,
        statusText: "Unauthorized",
      });
    }) as typeof fetch;

    await expect(githubStats()).rejects.toThrow(/401/);
  });

  test("contributors falls back to 1 when Link header is absent", async () => {
    globalThis.fetch = (async (url: string) => {
      if (url.includes("/contributors")) {
        return new Response("[{}]", { status: 200 });
      }
      return new Response(
        JSON.stringify({
          stargazers_count: 6,
          forks_count: 1,
          open_issues_count: 0,
        }),
        { status: 200 },
      );
    }) as typeof fetch;

    const data = await githubStats();
    expect(data.contributors).toBe(1);
  });
});
