import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { mkdtempSync, rmSync, readFileSync, readdirSync, statSync } from "fs";
import { tmpdir } from "os";
import { join, resolve } from "path";

const REPO_ROOT = resolve(import.meta.dir, "..", "..", "..");
const FIXTURE_CONFIG = "plugins/soleur/test/fixtures/jsonld-escaping/eleventy.config.js";

const WEAPONIZED_TITLE = 'A "quoted" title with \\ and <tag> and & ampersand';
const WEAPONIZED_DESC = 'Line one with "quotes" and \\ backslash\nLine two with <tag> and & ampersand';

const FORBIDDEN_ENTITIES = ["&quot;", "&amp;", "&lt;", "&gt;", "&#39;"];
const EXTRACT_JSONLD = /<script type="application\/ld\+json">([\s\S]*?)<\/script>/g;

let outputDir: string;
let homepageHtml: string;
let blogPostHtml: string;

beforeAll(() => {
  outputDir = mkdtempSync(join(tmpdir(), "jsonld-test-"));
  const proc = Bun.spawnSync(
    ["npx", "@11ty/eleventy", `--config=${FIXTURE_CONFIG}`, `--output=${outputDir}`],
    { cwd: REPO_ROOT },
  );
  if (proc.exitCode !== 0) {
    throw new Error(
      `Eleventy fixture build failed (exit ${proc.exitCode}):\n${new TextDecoder().decode(proc.stderr)}`,
    );
  }
  homepageHtml = readFileSync(join(outputDir, "index.html"), "utf8");
  blogPostHtml = readFileSync(join(outputDir, "blog", "test-post", "index.html"), "utf8");
});

afterAll(() => {
  rmSync(outputDir, { recursive: true, force: true });
});

function extractBlocks(html: string): string[] {
  return [...html.matchAll(EXTRACT_JSONLD)].map((m) => m[1]);
}

describe("JSON-LD escaping (#2609)", () => {
  test("homepage JSON-LD blocks JSON.parse without throwing", () => {
    const blocks = extractBlocks(homepageHtml);
    expect(blocks.length).toBeGreaterThan(0);
    for (const body of blocks) {
      expect(() => JSON.parse(body)).not.toThrow();
    }
  });

  test("blog-post JSON-LD blocks JSON.parse without throwing", () => {
    const blocks = extractBlocks(blogPostHtml);
    expect(blocks.length).toBeGreaterThan(0);
    for (const body of blocks) {
      expect(() => JSON.parse(body)).not.toThrow();
    }
  });

  test("blog-post headline and description round-trip byte-for-byte", () => {
    const blocks = extractBlocks(blogPostHtml).map((b) => JSON.parse(b));
    const bp = blocks.find((b) => b["@type"] === "BlogPosting");
    expect(bp).toBeDefined();
    // pin exact post-state (cq-mutation-assertions-pin-exact-post-state)
    expect(bp.headline).toBe(WEAPONIZED_TITLE);
    expect(bp.description).toBe(WEAPONIZED_DESC);
  });

  test("no HTML entity leaks inside any JSON-LD block (drift-guard)", () => {
    const blocks = [...extractBlocks(homepageHtml), ...extractBlocks(blogPostHtml)];
    for (const body of blocks) {
      for (const ent of FORBIDDEN_ENTITIES) {
        expect(body).not.toContain(ent);
      }
    }
  });

  test("no retained-outer-quote bug (empty-string-field drift-guard)", () => {
    // Catches `"name": ""value""` mistake from forgetting to drop outer quotes.
    const blocks = [...extractBlocks(homepageHtml), ...extractBlocks(blogPostHtml)];
    const emptyField = /"[a-zA-Z_@]+":\s*""/;
    for (const body of blocks) {
      expect(body).not.toMatch(emptyField);
    }
  });

  test("every JSON-LD interpolation in all docs templates uses | dump | safe", () => {
    const blockRe = /<script type="application\/ld\+json">([\s\S]*?)<\/script>/g;
    const sources = walkNjkFiles(resolve(REPO_ROOT, "plugins/soleur/docs"));
    let totalBlocks = 0;
    for (const path of sources) {
      const src = readFileSync(path, "utf8");
      for (const blockMatch of src.matchAll(blockRe)) {
        totalBlocks++;
        const body = blockMatch[1];
        const interps = [...body.matchAll(/\{\{[^}]*\}\}/g)].map((m) => m[0]);
        for (const interp of interps) {
          expect(interp, `${path} interpolation ${interp}`).toMatch(
            /\|\s*dump\s*\|\s*safe/,
          );
        }
      }
    }
    // Sanity: glob must find at least the two known templates, else the
    // guard silently passes by scanning zero files.
    expect(totalBlocks).toBeGreaterThanOrEqual(2);
  });
});

function walkNjkFiles(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    const s = statSync(p);
    if (s.isDirectory()) out.push(...walkNjkFiles(p));
    else if (entry.endsWith(".njk")) out.push(p);
  }
  return out;
}
