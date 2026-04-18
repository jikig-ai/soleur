import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { resolve } from "path";
import { existsSync } from "fs";

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
  return await import(`${COMMUNITY_STATS_DATA}?t=${Date.now()}-${Math.random()}`);
}

describe("communityStats.js data file", () => {
  beforeEach(() => {
    delete process.env.CI;
  });

  afterEach(() => {
    restoreEnv();
  });

  test("file exists", () => {
    expect(existsSync(COMMUNITY_STATS_DATA)).toBe(true);
  });

  test("returns Discord member/online counts when invite API responds 200", async () => {
    globalThis.fetch = (async (url: string) => {
      if (url.includes("api.github.com")) {
        return new Response(
          JSON.stringify({
            stargazers_count: 6,
            forks_count: 1,
            open_issues_count: 0,
          }),
          { status: 200 },
        );
      }
      if (url.includes("discord.com/api/")) {
        return new Response(
          JSON.stringify({
            approximate_member_count: 125,
            approximate_presence_count: 32,
          }),
          { status: 200 },
        );
      }
      return new Response("[]", { status: 200 });
    }) as typeof fetch;

    const mod = await freshImport();
    const data = await mod.default();
    expect(data.discord).toEqual({ members: 125, online: 32 });
    // Must also include GitHub stats pass-through
    expect(data.stars).toBe(6);
  });

  test("falls back to discord:null when Discord API fails (even in CI — soft dep)", async () => {
    process.env.CI = "true";
    globalThis.fetch = (async (url: string) => {
      if (url.includes("api.github.com")) {
        return new Response(
          JSON.stringify({
            stargazers_count: 6,
            forks_count: 1,
            open_issues_count: 0,
          }),
          { status: 200 },
        );
      }
      if (url.includes("discord.com/api/")) {
        throw new Error("discord down");
      }
      return new Response("[]", { status: 200 });
    }) as typeof fetch;

    const mod = await freshImport();
    const data = await mod.default();
    expect(data.discord).toBe(null);
    expect(data.stars).toBe(6);
  });

  test("falls back to discord:null when Discord returns non-200", async () => {
    globalThis.fetch = (async (url: string) => {
      if (url.includes("api.github.com")) {
        return new Response(
          JSON.stringify({
            stargazers_count: 6,
            forks_count: 1,
            open_issues_count: 0,
          }),
          { status: 200 },
        );
      }
      if (url.includes("discord.com/api/")) {
        return new Response("rate limited", { status: 429 });
      }
      return new Response("[]", { status: 200 });
    }) as typeof fetch;

    const mod = await freshImport();
    const data = await mod.default();
    expect(data.discord).toBe(null);
  });
});
