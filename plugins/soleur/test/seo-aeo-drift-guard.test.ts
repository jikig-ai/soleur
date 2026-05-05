// SEO/AEO drift-guard — enforces the on-page markup invariants closed by
// #2707 (visible FAQ matches FAQPage JSON-LD on /pricing/),
// #2708 (homepage <title> scoped to marketing brand, not Next.js dashboard),
// #2709 (brand-anchored <title> on pricing/community/blog — no bare single words),
// #2711 (inline author card + extended Person JSON-LD on every blog post).
//
// Test harness: bun:test (matches sibling tests in plugins/soleur/test/*.ts).
// Build: runs `npx @11ty/eleventy` into a tmp output dir so each test invocation
// produces a fresh build (mirrors plugins/soleur/test/jsonld-escaping.test.ts).
// Set SEO_AEO_SKIP_BUILD=1 to reuse an existing _site/ at repo root (rare —
// only useful for iterative local debugging of the drift-guard itself).

import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { resolve, join } from "path";
import {
  existsSync,
  readFileSync,
  readdirSync,
  statSync,
  mkdtempSync,
  rmSync,
} from "fs";
import { tmpdir } from "os";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SITE_JSON = resolve(
  REPO_ROOT,
  "plugins/soleur/docs/_data/site.json",
);
const INDEX_NJK = resolve(REPO_ROOT, "plugins/soleur/docs/index.njk");
const LAYOUT_TSX = resolve(
  REPO_ROOT,
  "apps/web-platform/app/layout.tsx",
);
const BLOG_POSTS_DIR = resolve(REPO_ROOT, "plugins/soleur/docs/blog");

// Google SERP snippet guidance: truncation begins ~155 chars on desktop,
// ~120 on mobile. Window matches the drift-guard envelope used by #2808.
const SERP_META_MIN = 120;
const SERP_META_MAX = 160;

let SITE: string;
let tmpSite: string | null = null;

beforeAll(() => {
  if (process.env.SEO_AEO_SKIP_BUILD === "1") {
    SITE = resolve(REPO_ROOT, "_site");
    if (!existsSync(SITE)) {
      throw new Error(
        "SEO_AEO_SKIP_BUILD=1 set but _site/ not found. Run `npx @11ty/eleventy` first.",
      );
    }
    return;
  }
  tmpSite = mkdtempSync(join(tmpdir(), "seo-aeo-drift-"));
  SITE = tmpSite;
  const proc = Bun.spawnSync(
    ["npx", "@11ty/eleventy", `--output=${tmpSite}`],
    { cwd: REPO_ROOT, stdout: "inherit", stderr: "inherit" },
  );
  if (proc.exitCode !== 0) {
    throw new Error(
      `Eleventy build failed in test setup (exit ${proc.exitCode}). Run 'npx @11ty/eleventy' from repo root to reproduce.`,
    );
  }
}, 60_000);

afterAll(() => {
  if (tmpSite) {
    rmSync(tmpSite, { recursive: true, force: true });
  }
});

// -- helpers ---------------------------------------------------------------

const JSONLD_BLOCK_RE =
  /<script type="application\/ld\+json">([\s\S]*?)<\/script>/g;

function readSite(relPath: string): string {
  const abs = resolve(SITE, relPath);
  if (!existsSync(abs)) {
    throw new Error(
      `Expected built file missing: ${abs}. Did Eleventy build succeed?`,
    );
  }
  return readFileSync(abs, "utf8");
}

function jsonLdBlockBodies(html: string): string[] {
  // Reset regex lastIndex because the global flag shares state across calls.
  return [...html.matchAll(JSONLD_BLOCK_RE)].map((m) => m[1]);
}

function jsonLdBlocks(html: string): unknown[] {
  return jsonLdBlockBodies(html).map((body) => JSON.parse(body));
}

function extractTitle(html: string): string {
  const m = html.match(/<title>([\s\S]*?)<\/title>/);
  if (!m) throw new Error("no <title> in HTML");
  return m[1].trim();
}

function extractFrontMatterSeoTitle(njkPath: string): string | null {
  const src = readFileSync(njkPath, "utf8");
  const m = src.match(/^---\n([\s\S]*?)\n---/);
  if (!m) return null;
  const fm = m[1];
  // seoTitle can be bare or quoted (single, double). Capture the raw value.
  const line = fm.match(/^seoTitle:\s*(.+)$/m);
  if (!line) return null;
  let v = line[1].trim();
  if (
    (v.startsWith('"') && v.endsWith('"')) ||
    (v.startsWith("'") && v.endsWith("'"))
  ) {
    v = v.slice(1, -1);
  }
  return v;
}

function walkHtmlFiles(dir: string): string[] {
  const out: string[] = [];
  if (!existsSync(dir)) return out;
  for (const ent of readdirSync(dir)) {
    const full = join(dir, ent);
    const st = statSync(full);
    if (st.isDirectory()) out.push(...walkHtmlFiles(full));
    else if (st.isFile() && full.endsWith(".html")) out.push(full);
  }
  return out;
}

