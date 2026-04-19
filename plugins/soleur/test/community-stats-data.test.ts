import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { resolve } from "path";
import { existsSync } from "fs";
import communityStats from "../docs/_data/communityStats.js";
import githubStats from "../docs/_data/githubStats.js";

const __resetGithubCache = githubStats.__resetCache;

const COMMUNITY_STATS_DATA = resolve(
  import.meta.dir,
  "../docs/_data/communityStats.js",
);

const ORIGINAL_CI = process.env.CI;
const ORIGINAL_FETCH = globalThis.fetch;

function restoreEnv() {
  if (ORIGINAL_CI === undefined) delete process.env.CI;
  else process.env.CI = ORIGINAL_CI;
  globalThis.fetch = ORIGINAL_FETCH;
}

async function freshImport() {
  return await import(
    `${COMMUNITY_STATS_DATA}?t=${Date.now()}-${Math.random()}`
  );
}

describe("communityStats.js data file", () => {
  beforeEach(() => {
    delete process.env.CI;
    __resetGithubCache();
  });

  afterEach(() => {
    restoreEnv();
    __resetGithubCache();
  });

  test("file exists", () => {
    expect(existsSync(COMMUNITY_STATS_DATA)).toBe(true);
  });

  test("returns Discord member/online counts when invite API responds 200", async () => {
    globalThis.fetch = (async (url: string) => {
      if (url.includes("discord.com/api/")) {
        return new Response(
          JSON.stringify({
            approximate_member_count: 125,
            approximate_presence_count: 32,
          }),
          { status: 200 },
        );
      }
      return new Response("not-used", { status: 200 });
    }) as typeof fetch;

    const mod = await freshImport();
    const data = await mod.default();
    expect(data).toEqual({ discord: { members: 125, online: 32 } });
  });

  test("falls back to discord:null when Discord API fails (even in CI — soft dep)", async () => {
    process.env.CI = "true";
    globalThis.fetch = (async (url: string) => {
      if (url.includes("discord.com/api/")) {
        throw new Error("discord down");
      }
      return new Response("not-used", { status: 200 });
    }) as typeof fetch;

    const mod = await freshImport();
    const data = await mod.default();
    expect(data).toEqual({ discord: null });
  });

  test("falls back to discord:null when Discord returns non-200", async () => {
    globalThis.fetch = (async (url: string) => {
      if (url.includes("discord.com/api/")) {
        return new Response("rate limited", { status: 429 });
      }
      return new Response("not-used", { status: 200 });
    }) as typeof fetch;

    const mod = await freshImport();
    const data = await mod.default();
    expect(data.discord).toBe(null);
  });

  test("does not leak GitHub stats into the returned shape", async () => {
    // After scope narrowing, consumers read githubStats.stars directly; the
    // community module returns Discord only to avoid duplicate-source drift.
    globalThis.fetch = (async (url: string) => {
      if (url.includes("discord.com/api/")) {
        return new Response(
          JSON.stringify({
            approximate_member_count: 42,
            approximate_presence_count: 10,
          }),
          { status: 200 },
        );
      }
      return new Response("not-used", { status: 200 });
    }) as typeof fetch;

    const mod = await freshImport();
    const data = await mod.default();
    expect(Object.keys(data).sort()).toEqual(["discord"]);
    expect("stars" in data).toBe(false);
  });

  // Note: not testing communityStats() behavior via static import here —
  // consumer contract is covered by the freshImport tests above, and the
  // static direct import is used by sibling tests in this repo.
  test("communityStats default export is callable via static import", async () => {
    // Sanity-check the static import wiring so a rename or signature drift
    // fails this test instead of silently breaking Eleventy at build time.
    expect(typeof communityStats).toBe("function");
  });
});
