import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { readFileSync } from "fs";
import { resolve } from "path";

import github from "../docs/_data/github.js";
import pluginData from "../docs/_data/plugin.js";

// The plugin manifest no longer carries a `version` key (the `0.0.0-dev` frozen
// sentinel was removed — plugin identity is the source commit SHA now). That
// makes `plugin.version` in the docs data layer come from `github()` alone, and
// `github()` has THREE paths that yield `version: null`:
//
//   1. the SOLEUR_DOCS_OFFLINE=1 hermetic-build hatch
//   2. the fetch `catch` arm (non-CI fallback) — a transient GitHub API failure
//   3. the no-release `?? null` (no published releases, or all drafts)
//
// `_includes/base.njk` renders `{{ plugin.version | jsonLdSafe | safe }}`, and
// `jsonLdSafe` is `JSON.stringify(value).replace(...)` — on `undefined`,
// `JSON.stringify` returns the *value* `undefined` and `.replace` throws. So an
// unguarded `plugin.version` is a hard build failure, not a degraded page.
// These tests pin the guard against all three null paths.

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const PLUGIN_MANIFEST = resolve(
  REPO_ROOT,
  "plugins/soleur/.claude-plugin/plugin.json",
);
const MARKETPLACE_MANIFEST = resolve(REPO_ROOT, ".claude-plugin/marketplace.json");
const GITHUB_DATA = resolve(import.meta.dir, "../docs/_data/github.js");

// Bun test runs all files in a single OS process — capture originals and restore
// to avoid leaking env mutations to sibling test files.
// See: knowledge-base/project/learnings/test-failures/2026-04-18-bun-test-env-var-leak-across-files-single-process.md
const ORIGINAL_CI = process.env.CI;
const ORIGINAL_OFFLINE = process.env.SOLEUR_DOCS_OFFLINE;
const ORIGINAL_TOKEN = process.env.GITHUB_TOKEN;
const ORIGINAL_FETCH = globalThis.fetch;

function restoreEnv() {
  if (ORIGINAL_CI === undefined) delete process.env.CI;
  else process.env.CI = ORIGINAL_CI;
  if (ORIGINAL_OFFLINE === undefined) delete process.env.SOLEUR_DOCS_OFFLINE;
  else process.env.SOLEUR_DOCS_OFFLINE = ORIGINAL_OFFLINE;
  if (ORIGINAL_TOKEN === undefined) delete process.env.GITHUB_TOKEN;
  else process.env.GITHUB_TOKEN = ORIGINAL_TOKEN;
  globalThis.fetch = ORIGINAL_FETCH;
}

// A query-suffixed dynamic import gives a *fresh* module instance, so each arm
// starts with an empty module-scope `cached`.
async function freshGithub(arm: string) {
  const mod = await import(`${GITHUB_DATA}?arm=${arm}`);
  return mod.default as () => Promise<{ version: string | null }>;
}

function readJson(path: string) {
  return JSON.parse(readFileSync(path, "utf-8"));
}

describe("plugin version with no manifest sentinel", () => {
  beforeEach(() => {
    delete process.env.CI;
    delete process.env.SOLEUR_DOCS_OFFLINE;
    delete process.env.GITHUB_TOKEN;
    github.__resetCache();
  });

  afterEach(() => {
    restoreEnv();
    github.__resetCache();
  });

  test("plugin.json carries no version key", () => {
    const manifest = readJson(PLUGIN_MANIFEST);
    expect(Object.hasOwn(manifest, "version")).toBe(false);
    // The delete must be surgical — mcpServers is consumed by
    // session-rules-loader.sh and agent-runner.ts.
    expect(Object.hasOwn(manifest, "mcpServers")).toBe(true);
  });

  test("marketplace.json plugin entry has no version, manifest-format version intact", () => {
    const marketplace = readJson(MARKETPLACE_MANIFEST);
    expect(Object.hasOwn(marketplace.plugins[0], "version")).toBe(false);
    // Top-level `version` is the manifest-format version — a different field
    // with a different meaning. It must survive.
    expect(marketplace.version).toBe("1.0.0");
  });

  test("github.js yields version null on the offline hatch", async () => {
    process.env.SOLEUR_DOCS_OFFLINE = "1";
    const data = await (await freshGithub("offline"))();
    expect(data.version).toBe(null);
  });

  test("github.js yields version null on the fetch catch arm (CI unset)", async () => {
    globalThis.fetch = (async () => {
      throw new Error("network down");
    }) as typeof fetch;
    const data = await (await freshGithub("catch"))();
    expect(data.version).toBe(null);
  });

  test("github.js yields version null when there is no published release", async () => {
    globalThis.fetch = (async () =>
      new Response("[]", { status: 200 })) as typeof fetch;
    const data = await (await freshGithub("norelease"))();
    expect(data.version).toBe(null);
  });

  test("plugin.js yields a usable version when github() returns null (catch arm)", async () => {
    globalThis.fetch = (async () => {
      throw new Error("GitHub API 503");
    }) as typeof fetch;

    const plugin = await pluginData();

    expect(typeof plugin.version).toBe("string");
    expect(plugin.version).toBe("unknown");
    // The jsonLdSafe contract: JSON.stringify must return a string, not the
    // value `undefined`, or base.njk's filter chain throws mid-build.
    expect(typeof JSON.stringify(plugin.version)).toBe("string");
  });

  test("plugin.js yields a usable version on the offline hatch", async () => {
    process.env.SOLEUR_DOCS_OFFLINE = "1";

    const plugin = await pluginData();

    expect(plugin.version).toBe("unknown");
    expect(typeof JSON.stringify(plugin.version)).toBe("string");
  });

  test("plugin.js prefers the live release version when github() has one", async () => {
    globalThis.fetch = (async () =>
      new Response(JSON.stringify([{ tag_name: "v1.2.3", body: "", published_at: "2026-08-12T00:00:00Z" }]), {
        status: 200,
      })) as typeof fetch;

    const plugin = await pluginData();

    expect(plugin.version).toBe("1.2.3");
  });
});