// -- Test 1: pricing FAQ parity -------------------------------------------

describe("#2707 pricing FAQ — visible <details> matches FAQPage JSON-LD", () => {
  test("JSON-LD mainEntity count equals visible <details class=\"faq-item\"> count and every name has a <summary>", () => {
    const html = readSite("pricing/index.html");
    const blocks = jsonLdBlocks(html);
    const faq = blocks.find(
      (b): b is { "@type": string; mainEntity: { name: string }[] } =>
        typeof b === "object" &&
        b !== null &&
        (b as { "@type"?: string })["@type"] === "FAQPage",
    );
    expect(faq).toBeDefined();
    const summaries = [
      ...html.matchAll(
        /<summary class="faq-question">([\s\S]*?)<\/summary>/g,
      ),
    ].map((m) => m[1].replace(/<[^>]+>/g, "").trim());
    const detailsCount = [
      ...html.matchAll(/<details class="faq-item">/g),
    ].length;
    const names = faq!.mainEntity.map((q) => q.name.trim());
    expect(detailsCount).toBe(names.length);
    expect(summaries.length).toBe(names.length);
    for (const name of names) {
      expect(summaries).toContain(name);
    }
  });
});

// -- Test 2: brand-anchored <title> --------------------------------------

describe("#2709 <title> is brand-anchored on pricing/community/blog + index", () => {
  const pages = [
    "index.html",
    "pricing/index.html",
    "community/index.html",
    "blog/index.html",
  ];
  const bareBanned = new Set(["Pricing", "Community", "Blog"]);

  for (const p of pages) {
    test(`${p} <title> contains "Soleur" and a separator, not a bare single word`, () => {
      const html = readSite(p);
      const t = extractTitle(html);
      expect(t).toContain("Soleur");
      expect(t.includes("—") || t.includes("|") || t.includes(" - ")).toBe(
        true,
      );
      expect(bareBanned.has(t)).toBe(false);
    });
  }
});

// -- Test 3: homepage <title> equals seoTitle string exactly --------------

describe("#2708 homepage <title> matches docs/index.njk seoTitle exactly", () => {
  test("exact string match", () => {
    const html = readSite("index.html");
    const t = extractTitle(html);
    const expected = extractFrontMatterSeoTitle(INDEX_NJK);
    expect(expected).toBeTruthy();
    expect(t).toBe(expected!);
  });
});

// -- Test 4: inline author card + extended Person JSON-LD on blog posts ---

