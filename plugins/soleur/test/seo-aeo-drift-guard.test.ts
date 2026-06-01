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

// -- Test 9: GSC coverage regression guard (2026-05-29 www→apex host flip) --
// Guards the Search Console "Page with redirect" / "crawled-not-indexed" /
// "404" cluster fixed on 2026-05-29. The sitemap must list only the bare apex
// canonical host (never the redirecting www host), must exclude legacy
// /pages/*.html redirect stubs + /index.html + the RSS feed, the changelog
// must not re-inject www links (APEX_RE rewriter removed from _data/github.js),
// and the renamed terms-of-service stub must resolve. Pre-flip this guard
// would fail: the sitemap used the www host and no terms-of-service stub
// existed. See
// knowledge-base/project/plans/2026-05-29-fix-gsc-coverage-indexing-host-canonical-plan.md.

describe("GSC coverage regression guard (www→apex host flip)", () => {
  test("sitemap.xml uses the apex canonical host only — no www, no legacy paths", () => {
    const siteUrl = (JSON.parse(readFileSync(SITE_JSON, "utf8")) as { url: string })
      .url;
    // Source-of-truth canonical host must be the bare apex (no www.).
    expect(siteUrl).toBe("https://soleur.ai");

    const sitemap = readSite("sitemap.xml");
    const locs = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
    expect(locs.length).toBeGreaterThan(0);

    // Every <loc> uses the apex host declared in site.json (bare apex or a
    // path under it) — nothing off-host.
    const offHost = locs.filter(
      (u) => u !== siteUrl && !u.startsWith(`${siteUrl}/`),
    );
    expect(
      offHost,
      `sitemap <loc> entries off the canonical host: ${offHost.join(", ")}`,
    ).toEqual([]);

    // No www host leaks (www 301s → apex; listing it re-triggers "Page with
    // redirect").
    const wwwLocs = locs.filter((u) => /https:\/\/www\.soleur\.ai/.test(u));
    expect(
      wwwLocs,
      `www-host <loc> entries (canonical is apex): ${wwwLocs.join(", ")}`,
    ).toEqual([]);

    // Legacy /pages/*.html redirect stubs, /index.html, and the RSS feed must
    // NOT appear in the sitemap.
    const legacy = locs.filter((u) =>
      /\/pages\/|\/index\.html|feed\.xml/.test(u),
    );
    expect(
      legacy,
      `legacy/excluded entries in sitemap: ${legacy.join(", ")}`,
    ).toEqual([]);

    // Positive guard for the load-bearing exclusion mechanism: the
    // terms-of-service redirect stub IS built on disk (asserted in a sibling
    // test) but MUST be absent from the sitemap. This is the real failure mode
    // the `/pages/` token above defends — it fires if page-redirects.njk loses
    // its `eleventyExcludeFromCollections: true` and stubs leak into the sitemap.
    const stubLocs = locs.filter((u) => u.includes("terms-of-service"));
    expect(
      stubLocs,
      `redirect-stub entries leaked into sitemap: ${stubLocs.join(", ")}`,
    ).toEqual([]);
  });

  test("changelog page canonical is apex + github.js APEX_RE rewriter removed", () => {
    const html = readSite("changelog/index.html");
    // Canonical <link> renders the apex host (deterministic — derives from
    // site.url). Matched as an HTML-element regex (not a bare URL substring) to
    // avoid the js/incomplete-url-substring-sanitization CodeQL pattern that
    // fires on `.includes("https://…")` host checks.
    expect(html).toMatch(/rel="canonical"[^>]*href="https:\/\/soleur\.ai\//);
    // AC15: the apex→www rewriter is gone from the data loader. Asserted at the
    // SOURCE (deterministic) — NOT against rendered changelog text. The
    // changelog is built from LIVE GitHub release bodies fetched at build time,
    // and a release note can legitimately contain the literal "www.soleur.ai"
    // (e.g. the release describing this very www→apex flip), so a rendered-text
    // absence check is non-deterministic and produces false CI failures.
    const githubJs = readFileSync(
      resolve(REPO_ROOT, "plugins/soleur/docs/_data/github.js"),
      "utf8",
    );
    expect(githubJs).not.toMatch(/APEX_RE|www\.soleur\.ai/);
  });

  test("legacy terms-of-service redirect stub resolves to terms-and-conditions", () => {
    const stub = readSite("pages/legal/terms-of-service.html");
    expect(stub).toContain("/legal/terms-and-conditions/");
  });
});

// -- Test 11: #3174 Person.knowsAbout holds topical areas, not role/bio ----

describe("#3174 Person JSON-LD knowsAbout is a topical-area array on every emitter", () => {
  // Canonical topical array lives in site.json; the drift-guard pins the
  // rendered Person nodes to it so a regression back to role/bio strings
  // (the pre-#3174 state, where knowsAbout === author.credentials) fails.
  const author = () =>
    JSON.parse(readFileSync(SITE_JSON, "utf8")) as {
      author: { knowsAbout: string[]; credentials: string[]; bio: string };
    };

  // A topical area is a short noun phrase. Role/bio sentences ("Founder,
  // Soleur", "15+ years in distributed systems", the full bio) are NOT
  // topics. This guard fails if any entry looks like a credential/bio line.
  function assertTopical(entries: string[], where: string) {
    const { credentials, bio } = author().author;
    expect(entries.length, `${where}: knowsAbout non-empty`).toBeGreaterThan(0);
    for (const e of entries) {
      expect(
        credentials.includes(e),
        `${where}: "${e}" is a credential string, not a topic`,
      ).toBe(false);
      expect(e === bio, `${where}: knowsAbout entry equals bio sentence`).toBe(
        false,
      );
      // Role/bio sentence smells: tenure phrasing, comma-separated title.
      expect(
        /\d+\+?\s*years|^Founder,|\bFounder of\b/.test(e),
        `${where}: "${e}" reads like a role/bio sentence, not a topic`,
      ).toBe(false);
    }
  }

  test("about ProfilePage Person.knowsAbout pins site.json topical array", () => {
    const html = readSite("about/index.html");
    const blocks = jsonLdBlocks(html);
    const profile = blocks.find(
      (b): b is {
        "@type": string;
        mainEntity: { "@type": string; knowsAbout?: string[]; description?: string };
      } =>
        typeof b === "object" &&
        b !== null &&
        (b as { "@type"?: string })["@type"] === "ProfilePage",
    );
    expect(profile, "about: ProfilePage JSON-LD block").toBeDefined();
    const person = profile!.mainEntity;
    expect(person["@type"]).toBe("Person");
    expect(typeof person.description, "about: Person.description").toBe("string");
    expect(person.knowsAbout).toEqual(author().author.knowsAbout);
    assertTopical(person.knowsAbout!, "about ProfilePage Person");
  });

  test("every blog post BlogPosting.author.knowsAbout pins the topical array", () => {
    const blogDir = resolve(SITE, "blog");
    const entries = existsSync(blogDir)
      ? readdirSync(blogDir).filter((e) => {
          const idx = join(blogDir, e, "index.html");
          if (!existsSync(idx) || !statSync(join(blogDir, e)).isDirectory())
            return false;
          const body = readFileSync(idx, "utf8");
          return !(body.length < 2000 && /<meta\s+http-equiv="refresh"/i.test(body));
        })
      : [];
    expect(entries.length).toBeGreaterThan(0);
    const expected = author().author.knowsAbout;
    for (const slug of entries) {
      const html = readSite(`blog/${slug}/index.html`);
      const post = jsonLdBlocks(html).find(
        (b): b is { "@type": string; author: { knowsAbout?: string[] } } =>
          typeof b === "object" &&
          b !== null &&
          (b as { "@type"?: string })["@type"] === "BlogPosting",
      );
      expect(post, `${slug}: BlogPosting JSON-LD block`).toBeDefined();
      expect(post!.author.knowsAbout, `${slug}: knowsAbout`).toEqual(expected);
      assertTopical(post!.author.knowsAbout!, `${slug} BlogPosting Person`);
    }
  });
});

// -- Test 12: #3173 BlogPosting.image threads per-post ogImage --------------

describe("#3173 BlogPosting.image uses the post-specific ogImage, not the site default", () => {
  // Parse ogImage frontmatter from every source post, then assert the built
  // BlogPosting.image renders that exact filename. Posts WITHOUT ogImage
  // legitimately fall back to og-image.png; the count parity assertion below
  // pins the imageless population so a regression (dropping the per-post
  // thread) collapses every post to the default and is caught.
  const SRC_BLOG = resolve(REPO_ROOT, "plugins/soleur/docs/blog");
  const siteUrl = () =>
    (JSON.parse(readFileSync(SITE_JSON, "utf8")) as { url: string }).url;

  function sourcePosts(): { slug: string; ogImage: string | null }[] {
    return readdirSync(SRC_BLOG)
      .filter((f) => f.endsWith(".md"))
      .map((f) => {
        const src = readFileSync(join(SRC_BLOG, f), "utf8");
        const m = src.match(/^ogImage:\s*["']?([^"'\n]+)["']?\s*$/m);
        // Eleventy strips the leading YYYY-MM-DD- date prefix from fileSlug.
        const slug = f.replace(/\.md$/, "").replace(/^\d{4}-\d{2}-\d{2}-/, "");
        return { slug, ogImage: m ? m[1].trim() : null };
      });
  }

  function blogPostingImage(slug: string): string {
    const html = readSite(`blog/${slug}/index.html`);
    const post = jsonLdBlocks(html).find(
      (b): b is { "@type": string; image: string } =>
        typeof b === "object" &&
        b !== null &&
        (b as { "@type"?: string })["@type"] === "BlogPosting",
    );
    expect(post, `${slug}: BlogPosting JSON-LD block`).toBeDefined();
    return post!.image;
  }

  test("posts with ogImage frontmatter render that exact filename in BlogPosting.image", () => {
    const withImage = sourcePosts().filter((p) => p.ogImage);
    expect(withImage.length).toBeGreaterThan(0);
    let checked = 0;
    for (const { slug, ogImage } of withImage) {
      const built = resolve(SITE, "blog", slug, "index.html");
      if (!existsSync(built)) continue; // permalink override — skip silently
      checked++;
      const image = blogPostingImage(slug);
      const expected = `${siteUrl()}/images/${ogImage}`;
      expect(image, `${slug}: BlogPosting.image threads ogImage`).toBe(expected);
      expect(image, `${slug}: must not be the site default`).not.toBe(
        `${siteUrl()}/images/og-image.png`,
      );
    }
    // Guard against a vacuous pass: a slug-derivation drift that skipped every
    // post would otherwise leave this test green having asserted nothing.
    expect(
      checked,
      "at least one ogImage post asserted against built HTML",
    ).toBeGreaterThan(0);
  });

  test("posts without ogImage fall back to the site default og-image.png", () => {
    const without = sourcePosts().filter((p) => !p.ogImage);
    let checked = 0;
    for (const { slug } of without) {
      const built = resolve(SITE, "blog", slug, "index.html");
      if (!existsSync(built)) continue;
      checked++;
      expect(blogPostingImage(slug), `${slug}: default image`).toBe(
        `${siteUrl()}/images/og-image.png`,
      );
    }
    expect(
      checked,
      "at least one imageless post asserted against built HTML",
    ).toBeGreaterThan(0);
  });
});

// -- Test 13: #3171 FAQPage JSON-LD parity beyond /pricing/ -----------------

describe("#3171 FAQPage JSON-LD matches the visible FAQ on every Q&A page", () => {
  // #2707 already covers /pricing/. This generalizes the parity invariant to
  // every other page that renders a visible FAQ block, so a future page that
  // ships <details class="faq-item"> without a matching FAQPage JSON-LD (or
  // with a drifted question set) fails the guard.
  for (const page of ["about", "company-as-a-service", ""]) {
    const label = page === "" ? "homepage" : `/${page}/`;
    const rel = page === "" ? "index.html" : `${page}/index.html`;
    test(`${label}: FAQPage mainEntity count + names match visible <summary>`, () => {
      const html = readSite(rel);
      const detailsCount = [
        ...html.matchAll(/<details class="faq-item">/g),
      ].length;
      if (detailsCount === 0) return; // page has no visible FAQ — nothing to pin
      const faq = jsonLdBlocks(html).find(
        (b): b is { "@type": string; mainEntity: { name: string }[] } =>
          typeof b === "object" &&
          b !== null &&
          (b as { "@type"?: string })["@type"] === "FAQPage",
      );
      expect(faq, `${label}: FAQPage JSON-LD present for visible FAQ`).toBeDefined();
      const summaries = [
        ...html.matchAll(/<summary class="faq-question">([\s\S]*?)<\/summary>/g),
      ].map((m) => m[1].trim());
      const names = faq!.mainEntity.map((q) => q.name.trim());
      expect(detailsCount, `${label}: details vs JSON-LD count`).toBe(names.length);
      expect(summaries.length, `${label}: summaries vs JSON-LD count`).toBe(
        names.length,
      );
      // Decode ONLY the autoescape entities Nunjucks emits for apostrophes and
      // double-quotes in a text node. Deliberately NOT &amp; (the &amp;->&
      // round-trip is the js/double-escaping CodeQL pattern) and no tag-strip
      // (summaries are plain text; /<[^>]+>/g is the js/incomplete-multi-
      // character-sanitization pattern). A future question that introduces
      // nested markup will fail loudly here — correct drift-guard behavior.
      const decodeText = (s: string) =>
        s.replace(/&#39;/g, "'").replace(/&quot;/g, '"');
      for (const name of names) {
        expect(
          summaries.map(decodeText),
          `${label}: JSON-LD question "${name}" has a visible <summary>`,
        ).toContain(decodeText(name));
      }
    });
  }
});

// -- Test 14: #3169 / #3170 / #3994 evergreen freshness block ---------------
// Every evergreen page must render, below the hero: (1) a stat-led summary
// paragraph (AEO citation target, #3169), and (2) a visible "Last updated"
// line + author byline (#3170), driven by per-page last_updated frontmatter
// rendered through _includes/page-freshness.njk. The combination targets the
// AEO Presence ≥55% exit gate (#3994). Shared partial → assert on every page.

describe("#3169/#3170/#3994 evergreen pages render stat-led summary + last-updated byline below the hero", () => {
  // Canonical evergreen set (homepage + the five cited pages) plus
  // /getting-started/ (also evergreen; carries the #4410 block too).
  const EVERGREEN: { label: string; rel: string }[] = [
    { label: "homepage", rel: "index.html" },
    { label: "/about/", rel: "about/index.html" },
    { label: "/vision/", rel: "vision/index.html" },
    { label: "/pricing/", rel: "pricing/index.html" },
    { label: "/agents/", rel: "agents/index.html" },
    { label: "/skills/", rel: "skills/index.html" },
    { label: "/getting-started/", rel: "getting-started/index.html" },
  ];

  // Byline name is the single source of truth in site.json — pin to it so a
  // rename in the data file must update the rendered byline in lockstep.
  const authorName = () =>
    (JSON.parse(readFileSync(SITE_JSON, "utf8")) as { author: { name: string } })
      .author.name;

  test("every evergreen page has exactly one stat-led summary + one last-updated byline, summary below the H1", () => {
    let checked = 0;
    for (const { label, rel } of EVERGREEN) {
      const abs = resolve(SITE, rel);
      if (!existsSync(abs)) continue; // build/permalink drift — skip, counter guards vacuity
      checked++;
      const html = readFileSync(abs, "utf8");

      // (1) Stat-led summary — exactly one, non-trivial length. The summary is
      // plain text inside the <p>; capture the inner text and .trim() only — no
      // tag-strip regex (js/incomplete-multi-character-sanitization) and no
      // &amp;->& decode (js/double-escaping). The summary contains no nested
      // markup by construction (page-freshness.njk emits a bare text node).
      const summaryMatches = [
        ...html.matchAll(/<p class="page-summary">([\s\S]*?)<\/p>/g),
      ];
      expect(summaryMatches.length, `${label}: exactly one .page-summary`).toBe(1);
      const summaryText = summaryMatches[0][1].trim();
      expect(
        summaryText.length,
        `${label}: stat-led summary is a real sentence`,
      ).toBeGreaterThan(80);
      // Proof points the AEO audit wants extractable from the summary.
      expect(summaryText, `${label}: summary names Company-as-a-Service`).toContain(
        "Company-as-a-Service",
      );
      expect(
        /Model Context Protocol/.test(summaryText),
        `${label}: summary cites MCP`,
      ).toBe(true);

      // (2) Last-updated + byline block — exactly one, with a machine-readable
      // <time datetime="YYYY-MM-DD"> and the author byline.
      const metaMatches = [
        ...html.matchAll(/<p class="page-meta">([\s\S]*?)<\/p>/g),
      ];
      expect(metaMatches.length, `${label}: exactly one .page-meta`).toBe(1);
      const metaText = metaMatches[0][1];
      expect(metaText, `${label}: visible "Last updated" label`).toContain(
        "Last updated",
      );
      expect(
        /<time datetime="\d{4}-\d{2}-\d{2}">/.test(metaText),
        `${label}: machine-readable <time datetime>`,
      ).toBe(true);
      expect(metaText, `${label}: author byline`).toContain(authorName());

      // (3) Ordering — the summary must sit BELOW the page H1 (below-the-hero).
      const h1Pos = html.search(/<h1[ >]/);
      const summaryPos = html.indexOf('class="page-summary"');
      expect(h1Pos, `${label}: page has an H1`).toBeGreaterThanOrEqual(0);
      expect(
        summaryPos > h1Pos,
        `${label}: stat-led summary renders below the hero H1`,
      ).toBe(true);
    }
    expect(
      checked,
      "at least one evergreen page asserted against built HTML",
    ).toBe(EVERGREEN.length);
  });

  test("every evergreen page's WebPage JSON-LD dateModified reflects the freshness date", () => {
    let checked = 0;
    for (const { label, rel } of EVERGREEN) {
      const abs = resolve(SITE, rel);
      if (!existsSync(abs)) continue;
      checked++;
      const html = readFileSync(abs, "utf8");
      // base.njk emits a single JSON-LD script holding a @graph array; the
      // WebPage node lives inside that graph, not as a top-level block.
      const nodes = jsonLdBlocks(html).flatMap((b) => {
        if (typeof b !== "object" || b === null) return [];
        const graph = (b as { "@graph"?: unknown[] })["@graph"];
        return Array.isArray(graph) ? graph : [b];
      });
      const webPage = nodes.find(
        (b): b is { "@type": string; dateModified?: string } =>
          typeof b === "object" &&
          b !== null &&
          (b as { "@type"?: string })["@type"] === "WebPage",
      );
      expect(webPage, `${label}: WebPage JSON-LD block`).toBeDefined();
      expect(
        typeof webPage!.dateModified,
        `${label}: WebPage.dateModified present (freshness signal)`,
      ).toBe("string");
      // RFC-3339-ish — the dateToRfc3339 filter emits an ISO timestamp.
      expect(
        /^\d{4}-\d{2}-\d{2}T/.test(webPage!.dateModified!),
        `${label}: dateModified is an ISO timestamp`,
      ).toBe(true);
    }
    expect(checked, "dateModified asserted on every evergreen page").toBe(
      EVERGREEN.length,
    );
  });
});

// -- Test 15: #4410 /getting-started/ definition + external citations -------
// The single weakest page for AI-engine extractability gets a plain-language
// Soleur definition at the top and ≥2 external citations (Apache-2.0, Claude
// Code docs, MCP spec). Assert on the built page.

describe("#4410 /getting-started/ has a plain-language definition + external citations", () => {
  test("renders one .page-definition and ≥2 distinct external citation hrefs", () => {
    const html = readSite("getting-started/index.html");

    const defMatches = [
      ...html.matchAll(/<p class="page-definition">([\s\S]*?)<\/p>/g),
    ];
    expect(defMatches.length, "exactly one .page-definition").toBe(1);
    expect(
      defMatches[0][1].trim().length,
      "definition is a real plain-language sentence",
    ).toBeGreaterThan(60);

    // Count distinct external hrefs inside the citations block. Match on the
    // href attribute only (no text extraction → no sanitization CodeQL flags).
    const citeBlock = html.match(
      /<div class="page-citations">([\s\S]*?)<\/div>/,
    );
    expect(citeBlock, ".page-citations block present").not.toBeNull();
    const hrefs = new Set(
      [...citeBlock![1].matchAll(/href="(https?:\/\/[^"]+)"/g)].map(
        (m) => m[1],
      ),
    );
    expect(
      hrefs.size,
      "≥2 distinct external citations in /getting-started/",
    ).toBeGreaterThanOrEqual(2);

    // Pin the three audit-mandated sources (host-anchored, not bare substring).
    const hostMatched = (re: RegExp) => [...hrefs].some((h) => re.test(h));
    expect(
      hostMatched(/^https:\/\/www\.apache\.org\//),
      "cites Apache-2.0 license",
    ).toBe(true);
    expect(
      hostMatched(/^https:\/\/docs\.claude\.com\//),
      "cites Claude Code docs",
    ).toBe(true);
    expect(
      hostMatched(/^https:\/\/modelcontextprotocol\.io(\/|$)/),
      "cites the MCP spec",
    ).toBe(true);
  });
});
