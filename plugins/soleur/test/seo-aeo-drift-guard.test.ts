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
  // SOLEUR_DOCS_OFFLINE=1 makes the Eleventy build hermetic: the _data/github.js,
  // githubStats.js, and communityStats.js loaders skip their live GitHub/Discord
  // fetches and return deterministic fallbacks. Without this, a transient GitHub
  // API rate-limit/5xx/abort in CI makes github.js (or githubStats.js) throw,
  // failing this build and surfacing as a flaky top-level beforeAll "(unnamed)"
  // test (~2.7s, the fetch-failure time). The drift-guards assert on local
  // markup/JSON-LD invariants, not live release data, so an empty changelog is
  // correct here.
  const proc = Bun.spawnSync(
    ["npx", "@11ty/eleventy", `--output=${tmpSite}`],
    {
      cwd: REPO_ROOT,
      stdout: "inherit",
      stderr: "inherit",
      env: { ...process.env, SOLEUR_DOCS_OFFLINE: "1" },
    },
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

// Meta-refresh redirect-stub detection — THE single shared predicate for the
// size-gated heuristic this file previously copy-pasted at 5 sites (#2711
// author-card exclusions, #3174 knowsAbout exclusion, #4407 description
// sampler, the noindex guard). Stubs are tiny (~500 B built); the byte gate
// keeps a refresh-meta hit inside a large legitimate page from
// misclassifying it. The regex is attribute-order- and quote-agnostic so a
// template emitting `<meta content="0;url=…" http-equiv='refresh'>` cannot
// silently escape detection.
const REDIRECT_STUB_MAX_BYTES = 2000;
function isMetaRefreshStub(body: string): boolean {
  return (
    body.length < REDIRECT_STUB_MAX_BYTES &&
    /<meta[^>]*http-equiv=["']refresh["']/i.test(body)
  );
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
          return !isMetaRefreshStub(body);
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
          return !isMetaRefreshStub(body);
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

// -- GSC "Crawled - not indexed" defensive interim: meta-refresh stubs noindex --
//
// The legacy /pages/legal/<slug>.html URLs (and the blog reslug) get edge 301s
// via the Bulk Redirects list in apps/web-platform/infra/seo-bulk-redirects.tf
// (same change; live once the #5092 token-widen + apply completes). Until the
// 301 fires, they are served the meta-refresh fallback (page-redirects.njk,
// HTTP 200), which Google classifies as "Crawled - currently not indexed".
// Adding `<meta name="robots" content="noindex">` to every meta-refresh stub is
// the belt-and-braces interim: even when Googlebot fetches the HTTP-200 stub,
// it is told not to index the legacy URL. The stub still carries
// http-equiv="refresh" + <link rel="canonical"> to the clean URL, so a user is
// still forwarded and a crawler still sees the canonical target. SEO-only; no
// behavior change for humans. See plan 2026-06-09-fix-gsc-legal-page-redirects-plan.md,
// #3367, #3297.
describe("GSC interim — every meta-refresh redirect stub is noindex", () => {
  // Detect stubs via the shared isMetaRefreshStub predicate (size-gated, used
  // by the author-card/knowsAbout/description guards in this file). Walking
  // the built tree (rather than hardcoding the file list) keeps this in
  // lockstep with _data/pageRedirects.js as redirect entries are added/removed.
  function metaRefreshStubs(): { rel: string; body: string }[] {
    return walkHtmlFiles(SITE)
      .map((full) => ({ rel: full.slice(SITE.length + 1), body: readFileSync(full, "utf8") }))
      .filter(({ body }) => isMetaRefreshStub(body));
  }

  test("at least one meta-refresh stub is built (guard is non-vacuous)", () => {
    expect(metaRefreshStubs().length).toBeGreaterThan(0);
  });

  test("the 9 legal stubs the bulk-redirect list maps are all present in the walk", () => {
    // Mirrors the legal source_url set in seo-bulk-redirects.tf 1:1 — if
    // _data/pageRedirects.js ever loses a legal entry, the suite goes RED here
    // instead of the noindex guard silently shrinking its coverage.
    const rels = new Set(metaRefreshStubs().map(({ rel }) => rel));
    const missing = [
      "privacy-policy",
      "cookie-policy",
      "gdpr-policy",
      "acceptable-use-policy",
      "data-protection-disclosure",
      "individual-cla",
      "corporate-cla",
      "disclaimer",
      "terms-and-conditions",
    ].filter((slug) => !rels.has(`pages/legal/${slug}.html`));
    expect(
      missing,
      `legal stubs missing from the built walk: ${missing.join(", ")}`,
    ).toEqual([]);
  });

  test("every meta-refresh stub carries a robots noindex meta", () => {
    // Two-step semantic check: find the robots meta (attribute-order- and
    // quote-agnostic), then require a noindex token in its content — so a
    // valid future `noindex,follow` or attribute reorder cannot false-RED.
    const isNoindexed = (body: string): boolean => {
      const robots = body.match(/<meta[^>]*name=["']robots["'][^>]*>/i);
      return robots !== null && /content=["'][^"']*noindex/i.test(robots[0]);
    };
    const missing = metaRefreshStubs()
      .filter(({ body }) => !isNoindexed(body))
      .map(({ rel }) => rel);
    expect(
      missing,
      `meta-refresh stubs missing noindex: ${missing.join(", ")}`,
    ).toEqual([]);
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
          return !isMetaRefreshStub(body);
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
    for (const { slug } of without) {
      const built = resolve(SITE, "blog", slug, "index.html");
      if (!existsSync(built)) continue;
      expect(blogPostingImage(slug), `${slug}: default image`).toBe(
        `${siteUrl()}/images/og-image.png`,
      );
    }
    // As of #4753 every blog post carries a bespoke ogImage, so `without` is
    // expected empty. The loop above still asserts the default-fallback path
    // for any imageless post reintroduced later, so this is not vacuous: it
    // pins the intended end-state (zero imageless posts) and fails if a post
    // loses its ogImage. (The per-post threading regression #3173 guards
    // against is caught by the "posts with ogImage frontmatter render that
    // exact filename" test above, not here.)
    expect(
      without.length,
      "all blog posts now carry bespoke ogImage (#4753); if an imageless " +
        "post is added intentionally, relax this back to a >= 0 floor",
    ).toBe(0);
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
// Soleur definition at the top and ≥2 external citations (BSL 1.1 LICENSE,
// Claude Code docs, MCP spec). Assert on the built page.

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
      hostMatched(/^https:\/\/github\.com\//),
      "cites the BSL 1.1 LICENSE on GitHub",
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

// -- Test 16: #3165/#3166/#3167/#3168/#3996 marketing copy invariants -------
// One-shot content batch. Pins the five copy/markup fixes against built HTML so
// a future edit that regresses any of them fails loudly:
//   #3168 homepage memory-first deck-line under the H1
//   #3167 /about/ full entity H1 (not bare "About")
//   #3166 /pricing/ inline "concurrent conversation" definition near the table
//   #3165 no hard prose agent/skill count on homepage/pricing/about (soft floor)
//   #3996 Cursor/Copilot comparison promoted OUT of <details> into a section
// Presence checks use html.includes("literal") (not unanchored .test()) per the
// js/regex/missing-regexp-anchor guidance; no tag-strip / &amp; decode.

describe("#3165/#3166/#3167/#3168/#3996 marketing copy invariants", () => {
  // The three prose-bearing marketing pages targeted by #3165.
  const PROSE_PAGES: { label: string; rel: string }[] = [
    { label: "homepage", rel: "index.html" },
    { label: "/pricing/", rel: "pricing/index.html" },
    { label: "/about/", rel: "about/index.html" },
  ];

  test("#3168 homepage renders a memory-first deck-line under the H1", () => {
    const html = readSite("index.html");
    // The deck-line sits in the hero-tagline slot directly under the H1.
    const tagline = html.match(
      /<p class="hero-tagline">([\s\S]*?)<\/p>/,
    );
    expect(tagline, "homepage has a hero-tagline deck-line").not.toBeNull();
    const text = tagline![1];
    // Memory-first hook copy (audit 2026-05-04 §Homepage rewrite #2).
    expect(text, "deck-line surfaces the memory-first hook").toContain(
      "already knows your business",
    );
    // Ordering: the deck-line renders AFTER the H1 (below it).
    const h1Pos = html.search(/<h1[ >]/);
    const taglinePos = html.indexOf('class="hero-tagline"');
    expect(h1Pos, "homepage has an H1").toBeGreaterThanOrEqual(0);
    expect(taglinePos > h1Pos, "deck-line renders below the H1").toBe(true);
  });

  test("#3167 /about/ H1 is the full entity H1, not bare \"About\"", () => {
    const html = readSite("about/index.html");
    const m = html.match(/<h1>([\s\S]*?)<\/h1>/);
    expect(m, "/about/ has an H1").not.toBeNull();
    const h1 = m![1].trim();
    expect(h1, "/about/ H1 names the founder entity").toContain(
      "Jean Deruelle",
    );
    expect(h1, "/about/ H1 names the org entity").toContain("Soleur");
    expect(h1 === "About", "/about/ H1 is not the bare word").toBe(false);
  });

  test("#3166 /pricing/ defines a concurrent conversation inline near the table", () => {
    const html = readSite("pricing/index.html");
    expect(
      html.includes("A concurrent conversation is one active session"),
      "/pricing/ has the inline concurrent-conversation definition",
    ).toBe(true);
    // The definition renders ABOVE the pricing tier grid (near the table).
    const defPos = html.indexOf("A concurrent conversation is one active session");
    const gridPos = html.indexOf('class="pricing-grid"');
    expect(defPos, "definition present").toBeGreaterThanOrEqual(0);
    expect(gridPos, "pricing grid present").toBeGreaterThanOrEqual(0);
    expect(defPos < gridPos, "definition sits above the pricing grid").toBe(
      true,
    );
  });

  test("#3165 no hard prose agent/skill count on homepage/pricing/about", () => {
    let checked = 0;
    for (const { label, rel } of PROSE_PAGES) {
      const html = readSite(rel);
      checked++;
      // The literal the audit/issue called out must never reappear in prose.
      expect(html.includes("66 AI agents"), `${label}: no "66 AI agents"`).toBe(
        false,
      );
      // Stronger drift guard: NO interpolated exact count appears as a prose
      // "N AI agents" / "N agents" / "N specialists" phrase. The stat strip,
      // pricing hero-stat, and tier listings render bare numbers without these
      // prose suffixes, so this matches prose only. A regression that puts
      // {{ stats.agents }} back into a prose sentence reintroduces the suffix
      // and fails here. (Anchored alternation — not a validation .test().)
      const proseCount = html.match(
        /\b\d+\s+(?:AI agents|agents|specialists|AI skills|workflow skills)\b/,
      );
      expect(
        proseCount,
        `${label}: prose must use the 60+ soft floor, found "${proseCount?.[0]}"`,
      ).toBeNull();
      // Positive guard: the soft floor is actually present in prose.
      expect(
        html.includes("60+ AI agents") || html.includes("60+ agents"),
        `${label}: 60+ soft floor present in prose`,
      ).toBe(true);
    }
    expect(checked, "all three prose pages asserted").toBe(PROSE_PAGES.length);
  });

  test("#3996 Cursor/Copilot comparison is promoted OUT of <details> on the homepage", () => {
    const html = readSite("index.html");
    // The promoted comparison lives in a dedicated non-collapsed section.
    expect(
      html.includes('id="soleur-vs-copilots"'),
      "homepage has the promoted comparison section",
    ).toBe(true);
    expect(
      html.includes("Soleur vs. Cursor and GitHub Copilot"),
      "promoted section carries the comparison heading",
    ).toBe(true);

    // Assert the comparison lead sentence appears OUTSIDE any <details> block.
    // Strip every <details>…</details> region, then confirm the lead sentence
    // still appears in what remains. (Region removal of a fixed tag pair — not
    // the single-pass /<[^>]+>/g tag-strip that trips
    // js/incomplete-multi-character-sanitization.)
    const LEAD = "Cursor and Copilot help you write code. Soleur helps you run a company.";
    expect(html.includes(LEAD), "comparison lead sentence present").toBe(true);
    const outsideDetails = html.replace(
      /<details[\s\S]*?<\/details>/g,
      "",
    );
    expect(
      outsideDetails.includes(LEAD),
      "comparison lead renders outside any <details> (above-the-fold-ish, crawlable)",
    ).toBe(true);

    // Hero jump-link to the promoted section keeps it discoverable from the fold.
    expect(
      html.includes('href="#soleur-vs-copilots"'),
      "hero links to the promoted comparison section",
    ).toBe(true);
  });
});

// -- Test 14: #4405 / #4406 high-traffic <title> is not brand-only ----------
// The audit (C1, C3) flagged /getting-started/ and /blog/ as brand-only titles
// that forfeit all non-branded search traffic. R1/R5 rewrites surface
// non-brand keywords. This guard fails if either title regresses to a
// brand-only string (just "Soleur" + the page noun + separators).

describe("#4405/#4406 /getting-started/ + /blog/ <title> surfaces non-brand keywords", () => {
  // Each page must surface at least one of these non-brand keyword tokens in
  // its <title>. Lowercased substring checks (no regex validation → no anchor
  // CodeQL concern). Pulled from R1 (install/AI organization/two commands) and
  // R5 (Company-as-a-Service/agentic/at scale/AI teams).
  const PAGES: { label: string; rel: string; keywords: string[] }[] = [
    {
      label: "/getting-started/",
      rel: "getting-started/index.html",
      keywords: ["install", "ai organization", "two commands"],
    },
    {
      label: "/blog/",
      rel: "blog/index.html",
      keywords: [
        "company-as-a-service",
        "agentic engineering",
        "at scale",
        "ai teams",
      ],
    },
  ];

  // Brand/structural tokens that, on their own, do NOT count as a search hook.
  // If stripping these from the title leaves nothing, the title is brand-only.
  const BRAND_NOISE = ["soleur", "blog", "—", "|", "-", "with"];

  let checked = 0;
  for (const { label, rel, keywords } of PAGES) {
    test(`${label} <title> contains a non-brand keyword (not brand-only)`, () => {
      const html = readSite(rel);
      const title = extractTitle(html);
      const lower = title.toLowerCase();

      // (1) At least one audit-named keyword token is present.
      const present = keywords.filter((k) => lower.includes(k));
      expect(
        present.length,
        `${label}: <title> "${title}" surfaces no non-brand keyword (${keywords.join(", ")})`,
      ).toBeGreaterThan(0);

      // (2) Stripping brand/structural noise must leave real residual words —
      // proves the title is more than "Blog — Soleur". Split on whitespace and
      // drop pure-noise tokens; a brand-only title collapses to zero residual.
      const residual = lower
        .split(/\s+/)
        .map((w) => w.trim())
        .filter((w) => w.length > 0 && !BRAND_NOISE.includes(w));
      expect(
        residual.length,
        `${label}: <title> "${title}" is brand-only after removing brand/structural tokens`,
      ).toBeGreaterThan(0);

      checked++;
    });
  }

  test("both high-traffic titles were asserted (no vacuous skip)", () => {
    expect(checked).toBe(PAGES.length);
  });
});

// -- Test 17: #4407 every canonical sampled page renders a non-empty meta ----
// The audit (C4) claimed no <meta name="description"> on any sampled page — a
// stale WebFetch artifact. base.njk renders `{{ description or site.description }}`,
// so every canonical page is non-empty by construction. This guard pins that:
// a regression that drops the fallback (or a page that somehow renders an empty
// description) fails. Redirect stubs (<meta http-equiv="refresh">) are excluded.

describe("#4407 canonical sampled pages render a non-empty <meta name=\"description\">", () => {
  // The nine audit-sampled pages plus the always-present home + company page.
  const SAMPLED: { label: string; rel: string }[] = [
    { label: "homepage", rel: "index.html" },
    { label: "/pricing/", rel: "pricing/index.html" },
    { label: "/getting-started/", rel: "getting-started/index.html" },
    { label: "/agents/", rel: "agents/index.html" },
    { label: "/skills/", rel: "skills/index.html" },
    { label: "/vision/", rel: "vision/index.html" },
    { label: "/about/", rel: "about/index.html" },
    { label: "/community/", rel: "community/index.html" },
    { label: "/blog/", rel: "blog/index.html" },
    { label: "/changelog/", rel: "changelog/index.html" },
    { label: "/legal/", rel: "legal/index.html" },
    { label: "/company-as-a-service/", rel: "company-as-a-service/index.html" },
  ];

  // SERP envelope: a meta description should be a real sentence, not a single
  // word, and not absurdly long. The lower bound (≥50) catches truncated/empty
  // descriptions; the upper bound is generous (≤220) because audit-mandated
  // copy (R5 /blog/) intentionally runs long. The homepage's stricter 120-160
  // window is pinned separately by Test #2808 above.
  const META_MIN = 50;
  const META_MAX = 220;

  // Attribute-capture extraction (no generic tag regex → avoids
  // js/incomplete-multi-character-sanitization). Returns the first meta
  // description content or null.
  function metaDescription(html: string): string | null {
    const m = [
      ...html.matchAll(/<meta name="description" content="([^"]*)"/g),
    ];
    return m.length > 0 ? m[0][1] : null;
  }

  test("every sampled canonical page has exactly one non-empty meta description within SERP bounds", () => {
    let checked = 0;
    const seen = new Map<string, string>();
    for (const { label, rel } of SAMPLED) {
      const abs = resolve(SITE, rel);
      if (!existsSync(abs)) continue; // build/permalink drift — counter guards vacuity
      const html = readFileSync(abs, "utf8");

      // Skip any redirect stub defensively (a sampled permalink should never be
      // one, but exclude by mechanism rather than by trusting the path).
      if (isMetaRefreshStub(html)) {
        continue;
      }
      checked++;

      const matches = [
        ...html.matchAll(/<meta name="description" content="([^"]*)"/g),
      ];
      expect(
        matches.length,
        `${label}: exactly one <meta name="description">`,
      ).toBe(1);

      const content = metaDescription(html)!.trim();
      expect(
        content.length,
        `${label}: meta description is a real sentence (≥${META_MIN})`,
      ).toBeGreaterThanOrEqual(META_MIN);
      expect(
        content.length,
        `${label}: meta description within ${META_MAX} chars`,
      ).toBeLessThanOrEqual(META_MAX);

      seen.set(label, content);
    }

    // The two audit-named pages must carry their bespoke (non-default) copy —
    // proves they did not silently fall back to site.description.
    const siteDefault = (
      JSON.parse(readFileSync(SITE_JSON, "utf8")) as { description: string }
    ).description;
    for (const label of ["/getting-started/", "/blog/"]) {
      const d = seen.get(label);
      expect(d, `${label}: present in sampled set`).toBeTruthy();
      expect(
        d,
        `${label}: carries a bespoke meta, not the site default`,
      ).not.toBe(siteDefault);
    }

    expect(
      checked,
      "every sampled canonical page asserted against built HTML",
    ).toBe(SAMPLED.length);
  });
});

// -- Test 7: net-new marketing pillars / clusters / glossary ----------------
// Closes #3175 (/company-as-a-service/ pillar — also the inbound link target
// for the homepage + /compare/ pages), #3176 (/ai-agents-for-solo-founders/),
// #2561 (/agentic-engineering/ pillar + /glossary/), #2560 (AI CTO / AI CMO /
// Solo Founder AI Stack clusters), and #2559 (Claude Code plugins pillar).
//
// CodeQL hygiene for this block (net-new test code is a merge gate):
//  - FAQ <summary> text is plain (no nested tags) → use .trim(), never a
//    /<[^>]+>/g tag-strip (avoids js/incomplete-multi-character-sanitization).
//  - HTML-entity decode is limited to &#39; and &quot;; &amp; is NOT collapsed
//    to & (avoids js/double-escaping). FAQ questions are authored free of
//    apostrophes/ampersands, so decode is belt-and-suspenders.
//  - Presence checks use html.includes(literal), never an unanchored .test()
//    (avoids js/regex/missing-regexp-anchor).
describe("#3175/#3176/#2561/#2560/#2559 marketing pillars + clusters + glossary", () => {
  // Decode only the two entities the build emits inside visible FAQ summaries.
  // Deliberately does NOT touch &amp; (see header note).
  const decodeFaqText = (s: string): string =>
    s.replace(/&#39;/g, "'").replace(/&quot;/g, '"');

  // Plain-text <summary> bodies → split on the literal close tag, trim. No
  // tag-strip regex because these summaries never contain nested markup.
  const faqSummaries = (html: string): string[] =>
    [...html.matchAll(/<summary class="faq-question">([^<]*)<\/summary>/g)].map(
      (m) => decodeFaqText(m[1]).trim(),
    );

  const faqDetailsCount = (html: string): number =>
    [...html.matchAll(/<details class="faq-item">/g)].length;

  function faqPageNames(html: string): string[] {
    const block = jsonLdBlocks(html).find(
      (b): b is { "@type": string; mainEntity: { name: string }[] } =>
        typeof b === "object" &&
        b !== null &&
        (b as { "@type"?: string })["@type"] === "FAQPage",
    );
    return block ? block.mainEntity.map((q) => q.name.trim()) : [];
  }

  // Pages with a visible FAQ block + FAQPage JSON-LD that must stay in parity.
  const FAQ_PAGES = [
    "company-as-a-service/index.html",
    "ai-agents-for-solo-founders/index.html",
    "agentic-engineering/index.html",
    "ai-cto/index.html",
    "ai-cmo/index.html",
    "solo-founder-ai-stack/index.html",
    "claude-code-plugins/index.html",
  ];

  // All net-new routes that must build with a real title + meta description.
  const NEW_PAGES = [
    ...FAQ_PAGES,
    "glossary/index.html",
  ];

  test("every new page builds with a non-empty <title> and meta description", () => {
    let checked = 0;
    for (const rel of NEW_PAGES) {
      const html = readSite(rel);
      const title = extractTitle(html);
      expect(title.length, `${rel}: non-empty <title>`).toBeGreaterThan(0);
      expect(title, `${rel}: brand-anchored title`).toContain("Soleur");

      const meta = [
        ...html.matchAll(/<meta name="description" content="([^"]*)"/g),
      ];
      expect(meta.length, `${rel}: exactly one meta description`).toBe(1);
      expect(
        meta[0][1].trim().length,
        `${rel}: meta description is a real sentence`,
      ).toBeGreaterThanOrEqual(50);
      checked++;
    }
    expect(checked, "every new page asserted").toBe(NEW_PAGES.length);
  });

  test("each new page with a visible FAQ has a parity-matched FAQPage JSON-LD", () => {
    let checked = 0;
    for (const rel of FAQ_PAGES) {
      const html = readSite(rel);
      const summaries = faqSummaries(html);
      const details = faqDetailsCount(html);
      const names = faqPageNames(html);

      expect(names.length, `${rel}: FAQPage JSON-LD present`).toBeGreaterThan(0);
      expect(summaries.length, `${rel}: visible summaries present`).toBe(
        details,
      );
      expect(
        details,
        `${rel}: <details> count equals JSON-LD question count`,
      ).toBe(names.length);
      for (const name of names) {
        expect(
          summaries,
          `${rel}: JSON-LD question "${name}" has a character-identical visible <summary>`,
        ).toContain(name);
      }
      checked++;
    }
    expect(checked, "every FAQ page asserted for parity").toBe(
      FAQ_PAGES.length,
    );
  });

  test("/company-as-a-service/ exists and carries the quotable definition (closes D/F inbound links)", () => {
    const html = readSite("company-as-a-service/index.html");
    // Quotable definition near the top — presence check, not regex.
    expect(
      html.includes("Company-as-a-Service (CaaS) is a new category of platform"),
      "quotable CaaS definition present",
    ).toBe(true);
    // The inbound-link target slug resolves as a real page.
    expect(html.includes("<h1>Company-as-a-Service</h1>"), "CaaS H1").toBe(true);
  });

  test("/glossary/ renders at least 8 term definitions", () => {
    const html = readSite("glossary/index.html");
    const terms = [
      "Company-as-a-Service",
      "Agentic Engineering",
      "AI Agent",
      "MCP (Model Context Protocol)",
      "Claude Code Plugin",
      "Skill",
      "Knowledge Base",
      "Human-in-the-Loop",
      "Vibe Coding",
      "Context Engineering",
    ];
    let found = 0;
    for (const t of terms) {
      if (html.includes(`>${t}</h2>`)) found++;
    }
    expect(found, "glossary renders >= 8 of the canonical terms").toBeGreaterThanOrEqual(
      8,
    );
    // DefinedTermSet JSON-LD backs the visible terms.
    const hasTermSet = jsonLdBlocks(html).some(
      (b) =>
        typeof b === "object" &&
        b !== null &&
        (b as { "@type"?: string })["@type"] === "DefinedTermSet",
    );
    expect(hasTermSet, "glossary has DefinedTermSet JSON-LD").toBe(true);
  });

  test("the Claude Code plugins pillar exists and the disambiguation post slug it links to is well-formed", () => {
    const pillar = readSite("claude-code-plugins/index.html");
    // The pillar is the head-term page; it links to the existing reviews post
    // and the sibling disambiguation post by their canonical slugs.
    expect(
      pillar.includes('href="https://soleur.ai/blog/best-claude-code-plugins-2026/"'),
      "pillar links to the existing best-plugins reviews post",
    ).toBe(true);
    expect(
      pillar.includes(
        'href="https://soleur.ai/blog/claude-code-plugin-vs-skill-vs-mcp/"',
      ),
      "pillar links to the disambiguation post by its canonical slug",
    ).toBe(true);
  });
});

// -- Test 18: #4408 / #4409 / #3177 new comparison + disambiguation surfaces --
// The three net-new content pages shipped for the commercial-intent comparison
// gap (#4408 /compare/soleur-vs-cursor/, #4409 /compare/soleur-vs-devin/) and the
// AEO disambiguation post (#3177 /blog/claude-code-plugin-vs-skill-vs-mcp/).
// Each must build with a non-empty <title> + meta description; each visible FAQ
// must have a matching FAQPage JSON-LD (mainEntity names == visible <summary>
// text — the #2707/#3171 parity shape); and the disambiguation post must render
// the Plugin/Skill/MCP table.

describe("#4408/#4409/#3177 new comparison + disambiguation pages", () => {
  // The three new surfaces, by built relative path.
  const PAGES: { label: string; rel: string }[] = [
    { label: "/compare/soleur-vs-cursor/", rel: "compare/soleur-vs-cursor/index.html" },
    { label: "/compare/soleur-vs-devin/", rel: "compare/soleur-vs-devin/index.html" },
    {
      label: "/blog/claude-code-plugin-vs-skill-vs-mcp/",
      rel: "blog/claude-code-plugin-vs-skill-vs-mcp/index.html",
    },
  ];

  // Decode ONLY the autoescape entities Nunjucks emits for apostrophes and
  // double-quotes in a text node. Deliberately NOT &amp; (the &amp;->& round-trip
  // is the js/double-escaping CodeQL pattern) and NO tag-strip (/<[^>]+>/g is the
  // js/incomplete-multi-character-sanitization pattern). Question text is plain
  // ASCII by construction, so .trim() alone suffices; the decode is defensive.
  const decodeText = (s: string) =>
    s.replace(/&#39;/g, "'").replace(/&quot;/g, '"');

  test("each new page builds with a non-empty <title> and meta description", () => {
    let checked = 0;
    for (const { label, rel } of PAGES) {
      const abs = resolve(SITE, rel);
      expect(existsSync(abs), `${label}: built file present`).toBe(true);
      const html = readFileSync(abs, "utf8");

      const title = extractTitle(html);
      expect(title.length, `${label}: non-empty <title>`).toBeGreaterThan(0);
      // The /compare/ pages are brand-anchored (seoTitle ends "| Soleur"); the
      // disambiguation blog post is keyword-led (no brand suffix), so only
      // require the brand anchor on the comparison surfaces.
      if (rel.startsWith("compare/")) {
        expect(title, `${label}: <title> is brand-anchored`).toContain("Soleur");
      }

      const metaMatches = [
        ...html.matchAll(/<meta name="description" content="([^"]*)"/g),
      ];
      expect(
        metaMatches.length,
        `${label}: exactly one <meta name="description">`,
      ).toBe(1);
      expect(
        metaMatches[0][1].trim().length,
        `${label}: meta description is a real sentence`,
      ).toBeGreaterThan(50);
      checked++;
    }
    expect(checked, "all three new pages asserted").toBe(PAGES.length);
  });

  test("each new page's visible FAQ matches its FAQPage JSON-LD (count + names)", () => {
    let checked = 0;
    for (const { label, rel } of PAGES) {
      const html = readSite(rel);
      const detailsCount = [
        ...html.matchAll(/<details class="faq-item">/g),
      ].length;
      // Every new page ships a visible FAQ — assert that, then assert parity.
      expect(detailsCount, `${label}: renders a visible FAQ`).toBeGreaterThan(0);

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
      for (const name of names) {
        expect(
          summaries.map(decodeText),
          `${label}: JSON-LD question "${name}" has a matching visible <summary>`,
        ).toContain(decodeText(name));
      }
      checked++;
    }
    expect(checked, "FAQ parity asserted on all three new pages").toBe(
      PAGES.length,
    );
  });

  test("#3177 disambiguation post renders a Plugin/Skill/MCP table", () => {
    const html = readSite("blog/claude-code-plugin-vs-skill-vs-mcp/index.html");
    // The post body renders inside .prose; the disambiguation table is a real
    // <table>. Assert structure (a table with header cells) and the three
    // primitive column headers it disambiguates. Literal-substring presence
    // checks (.includes) — no regex validation, so no js/regex/missing-regexp-anchor.
    expect(html.includes("<table>"), "disambiguation <table> present").toBe(true);
    expect(html.includes("</table>"), "disambiguation table closed").toBe(true);
    // The three primitives are the table's value columns.
    expect(html.includes("<th>Skill</th>"), "Skill column header").toBe(true);
    expect(html.includes("<th>MCP server</th>"), "MCP server column header").toBe(
      true,
    );
    expect(html.includes("<th>Plugin</th>"), "Plugin column header").toBe(true);
    // The "Scope" row anchors the scope/lifecycle/distribution axes the issue
    // (#3177) requires the table to disambiguate.
    expect(html.includes("Scope"), "table covers Scope").toBe(true);
    expect(html.includes("Lifecycle"), "table covers Lifecycle").toBe(true);
    expect(html.includes("Distribution"), "table covers Distribution").toBe(true);
  });

  test("#3177 disambiguation post links the plugin pillar + a sibling cluster post", () => {
    const html = readSite("blog/claude-code-plugin-vs-skill-vs-mcp/index.html");
    // Internal cross-links the issue requires: the Claude Code plugin pillar
    // (best-claude-code-plugins-2026) and a sibling (skill-libraries-vs-workflow-plugins).
    // Href-attribute presence checks — no text extraction, no sanitization concern.
    expect(
      html.includes('href="/blog/best-claude-code-plugins-2026/"'),
      "links the plugin pillar post",
    ).toBe(true);
    expect(
      html.includes('href="/blog/skill-libraries-vs-workflow-plugins/"'),
      "links a sibling cluster post",
    ).toBe(true);
  });

  test("#4408 cursor compare page cross-links the existing soleur-vs-cursor blog post", () => {
    const html = readSite("compare/soleur-vs-cursor/index.html");
    // The issue requires the /compare/ page and the existing blog post to be
    // cross-linked (not duplicated). The compare page links the blog post via an
    // absolute {{ site.url }}-prefixed href.
    expect(
      html.includes("/blog/soleur-vs-cursor/"),
      "cursor compare page links the existing blog post",
    ).toBe(true);
  });
});

// -- Test 19: #3993 /vision/ demotes internal codenames from proper nouns ---
// The 2026-05-18 content audit (§1, C-6/C-7) flagged /vision/ for reading like
// an internal strategy memo: it used "vessel" as metaphor-as-jargon and
// introduced "Global Brain", "Swarm of Agents", and "Decision Ledger" as
// proper-noun codenames ("Internally called..."). The rewrite reframes them as
// plain lowercase descriptions a non-technical founder/journalist/investor
// understands, while preserving the strategic substance AND the #4754 freshness
// block (stat-led summary + last-updated byline).
//
// CodeQL hygiene (net-new test code is a merge gate): these are pure absence/
// presence checks via html.includes("literal") — NO tag-strip
// (js/incomplete-multi-character-sanitization), NO &amp; decode
// (js/double-escaping), NO unanchored .test() (js/regex/missing-regexp-anchor).
describe("#3993 /vision/ demotes internal codenames + preserves the freshness block", () => {
  // Case-sensitive proper-noun forms the audit named. The plain-language
  // replacements use lowercase phrasing, so these exact strings must be absent
  // from the rendered page.
  const BANNED_CODENAMES = [
    "Global Brain",
    "Swarm of Agents",
    "Decision Ledger",
    "vessel",
  ];

  test("rendered /vision/ contains none of the four proper-noun codenames", () => {
    const html = readSite("vision/index.html");
    for (const codename of BANNED_CODENAMES) {
      expect(
        html.includes(codename),
        `/vision/ must not surface the internal codename/metaphor "${codename}"`,
      ).toBe(false);
    }
  });

  test("rendered /vision/ still renders the #4754 stat-led summary + last-updated block", () => {
    const html = readSite("vision/index.html");
    // Positive guard: don't regress PR B's freshness work while rewriting prose.
    const summaryMatches = [
      ...html.matchAll(/<p class="page-summary">([\s\S]*?)<\/p>/g),
    ];
    expect(summaryMatches.length, "/vision/ has exactly one stat-led summary").toBe(
      1,
    );
    expect(
      summaryMatches[0][1].trim().length,
      "/vision/ stat-led summary is a real sentence",
    ).toBeGreaterThan(80);
    const metaMatches = [
      ...html.matchAll(/<p class="page-meta">([\s\S]*?)<\/p>/g),
    ];
    expect(metaMatches.length, "/vision/ has exactly one last-updated block").toBe(
      1,
    );
    expect(
      metaMatches[0][1].includes("Last updated"),
      '/vision/ last-updated block carries the "Last updated" label',
    ).toBe(true);
  });
});