describe("#2711 blog posts render author card + extended Person JSON-LD", () => {
  // Load the canonical sameAs array from site.json so the drift-guard
  // pins the exact post-state (cq-mutation-assertions-pin-exact-post-state).
  // Evaluated lazily inside each test to avoid running before beforeAll.
  const site = () =>
    JSON.parse(readFileSync(SITE_JSON, "utf8")) as {
      author: { sameAs: string[] };
    };

  test("at least one blog post rendered", () => {
    const blogDir = resolve(SITE, "blog");
    const entries = existsSync(blogDir)
      ? readdirSync(blogDir).filter((e) => {
          const p = join(blogDir, e);
          const idx = join(p, "index.html");
          if (!statSync(p).isDirectory() || !existsSync(idx)) return false;
          const body = readFileSync(idx, "utf8");
          if (body.length < 2000 && /<meta\s+http-equiv="refresh"/i.test(body)) {
            return false;
          }
          return true;
        })
      : [];
    expect(entries.length).toBeGreaterThan(0);
  });

  test("every blog post: author-card DOM + Person JSON-LD image exists on disk + sameAs pins site.json exactly", () => {
    const blogDir = resolve(SITE, "blog");
    const entries = existsSync(blogDir)
      ? readdirSync(blogDir).filter((e) => {
          const p = join(blogDir, e);
          const idx = join(p, "index.html");
          if (!statSync(p).isDirectory() || !existsSync(idx)) return false;
          const body = readFileSync(idx, "utf8");
          if (body.length < 2000 && /<meta\s+http-equiv="refresh"/i.test(body)) {
            return false;
          }
          return true;
        })
      : [];
    const expectedSameAs = site().author.sameAs;

    for (const slug of entries) {
      const html = readSite(`blog/${slug}/index.html`);

      // Author card DOM (flat-hyphen convention — see commit 3)
      expect(html, `${slug}: author-card class`).toContain(
        'class="author-card"',
      );
      const imgMatch = html.match(
        /<img[^>]+src="(\/images\/jean-deruelle\.(?:jpg|png|svg))"/,
      );
      expect(imgMatch, `${slug}: author-card img src`).not.toBeNull();
      // Pinned existence of the referenced asset on disk — catches the
      // case where site.json references an image whose file was deleted.
      const imgPath = imgMatch![1].replace(/^\//, "");
      const absImg = resolve(SITE, imgPath);
      expect(
        existsSync(absImg),
        `${slug}: author-card asset ${imgMatch![1]} missing from _site/`,
      ).toBe(true);

      // BlogPosting JSON-LD with Person author extended with image + sameAs
      const blocks = jsonLdBlocks(html);
      const post = blocks.find(
        (b): b is {
          "@type": string;
          author: {
            "@type": string;
            image?: string;
            sameAs?: string[];
          };
        } =>
          typeof b === "object" &&
          b !== null &&
          (b as { "@type"?: string })["@type"] === "BlogPosting",
      );
      expect(post, `${slug}: BlogPosting JSON-LD block`).toBeDefined();
      expect(post!.author["@type"]).toBe("Person");
      expect(typeof post!.author.image).toBe("string");
      expect(post!.author.image!.length).toBeGreaterThan(0);
      // Deep equality in order — prevents silent shrinkage or reordering.
      expect(post!.author.sameAs).toEqual(expectedSameAs);
    }
  });
});

// -- Test 5: every JSON-LD block parses as valid JSON --------------------

describe("all <script type=\"application/ld+json\"> blocks parse as valid JSON", () => {
  test("no malformed JSON-LD anywhere in _site", () => {
    const files = walkHtmlFiles(SITE);
    expect(files.length).toBeGreaterThan(0);
    const failures: { file: string; err: string; snippet: string }[] = [];
    for (const f of files) {
      const html = readFileSync(f, "utf8");
      // Reuse the shared extractor (jsonLdBlockBodies) + try/catch per-block
      // so failures accumulate across the whole site rather than aborting on
      // the first bad block.
      for (const body of jsonLdBlockBodies(html)) {
        try {
          JSON.parse(body);
        } catch (e) {
          failures.push({
            file: f,
            err: (e as Error).message,
            snippet: body.slice(0, 200),
          });
        }
      }
    }
    if (failures.length > 0) {
      const msg = failures
        .map((f) => `${f.file}: ${f.err}\n  ${f.snippet}`)
        .join("\n");
      throw new Error(`Invalid JSON-LD in ${failures.length} block(s):\n${msg}`);
    }
  });
});

// -- Test 6: #2807 blog listing cards render per-entry byline -------------

describe("#2807 blog listing cards render per-entry byline", () => {
  test("every <a class=\"component-card\"> on /blog/ renders one <p class=\"card-byline\">by …</p>", () => {
    const html = readSite("blog/index.html");
    const cards = [...html.matchAll(/<a\s+[^>]*class="component-card"/g)].length;
    const bylines = [...html.matchAll(/<p\s+class="card-byline">by\s/g)].length;
    // Derive expected minimum from the source of truth on disk: the number
    // of blog `.md` files. Posts tagged in multiple categories render once
    // per matching section, so cards >= postCount is the tight floor.
    const postCount = readdirSync(BLOG_POSTS_DIR).filter((f) =>
      f.endsWith(".md"),
    ).length;
    expect(postCount).toBeGreaterThan(0);
    expect(cards).toBeGreaterThanOrEqual(postCount);
    expect(bylines).toBe(cards);
  });
});

// -- Test 7: #2808 homepage meta description SERP-safe + keyword-dense -----

describe("#2808 homepage meta description is SERP-safe + keyword-dense", () => {
  test("<meta name=\"description\"> length within SERP window and contains primary keywords", () => {
    const html = readSite("index.html");
    const m = html.match(
      /<meta\s+name="description"\s+content="([^"]+)"/i,
    );
    expect(m, "homepage has <meta name=\"description\">").not.toBeNull();
    const content = m![1];
    expect(content.length).toBeLessThanOrEqual(SERP_META_MAX);
    expect(content.length).toBeGreaterThanOrEqual(SERP_META_MIN);
    const lower = content.toLowerCase();
    expect(lower).toContain("solo founder");
    // Use word-boundary match so "agentic"/"reagent" etc. do not pass this
    // keyword-density assertion in place of "agent"/"agents".
    expect(/\bagents?\b/.test(lower)).toBe(true);
    expect(lower).toContain("department");
  });
});

// -- Test 8: Next.js layout title is dashboard-scoped (prevent #2708) -----

describe("#2708 — Next.js layout title is dashboard-scoped", () => {
  test("apps/web-platform/app/layout.tsx uses dashboard template + default, not marketing brand", () => {
    const src = readFileSync(LAYOUT_TSX, "utf8");
    // Must NOT contain the old marketing brand string that leaked onto
    // marketing routes (the original #2708 regression).
    expect(src).not.toContain("One Command Center, 8 Departments");
    // Must use the dashboard-scoped template.
    expect(src).toContain("%s — Soleur Dashboard");
    // Must use the dashboard default title. PR #3240 (PR-A pre-flight)
    // dropped the "— Your Command Center" suffix when the brand rename
    // collapsed the surface to "Soleur Dashboard"; the dashboard-scoped
    // shape is preserved and the regression class (#2708 marketing-brand
    // leak) remains guarded by the negative assertion above.
    expect(src).toContain('default: "Soleur Dashboard"');
  });
});
