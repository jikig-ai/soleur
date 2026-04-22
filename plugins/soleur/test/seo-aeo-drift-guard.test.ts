// SEO/AEO drift-guard — enforces the on-page markup invariants closed by
// #2707 (visible FAQ matches FAQPage JSON-LD on /pricing/),
// #2708 (homepage <title> scoped to marketing brand, not Next.js dashboard),
// #2709 (brand-anchored <title> on pricing/community/blog — no bare single words),
// #2711 (inline author card + extended Person JSON-LD on every blog post).
//
// Test harness: bun:test (matches sibling tests in plugins/soleur/test/*.ts).
// Build gating: if _site/ is absent, runs `npx @11ty/eleventy` from the repo
// root (see eleventy.config.js INPUT constant — build MUST run from repo root
// per learning 2026-03-15-eleventy-build-must-run-from-repo-root.md).

import { describe, test, expect, beforeAll } from "bun:test";
import { resolve, join } from "path";
import { existsSync, readFileSync, readdirSync, statSync } from "fs";
import { spawnSync } from "child_process";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SITE = resolve(REPO_ROOT, "_site");
const INDEX_NJK = resolve(REPO_ROOT, "plugins/soleur/docs/index.njk");

beforeAll(() => {
  if (!existsSync(SITE)) {
    const res = spawnSync("npx", ["@11ty/eleventy"], {
      cwd: REPO_ROOT,
      stdio: "inherit",
    });
    if (res.status !== 0) {
      throw new Error(
        `Eleventy build failed in test setup (exit ${res.status}). Run 'npx @11ty/eleventy' from repo root to reproduce.`,
      );
    }
  }
});

// -- helpers ---------------------------------------------------------------

function readSite(relPath: string): string {
  const abs = resolve(SITE, relPath);
  if (!existsSync(abs)) {
    throw new Error(
      `Expected built file missing: ${abs}. Did Eleventy build succeed?`,
    );
  }
  return readFileSync(abs, "utf8");
}

function jsonLdBlocks(html: string): unknown[] {
  const re = /<script type="application\/ld\+json">([\s\S]*?)<\/script>/g;
  const out: unknown[] = [];
  for (const m of html.matchAll(re)) {
    out.push(JSON.parse(m[1]));
  }
  return out;
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
  const blogDir = resolve(SITE, "blog");
  const entries = existsSync(blogDir)
    ? readdirSync(blogDir).filter((e) => {
        const p = join(blogDir, e);
        return statSync(p).isDirectory() && existsSync(join(p, "index.html"));
      })
    : [];

  test("at least one blog post rendered", () => {
    expect(entries.length).toBeGreaterThan(0);
  });

  for (const slug of entries) {
    test(`${slug}: author-card DOM + Person JSON-LD with image+sameAs`, () => {
      const html = readSite(`blog/${slug}/index.html`);
      // Author card DOM
      expect(html).toContain('class="author-card"');
      expect(html).toMatch(/<img[^>]+src="\/images\/jean-deruelle\.(jpg|png|svg)"/);
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
      expect(post).toBeDefined();
      expect(post!.author["@type"]).toBe("Person");
      expect(typeof post!.author.image).toBe("string");
      expect(post!.author.image!.length).toBeGreaterThan(0);
      expect(Array.isArray(post!.author.sameAs)).toBe(true);
      expect(post!.author.sameAs!.length).toBeGreaterThanOrEqual(2);
    });
  }
});

// -- Test 5: every JSON-LD block parses as valid JSON --------------------

describe("all <script type=\"application/ld+json\"> blocks parse as valid JSON", () => {
  test("no malformed JSON-LD anywhere in _site", () => {
    const files = walkHtmlFiles(SITE);
    expect(files.length).toBeGreaterThan(0);
    const failures: { file: string; err: string; snippet: string }[] = [];
    for (const f of files) {
      const html = readFileSync(f, "utf8");
      const re =
        /<script type="application\/ld\+json">([\s\S]*?)<\/script>/g;
      for (const m of html.matchAll(re)) {
        try {
          JSON.parse(m[1]);
        } catch (e) {
          failures.push({
            file: f,
            err: (e as Error).message,
            snippet: m[1].slice(0, 200),
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
