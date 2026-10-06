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
import {
  allDeclaredSources,
  bulkRedirectPairs,
  dynamicItemBlock,
  missingEdge301Flags,
} from "./lib/bulk-redirect-pairs";
import {
  decodeEntities,
  openAncestors,
  plainText,
  sentencesOf,
  tagsOf,
  visibleText,
  withoutInert,
} from "./lib/visible-text";

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

    // Positive guard for the load-bearing exclusion mechanism: a terms-of-service
    // redirect stub MUST be absent from the sitemap. This is the real failure mode
    // the `/pages/` token above defends — if a stub template is ever reintroduced
    // without `eleventyExcludeFromCollections: true`, it leaks into the sitemap.
    // (Disk presence is fenced separately by the Guard-2 zero-stub walk below;
    // the meta-refresh machinery was deleted in #3328.)
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

  test("legacy terms-of-service URL is covered by the bulk-redirect list", () => {
    // #3328 PR-B: the meta-refresh stub no longer exists — the canonical source
    // of truth for this redirect is the Cloudflare Bulk Redirect list in
    // seo-bulk-redirects.tf (live edge 301, verified 2026-09-18/19). Assert the
    // pair on its own item {} block — a file-wide match could hide a dropped
    // target behind the sibling terms-and-conditions item's identical target.
    const tf = readFileSync(
      resolve(REPO_ROOT, "apps/web-platform/infra/seo-bulk-redirects.tf"),
      "utf8",
    );
    const item = bulkRedirectPairs(tf).get(
      "soleur.ai/pages/legal/terms-of-service.html",
    );
    expect(
      item?.target,
      "terms-of-service.html must 301 to the renamed legal page",
    ).toBe("https://soleur.ai/legal/terms-and-conditions/");
  });
});

// -- Guard 2 (#3328 PR-B): meta-refresh reintroduction fence ------------------
//
// The meta-refresh redirect machinery (docs/page-redirects.njk,
// _data/pageRedirects.js, docs/blog/redirects.njk, _data/blogRedirects.js —
// plus docs/pages/articles.njk, the last hand-maintained stub, found by this
// fence's first _site walk and migrated to the bulk list in the same PR) was
// deleted in #3328 PR-B after every legacy URL was verified live behind an
// edge 301 (Cloudflare Bulk Redirects, apps/web-platform/infra/
// seo-bulk-redirects.tf — 19/19 from-paths + 69/69 blog date-slug URLs,
// 2026-09-18/19). The built site must now contain ZERO meta-refresh stubs: a
// reintroduced stub is the exact regression that put these URLs in GSC's
// "Crawled - currently not indexed" bucket (HTTP 200 + refresh, a
// non-deterministic signal). The second chokepoint is validate-seo.sh, whose
// instant-refresh skip block was removed in the same PR, so a reintroduced
// stub also fails full SEO validation on its missing canonical. The tf-source
// assertions pin the legal source_url set the stubs used to render — the
// parity property the deleted _data/pageRedirects.js provided, now anchored
// on the canonical source.
describe("Guard 2 — zero meta-refresh stubs + bulk-redirect source parity (#3328)", () => {
  const TF_PATH = resolve(
    REPO_ROOT,
    "apps/web-platform/infra/seo-bulk-redirects.tf",
  );
  const readTf = () => readFileSync(TF_PATH, "utf8");

  test("no built HTML page contains a meta refresh of any size or delay", () => {
    // isMetaRefreshStub is size-gated (<2KB) by design — a stub emitted inside
    // a full layout escapes it AND escapes validate-seo.sh (the layout
    // supplies canonical/JSON-LD/og/h1/description). After #3328 no page may
    // carry http-equiv=refresh at all: the fence is unconditional, not
    // stub-shaped. Any delay (content=5) counts too — a delayed refresh is
    // still the GSC crawled-not-indexed mechanism.
    const files = walkHtmlFiles(SITE);
    expect(files.length).toBeGreaterThan(0);
    const offenders = files
      .map((full) => ({ rel: full.slice(SITE.length + 1), body: readFileSync(full, "utf8") }))
      .filter(({ body }) => /http-equiv\s*=\s*["']?refresh/i.test(body))
      .map(({ rel }) => rel);
    expect(
      offenders,
      `meta refresh found in built page(s) — no page may use http-equiv=refresh after #3328 (edge 301s only): ${offenders.join(", ")}`,
    ).toEqual([]);
  });

  test("the built site emits no _redirects/_headers channel outside the guards' window", () => {
    // A Cloudflare Pages _redirects or _headers file (via an
    // addPassthroughCopy in eleventy.config.js) would be a second redirect
    // channel that neither the _site HTML walk nor the tf assertions see.
    // Assert none exists in the build output.
    for (const name of ["_redirects", "_headers"]) {
      expect(
        existsSync(join(SITE, name)),
        `${name} emitted into _site — a redirect channel outside the tf-guard window; route redirects through seo-bulk-redirects.tf instead`,
      ).toBe(false);
    }
  });

  test("seo-bulk-redirects.tf still declares the legal + alias + /articles/ pairs with edge-301 flags", () => {
    // Mirrors the source_url -> target_url set in seo-bulk-redirects.tf — the
    // parity property the deleted _data/pageRedirects.js (and the
    // articles.njk stub) provided, anchored on the canonical source. If an
    // entry is ever dropped from the list, the corresponding legacy URL loses
    // its edge 301. Flags are pinned on the SAME item block as the pair: a
    // status_code flip to 302 or a dropped include_subdomains changes the
    // redirect's semantics without touching the pair.
    const tf = readTf();
    const pairs = bulkRedirectPairs(tf);
    // Anti-vacuity floor on the map side: a renamed locals/item structure that
    // yields zero parsed pairs must not read as "all expected pairs absent".
    expect(
      pairs.size,
      "no redirect items parsed from seo-bulk-redirects.tf — the parser or the file drifted",
    ).toBeGreaterThan(0);
    const expected = new Map<string, string>([
      // 9 legal slugs (clean-slug == source-slug)
      ...[
        "privacy-policy",
        "cookie-policy",
        "gdpr-policy",
        "acceptable-use-policy",
        "data-protection-disclosure",
        "individual-cla",
        "corporate-cla",
        "disclaimer",
        "terms-and-conditions",
      ].map(
        (slug): [string, string] => [
          `soleur.ai/pages/legal/${slug}.html`,
          `https://soleur.ai/legal/${slug}/`,
        ],
      ),
      // The ToS alias pair (terms-of-service → terms-and-conditions) — the
      // renamed URL the original GSC fix depended on.
      [
        "soleur.ai/pages/legal/terms-of-service.html",
        "https://soleur.ai/legal/terms-and-conditions/",
      ],
      // The /articles/ stub reslug added in #3328 PR-B — deleting the stub
      // with no edge 301 would have stranded the URL as a 404.
      ["soleur.ai/articles/", "https://soleur.ai/blog/"],
      ["soleur.ai/articles/index.html", "https://soleur.ai/blog/"],
      ["soleur.ai/articles", "https://soleur.ai/blog/"],
    ]);
    const missing: string[] = [];
    const mismatched: string[] = [];
    const flagless: string[] = [];
    for (const [src, tgt] of expected) {
      const item = pairs.get(src);
      if (!item) {
        missing.push(src);
        continue;
      }
      if (item.target !== tgt)
        mismatched.push(`${src} -> ${item.target} (expected ${tgt})`);
      for (const flag of missingEdge301Flags(item.block)) {
        flagless.push(`${src}: ${flag}`);
      }
    }
    expect(
      missing,
      `redirect source_urls missing from seo-bulk-redirects.tf: ${missing.join(", ")}`,
    ).toEqual([]);
    expect(
      mismatched,
      `redirect items with wrong target_url in seo-bulk-redirects.tf: ${mismatched.join(", ")}`,
    ).toEqual([]);
    expect(
      flagless,
      `redirect items missing edge-301 flags in seo-bulk-redirects.tf: ${flagless.join(", ")}`,
    ).toEqual([]);
  });

  test("the generated-item expansion (3 arms + dynamic block) is intact", () => {
    // The pairs maps only reach Cloudflare through the 3-arm flattens in
    // local.blog_redirect_items + local.tombstone_redirect_items, the concat
    // into local.redirect_items, and the `dynamic "item"` block on the list
    // resource. Dropping one arm un-serves a whole URL shape per pair;
    // dropping the dynamic block un-serves every generated item — and every
    // pair assertion above stays green because it never reads the expansion.
    // Pin the structure.
    const tf = readTf();
    for (const arm of [
      'source = "soleur.ai/blog/${date_slug}/"',
      'source = "soleur.ai/blog/${date_slug}/index.html"',
      'source = "soleur.ai/blog/${date_slug}"',
    ]) {
      expect(
        tf.includes(arm),
        `blog_redirect_items is missing the expansion arm: ${arm} — a whole URL shape loses its edge 301`,
      ).toBe(true);
    }
    // #8364: tombstone expansion — same 3 shapes, ${prefix} keyed.
    for (const arm of [
      'source = "soleur.ai/${prefix}/"',
      'source = "soleur.ai/${prefix}/index.html"',
      'source = "soleur.ai/${prefix}"',
    ]) {
      expect(
        tf.includes(arm),
        `tombstone_redirect_items is missing the expansion arm: ${arm} — a tombstoned URL shape loses its edge 301`,
      ).toBe(true);
    }
    expect(
      /redirect_items = concat\(local\.blog_redirect_items, local\.tombstone_redirect_items\)/.test(
        tf,
      ),
      "local.redirect_items must concat both generated-item expansions — a dropped side un-serves that whole class",
    ).toBe(true);

    // The dynamic "item" template is what every generated redirect is stamped
    // from — pinning only the locals leaves a mutation inside its content {}
    // block (301→302, dropped subdomains flag, rewired source) invisible to
    // every assertion above (#8364 review). Pin the block's attributes.
    const dyn = dynamicItemBlock(tf);
    expect(
      dyn,
      'dynamic "item" must iterate local.redirect_items',
    ).toMatch(/for_each\s*=\s*local\.redirect_items/);
    for (const pin of [
      /source_url\s*=\s*item\.value\.source/,
      /target_url\s*=\s*item\.value\.target/,
      /status_code\s*=\s*301/,
      /include_subdomains\s*=\s*"enabled"/,
      /preserve_query_string\s*=\s*"enabled"/,
    ]) {
      expect(
        pin.test(dyn),
        `dynamic "item" content block lost ${pin.source} — every generated redirect inherits the mutation`,
      ).toBe(true);
    }
  });

  test("bulk-list freshness: every declared source is dead on disk and every target resolves to a built page (#8364)", () => {
    // The declared redirect set must be internally fresh in BOTH directions:
    //   - a source_url still served by the built site means the redirect
    //     shadows a live page (the edge 301 wins over the origin — the page
    //     becomes unreachable);
    //   - a target_url with no built page is a redirect-to-404 rot.
    // Sources: literal items + both pair-map expansions. Non-apex hosts
    // (the www_canonical item) are out of scope — that list's semantics are
    // subpath-matching, not exact-path.
    const tf = readTf();
    // allDeclaredSources throws on a cross-set source_url collision — a
    // generated expansion that duplicates a literal item is a defect, not a
    // merge (same last-wins masking class as the parser's in-list throw).
    const allSources = allDeclaredSources(tf);
    expect(
      allSources.size,
      "no redirect sources parsed — the parser or the file drifted",
    ).toBeGreaterThan(0);

    // Candidate built-file paths a URL maps to (dir index, literal file,
    // or extension-suffixed twin).
    const builtCandidates = (path: string): string[] => {
      if (path === "/" || path === "") return ["index.html"];
      const p = path.replace(/^\//, "");
      if (p.endsWith("/")) return [`${p}index.html`];
      const last = p.split("/").pop()!;
      if (last.includes(".")) return [p];
      return [`${p}/index.html`, `${p}.html`, p];
    };

    const shadowed: string[] = [];
    const deadTargets: string[] = [];
    for (const [src, target] of allSources) {
      if (!src.startsWith("soleur.ai")) continue; // non-apex host (www list)
      const srcPath = src.slice("soleur.ai".length);
      if (
        // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal -- rel derives from tf-declared redirect sources, repo-controlled constants
        builtCandidates(srcPath).some((rel) => existsSync(resolve(SITE, rel)))
      ) {
        shadowed.push(src);
      }
      const tm = target.match(/^https:\/\/soleur\.ai(\/.*)?$/);
      if (!tm) {
        deadTargets.push(`${src} -> ${target} (off-host target)`);
        continue;
      }
      const targetPath = tm[1] ?? "/";
      if (
        !builtCandidates(targetPath).some((rel) =>
          // nosemgrep: javascript.lang.security.audit.path-traversal.path-join-resolve-traversal.path-join-resolve-traversal -- rel derives from tf-declared redirect targets, repo-controlled constants
          existsSync(resolve(SITE, rel)),
        )
      ) {
        deadTargets.push(`${src} -> ${target} (no built page)`);
      }
    }
    expect(
      shadowed,
      `redirect sources still served by the built site (a live page is shadowed by its own 301): ${shadowed.join(", ")}`,
    ).toEqual([]);
    expect(
      deadTargets,
      `redirect targets with no built page (redirect-to-404 rot): ${deadTargets.join(", ")}`,
    ).toEqual([]);
  });
});

// -- Guard 3 (#3328 PR-B): pillar-series frontmatter <-> _data/pillars.js ----
//
// The two new series added for #3328 internal-link equity are wired by
// `pillar: <key>` frontmatter consumed by _includes/pillar-series.njk, which
// degrades silently: an unknown key emits only an HTML comment, and a member
// URL resolving to no post renders an empty <a> title (or a 404 href). This
// guard makes the relation bidirectional and loud — same parity property the
// redirect guards above enforce, applied to the link-equity data.
describe("pillar-series frontmatter <-> _data/pillars.js parity", () => {
  test("every pillar: key resolves to a series and every member URL resolves to a post", async () => {
    const { default: loadPillars } = await import(
      resolve(REPO_ROOT, "plugins/soleur/docs/_data/pillars.js")
    );
    const pillars = loadPillars() as Record<
      string,
      { members: { url: string; relation: string }[] }
    >;
    const seriesKeys = new Set(Object.keys(pillars));

    const posts = readdirSync(BLOG_POSTS_DIR).filter((f) =>
      f.endsWith(".md"),
    );
    // frontmatter body only — a body line starting `pillar:` must not count.
    const declared = new Map<string, string>();
    for (const f of posts) {
      const fm =
        readFileSync(join(BLOG_POSTS_DIR, f), "utf8").split(/^---$/m)[1] ?? "";
      const m = fm.match(/^pillar:\s*(\S+)/m);
      if (m) declared.set(f.replace(/\.md$/, ""), m[1]);
    }
    for (const [file, key] of declared) {
      expect(
        seriesKeys.has(key),
        `${file}.md declares unknown pillar: '${key}' — pillar-series.njk renders only an HTML comment for unknown keys`,
      ).toBe(true);
    }

    // fileSlug strips an optional YYYY-MM-DD- prefix, so a member URL
    // /blog/<slug>/ maps to either <slug>.md or YYYY-MM-DD-<slug>.md — the
    // "-"-anchored endsWith covers both without a regex.
    const fileForSlug = (slug: string) =>
      posts.find((f) => f === `${slug}.md` || f.endsWith(`-${slug}.md`));
    const failures: string[] = [];
    let memberCount = 0;
    for (const [key, series] of Object.entries(pillars)) {
      for (const member of series.members) {
        memberCount++;
        const slug = member.url.replace(/^\/blog\//, "").replace(/\/$/, "");
        const file = fileForSlug(slug);
        if (!file) {
          failures.push(`${key}: member ${member.url} resolves to no post file`);
          continue;
        }
        const base = file.replace(/\.md$/, "");
        if (declared.get(base) !== key) {
          failures.push(
            `${key}: member ${member.url} -> ${file} declares pillar '${declared.get(base)}' (expected '${key}')`,
          );
        }
      }
    }
    expect(
      memberCount,
      "no pillar members enumerated — the parity guard cannot pass vacuously",
    ).toBeGreaterThan(0);
    expect(failures).toEqual([]);
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
//   #3165 no hard prose agent/skill count on pricing/about (soft floor; the homepage moved to computed counts, #9579 Guard 2)
//   #3996 Cursor/Copilot comparison promoted OUT of <details> into a section
// Presence checks use html.includes("literal") (not unanchored .test()) per the
// js/regex/missing-regexp-anchor guidance; no tag-strip / &amp; decode.

describe("#3165/#3166/#3167/#3168/#3996 marketing copy invariants", () => {
  // The prose-bearing marketing pages that keep the 60+ soft floor (#3165).
  // The homepage left this list in #9579: it renders computed stats.js counts,
  // pinned by "#9579 Guard 2" below. Pricing/about stay on the floor.
  const PROSE_PAGES: { label: string; rel: string }[] = [
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

  test("#3165 no hard prose agent/skill count on pricing/about (homepage: see #9579 Guard 2)", () => {
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
    expect(checked, "both prose pages asserted").toBe(PROSE_PAGES.length);
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

    // The hero reaches a comparison page that exists (#9579; the in-page
    // anchor link was replaced, the section and its id stay for AEO).
    expect(
      html.includes('href="/compare/soleur-vs-cursor/"'),
      "hero links to the Cursor comparison page",
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

// -- #9579/#9580 trust-copy guards ------------------------------------------
// Three guards (hosted-claims copy, computed counts, attribution) plus a hero
// structure check. The contract and mutation matrices live in
// knowledge-base/project/plans/2026-10-06-fix-homepage-copy-and-trust-fixes-plan.md
// (## Guard Contract). Visible text comes from ./lib/visible-text (a character
// scan, not a tag-strip regex: js/incomplete-multi-character-sanitization).

const LD_BLOCK_RE = /<script[^>]*application\/ld\+json[^>]*>([\s\S]*?)<\/script>/gi;

function ldBodies(html: string): string[] {
  return [...html.matchAll(LD_BLOCK_RE)].map((m) => m[1]);
}

function jsonLdStrings(html: string): string[] {
  const out: string[] = [];
  const walk = (v: unknown): void => {
    if (typeof v === "string") out.push(v);
    else if (Array.isArray(v)) v.forEach(walk);
    else if (v && typeof v === "object") Object.values(v).forEach(walk);
  };
  for (const body of ldBodies(html)) walk(JSON.parse(body));
  return out;
}

function hasKey(v: unknown, keys: string[]): boolean {
  if (Array.isArray(v)) return v.some((x) => hasKey(x, keys));
  if (v && typeof v === "object") {
    return Object.entries(v).some(([k, x]) => keys.includes(k) || hasKey(x, keys));
  }
  return false;
}

// Text a crawler or share card reads that no visible-text scan sees: meta
// description / og / twitter content and alt, aria-label, title, placeholder.
// Tags come from the quote-aware scanner (a `>` inside a quoted value does not
// end the tag); values may be double-quoted, single-quoted or unquoted.
function attributeTexts(html: string): string[] {
  const out: string[] = [];
  for (const { raw } of tagsOf(html)) {
    if (raw.startsWith("</")) continue;
    const isMeta = /^<meta\b/i.test(raw);
    const metaOk = /\b(?:name|property)\s*=\s*["']?(?:description|og:[^"'\s>]*|twitter:[^"'\s>]*)(?=["'\s>])/i.test(raw);
    for (const a of raw.matchAll(
      /\b(alt|aria-label|title|content|placeholder)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/gi,
    )) {
      if (a[1].toLowerCase() === "content" && !(isMeta && metaOk)) continue;
      out.push(decodeEntities(a[2] ?? a[3] ?? a[4] ?? ""));
    }
  }
  return out;
}

function relOf(abs: string): string {
  return abs.slice(SITE.length + 1);
}

function allPages(): { rel: string; html: string }[] {
  return walkHtmlFiles(SITE)
    .map((abs) => ({ rel: relOf(abs), html: readFileSync(abs, "utf8") }))
    .filter(({ html }) => !isMetaRefreshStub(html));
}

const marketingPages = () =>
  allPages().filter(({ rel }) => !rel.startsWith("blog/") && !rel.startsWith("legal/"));
const blogPages = () => allPages().filter(({ rel }) => rel.startsWith("blog/"));

// The three places a claim lives: visible text, structured data, attributes.
function pageParts(html: string): { text: string[]; ld: string[]; attr: string[] } {
  return {
    text: sentencesOf(visibleText(html)),
    ld: jsonLdStrings(html).flatMap(sentencesOf),
    attr: attributeTexts(html).flatMap(sentencesOf),
  };
}

function faqAnswer(html: string, question: string): string {
  const esc = question.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const m = html.match(
    new RegExp(
      `<summary class="faq-question">${esc}</summary>\\s*<p class="faq-answer">([\\s\\S]*?)</p>`,
    ),
  );
  if (!m) throw new Error(`FAQ question not found: ${question}`);
  return plainText(m[1]);
}

function faqLdAnswer(html: string, question: string): string {
  for (const body of ldBodies(html)) {
    const doc = JSON.parse(body) as { "@type"?: string; mainEntity?: any[] };
    if (doc["@type"] !== "FAQPage") continue;
    const q = (doc.mainEntity ?? []).find((e) => e.name === question);
    if (q) return String(q.acceptedAnswer.text).replace(/\s+/g, " ").trim();
  }
  throw new Error(`FAQPage JSON-LD question not found: ${question}`);
}

// Claude-plan / login wording is only true of the self-hosted version. The
// vocabulary follows CLO audit section 6 (Pro / Max / Team / Enterprise, login,
// seat, subscription limits and tokens), not just the spellings found on the site
// today. Alternatives never overlap (an overlap cannot be told apart by any probe),
// and every alternative is pinned by the ablation check below.
const PLAN_WORDING_RE =
  /Claude(?: Code)?(?:\.ai)? (?:plan|Pro|Max|subscription|account|login|log-in|sign-?in|seat)\b|Claude\.ai\b|\b(?:Pro|Max|Team|Enterprise) (?:plan|subscription|seat)\b|\bPro\/Max\b|\bPro,? (?:or|and) Max\b|\bMax (?:or|and) Pro\b|\bAnthropic (?:subscription|account|login|plan)\b|\b(?:sign|log)(?:s|ged|ed)? ?in (?:to |with )?(?:Claude|Anthropic)\b|subscription (?:limits|tokens?|auth\w*)|usage limits|setup-token|\boauth\b/i;
const HOSTED_RE =
  /(?<!self-)\b(?:hosted|cloud platform|managed|Soleur Cloud|SaaS|web platform|cloud (?:version|tier|plan|edition)|web app|web dashboard|app\.soleur\.ai)\b/i;
const PRIVACY_OVERCLAIM_RE =
  /\bprivate(?:ly)?\b|\bconfidential\b|zero-knowledge|\bencrypt\w*|\bnever (?:see|sees|leaves?|reads?|shares?|stores?|touch(?:es)?|access(?:es)?|views?)\b|(?:do(?:es)? not|don['’]t|doesn['’]t|did(?:n['’]t| not)|cannot|can['’]t|won['’]t|will not) (?:see|read|access|store|view|touch)\b|stays? (?:on|in) your (?:machine|device|laptop)|keeps? your (?:data|code|files) (?:safe|secure)/i;
// Soleur paying for, bundling or reselling Claude usage (CLO 6.1.3). The optional
// `(?:\w+ )?` in the first branch already absorbs "your "/"the ".
const COVERS_CLAUDE_RE =
  /\b(?:bundl|includ|resell|cover)\w* (?:\w+ )?Claude (?:usage|costs?)\b|\bpay(?:s|ing)? for (?:your |the )?Claude (?:usage|costs?)\b|\bClaude (?:usage|costs?) (?:is|are) (?:included|covered|bundled)\b/i;
// The permitted wording negates it ("plans don't include Claude usage"): a negation
// only counts when it sits directly before the verb, not anywhere in the sentence.
const NEGATES_COVER_RE = /(?:\bnot|\bnever|\bno|n['’]t)\s+(?:\w+\s+){0,2}(?:bundl|includ|resell|cover)/i;
// A hosted sentence that states a price or a way to buy must also say it is not
// available yet (there is a waitlist, no checkout), and must not contradict that.
const AVAILABILITY_RE =
  /\$\s?\d|\b\d+ dollars\b|per month|\/month|\bplans? (?:start|from)\b|choose a paid|upgrade to|sign up for|subscribe/i;
const NOT_YET_RE =
  /coming soon|waitlist|not yet|pre-?launch|\b(?:once|until|when|after)\b[^.]{0,40}\b(?:opens?|launch\w*|(?:is|are) available|(?:is|are) ready)\b/i;
const SELLS_NOW_RE =
  /\b(?:no|without) waitlist\b|\bcheckout\b|\bbuy now\b|\b(?:available|open|live) now\b|\bsign up now\b|\bstart (?:today|now)\b/i;
// No pricing tier has a priority-support line (Solo: email support; Startup: a
// priority execution queue), so the phrase on a marketing page contradicts the card.
const PRIORITY_SUPPORT_RE = /\bpriority support\b/i;
const FOOTER_HOSTED_LABEL = "Hosted version (coming soon)";

type Corpus = "marketing" | "blog";

// Marketing pages: any plan/login wording must be about the self-hosted version
// ALONE (a sentence that also names the hosted tier is flagged). Blog posts
// legitimately quote other products' Claude plans, so there the wording is only
// flagged when the same sentence names the hosted tier. Privacy over-claims are
// flagged wherever a sentence names the hosted tier; availability and support-tier
// wording are checked on marketing pages only (blog posts quote other products'
// prices). `assumeHosted` treats every sentence as hosted for the availability rule
// (used for pricing-page meta tags, which never name the tier but are about it).
function violationsIn(
  sentences: string[],
  corpus: Corpus,
  where = "",
  opts: { assumeHosted?: boolean } = {},
): string[] {
  const out: string[] = [];
  for (const s of sentences) {
    const plan = PLAN_WORDING_RE.test(s);
    const hosted = HOSTED_RE.test(s);
    const selfHost = /self-host/i.test(s);
    const planBad = corpus === "marketing" ? plan && (!selfHost || hosted) : plan && hosted;
    if (planBad) out.push(`${where}plan wording applied to hosted: "${s}"`);
    if (hosted && PRIVACY_OVERCLAIM_RE.test(s)) {
      out.push(`${where}hosted sentence over-claims privacy: "${s}"`);
    }
    if (hosted && COVERS_CLAUDE_RE.test(s) && !NEGATES_COVER_RE.test(s)) {
      out.push(`${where}hosted sentence says Soleur covers Claude usage: "${s}"`);
    }
    if (corpus === "marketing") {
      if ((hosted || opts.assumeHosted === true) && AVAILABILITY_RE.test(s) && !NOT_YET_RE.test(s)) {
        out.push(`${where}hosted availability stated without "coming soon": "${s}"`);
      }
      if (hosted && SELLS_NOW_RE.test(s)) {
        out.push(`${where}hosted tier described as available now: "${s}"`);
      }
      if (PRIORITY_SUPPORT_RE.test(s)) {
        out.push(`${where}"priority support" contradicts the pricing card (Solo: email support): "${s}"`);
      }
    }
  }
  return out;
}

// One function per corpus arm, so the self-tests below can drive each arm with a
// synthetic page: an arm that is dropped, or fed nothing, then fails a test
// instead of reading as a clean scan.
type Scan = { violations: string[]; hostedText: Map<string, number>; hostedLd: number; hostedAttr: number };
type Entry = { rel: string; html: string };

function scanPages(entries: Entry[], corpus: Corpus): Scan {
  const scan: Scan = { violations: [], hostedText: new Map(), hostedLd: 0, hostedAttr: 0 };
  for (const { rel, html } of entries) {
    const parts = pageParts(html);
    scan.violations.push(...violationsIn([...parts.text, ...parts.ld], corpus, `${rel}: `));
    // Meta tags and alt text of the pricing page are about the hosted tier even when
    // the sentence never names it, so the availability rule treats them as hosted.
    scan.violations.push(
      ...violationsIn(parts.attr, corpus, `${rel}: `, { assumeHosted: rel === "pricing/index.html" }),
    );
    scan.hostedText.set(rel, parts.text.filter((s) => HOSTED_RE.test(s) && s !== FOOTER_HOSTED_LABEL).length);
    scan.hostedLd += parts.ld.filter((s) => HOSTED_RE.test(s)).length;
    scan.hostedAttr += parts.attr.filter((s) => HOSTED_RE.test(s)).length;
  }
  return scan;
}

// llms.txt is Markdown: every line is its own unit, then split into sentences.
function scanLlms(raw: string): { violations: string[]; hosted: number } {
  const sentences = raw.split("\n").flatMap(sentencesOf);
  return {
    violations: violationsIn(sentences, "marketing", "llms.txt: "),
    hosted: sentences.filter((s) => HOSTED_RE.test(s)).length,
  };
}

// The assembled verdict, one record per corpus arm, so a test can assert each arm
// by name (dropping `llms` or running `blog` as `marketing` then fails a test).
function assemble(marketing: Entry[], blog: Entry[], llmsRaw: string) {
  return {
    marketing: scanPages(marketing, "marketing"),
    blog: scanPages(blog, "blog"),
    llms: scanLlms(llmsRaw),
  };
}

const synthetic = (head: string, body: string, rel = "x/index.html"): Entry => ({
  rel,
  html: `<html><head>${head}</head><body>${body}</body></html>`,
});
const LD = (obj: string) => `<script type="application/ld+json">${obj}</script>`;

// Ablation: for every group that has several alternatives, drop ONE alternative and
// recompile. The vocabulary above is restated from the CLO audit, so a member no
// probe depends on could be deleted with every row still green; the check below
// requires, per member, a probe the full regex matches and the ablated one does not.
function ablations(re: RegExp): { removed: string; re: RegExp }[] {
  const src = re.source;
  type G = { contentStart: number; seps: number[]; close: number };
  const root: G = { contentStart: 0, seps: [], close: src.length };
  const groups: G[] = [root];
  const stack: G[] = [root];
  let inClass = false;
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (c === "\\") {
      i++;
      continue;
    }
    if (inClass) {
      if (c === "]") inClass = false;
      continue;
    }
    if (c === "[") {
      inClass = true;
      continue;
    }
    if (c === "(") {
      let len = 1;
      if (src[i + 1] === "?") len = src.startsWith("(?<!", i) || src.startsWith("(?<=", i) ? 4 : 3;
      const g: G = { contentStart: i + len, seps: [], close: -1 };
      groups.push(g);
      stack.push(g);
      i += len - 1;
      continue;
    }
    if (c === ")") {
      stack.pop()!.close = i;
      continue;
    }
    if (c === "|") stack[stack.length - 1].seps.push(i);
  }
  const out: { removed: string; re: RegExp }[] = [];
  for (const g of groups) {
    if (g.seps.length === 0) continue;
    const bounds = [g.contentStart - 1, ...g.seps, g.close];
    for (let k = 0; k < bounds.length - 1; k++) {
      const a = bounds[k] + 1;
      const b = bounds[k + 1];
      const last = k === bounds.length - 2;
      const mutant = src.slice(0, last ? a - 1 : a) + src.slice(last ? b : b + 1);
      try {
        out.push({ removed: src.slice(a, b), re: new RegExp(mutant, re.flags) });
      } catch {
        // an ablation that no longer compiles is not a usable mutant
      }
    }
  }
  return out;
}

// Alternatives no probe depends on, for one regex.
function unpinnedAlternatives(re: RegExp, probes: string[]): string[] {
  return ablations(re)
    .filter(({ re: m }) => !probes.some((p) => re.test(p) && !m.test(p)))
    .map(({ removed }) => removed);
}

// One probe per alternative, each sentence matching the regex through that member only.
const PROBES: Record<string, { re: RegExp; probes: string[]; minAlternatives: number }> = {
  PLAN_WORDING_RE: {
    re: PLAN_WORDING_RE,
    minAlternatives: 38,
    probes: [
      "Hosted uses your Claude plan.", "Hosted uses your Claude Pro.", "Hosted uses your Claude Max.",
      "Hosted uses your Claude subscription.", "Hosted uses your Claude account.", "Hosted uses your Claude login.",
      "Hosted uses your Claude log-in.", "Hosted uses your Claude sign-in.", "Hosted uses your Claude seat.",
      "Hosted uses Claude.ai.",
      "Hosted uses a Pro plan.", "Hosted uses a Max plan.", "Hosted uses a Team plan.", "Hosted uses an Enterprise plan.",
      "Hosted uses a Team subscription.", "Hosted uses a Team seat.",
      "Hosted uses Pro/Max.", "Hosted uses Pro or Max.", "Hosted uses Pro and Max.",
      "Hosted uses Max or Pro.", "Hosted uses Max and Pro.",
      "Hosted uses your Anthropic subscription.", "Hosted uses your Anthropic account.",
      "Hosted uses your Anthropic login.", "Hosted uses your Anthropic plan.",
      "Hosted signs in with Claude.", "Hosted logged in with Anthropic.", "Hosted signed in with Anthropic.",
      "Hosted users log in with Claude.", "Hosted users sign in to Anthropic.", "Hosted users sign in with Claude.",
      "Hosted hits subscription limits.", "Hosted needs a subscription token.", "Hosted needs subscription authentication.",
      "Hosted hits usage limits.", "Hosted needs a setup-token.", "Hosted needs OAuth.",
    ],
  },
  HOSTED_RE: {
    re: HOSTED_RE,
    minAlternatives: 11,
    probes: [
      "The hosted platform.", "The cloud platform.", "The managed service.", "The Soleur Cloud.", "The SaaS.",
      "The web platform.", "The cloud version.", "The cloud tier.", "The cloud plan.", "The cloud edition.",
      "The web app.", "The web dashboard.", "Open app.soleur.ai.",
    ],
  },
  PRIVACY_OVERCLAIM_RE: {
    re: PRIVACY_OVERCLAIM_RE,
    minAlternatives: 30,
    probes: [
      "Data is private.", "It is confidential.", "It is zero-knowledge.", "Data is encrypted.",
      "We never see it.", "It never sees it.", "It never leaves.", "It never reads it.", "It never shares it.",
      "It never stores it.", "It never touches it.", "It never accesses it.", "It never views it.",
      "We do not see it.", "We don't see it.", "It doesn't see it.", "It didn't see it.", "It did not see it.",
      "We cannot see it.", "We can't see it.", "We won't see it.", "We will not see it.",
      "We do not read it.", "We do not access it.", "We do not store it.", "We do not view it.", "We do not touch it.",
      "Data stays on your machine.", "Data stays in your device.", "Data stays on your laptop.",
      "It keeps your data safe.", "It keeps your code secure.", "It keeps your files safe.",
    ],
  },
  COVERS_CLAUDE_RE: {
    re: COVERS_CLAUDE_RE,
    minAlternatives: 17,
    probes: [
      "Plans bundle Claude usage.", "Plans include Claude usage.", "Plans resell Claude usage.", "Plans cover Claude usage.",
      "Plans include unlimited Claude usage.", "Plans cover your Claude usage.", "Plans cover the Claude usage.",
      "Plans cover Claude costs.",
      "Soleur pays for Claude usage.", "Soleur is paying for Claude usage.", "Soleur pays for your Claude usage.",
      "Soleur pays for the Claude usage.", "Soleur pays for Claude costs.",
      "Claude usage is included.", "Claude usage are covered.", "Claude usage is bundled.", "Claude costs are included.",
    ],
  },
  NEGATES_COVER_RE: {
    re: NEGATES_COVER_RE,
    minAlternatives: 8,
    probes: [
      "Plans do not include it.", "Plans never include it.", "Plans no longer include it.", "Plans don't include it.",
      "Plans do not bundle it.", "Plans do not resell it.", "Plans do not cover it.",
    ],
  },
  AVAILABILITY_RE: {
    re: AVAILABILITY_RE,
    minAlternatives: 9,
    probes: [
      "Hosted costs $49.", "Hosted costs 49 dollars.", "Hosted costs ten per month.", "Hosted is 49/month.",
      "Hosted plans start low.", "Hosted plan from the start.", "Choose a paid tier.", "Upgrade to hosted.",
      "Sign up for hosted.", "Subscribe to hosted.",
    ],
  },
  NOT_YET_RE: {
    re: NOT_YET_RE,
    minAlternatives: 14,
    probes: [
      "Hosted costs $49, coming soon.", "Hosted costs $49, join the waitlist.", "Hosted costs $49, not yet.",
      "Hosted costs $49, pre-launch.", "Hosted costs $49 once it opens.", "Hosted costs $49 until launch.",
      "Hosted costs $49 when it opens.", "Hosted costs $49 after launch.", "Hosted costs $49 when it is available.",
      "Hosted costs $49 after it is ready.", "Hosted costs $49 when plans are available.",
      "Hosted costs $49 after plans are ready.",
    ],
  },
  SELLS_NOW_RE: {
    re: SELLS_NOW_RE,
    minAlternatives: 12,
    probes: [
      "Hosted is $49, no waitlist.", "Hosted is $49, without waitlist.", "Use the checkout.", "Buy now.",
      "Hosted is available now.", "Hosted is open now.", "Hosted is live now.", "Sign up now.", "Start today.", "Start now.",
    ],
  },
};

// What the page offers for sale, read from its structured data: an `availability`
// key anywhere, a BuyAction/OrderAction, or a potentialAction. While only a waitlist
// exists, none of them may appear on any marketing page.
function orderability(html: string): string[] {
  const why: string[] = [];
  const walk = (v: unknown): void => {
    if (Array.isArray(v)) v.forEach(walk);
    else if (v && typeof v === "object") {
      const o = v as Record<string, unknown>;
      if ("availability" in o) why.push(`availability: ${String(o.availability)}`);
      if ("potentialAction" in o) why.push("potentialAction");
      if (/^(?:Buy|Order|Trade|Rent)Action$/.test(String(o["@type"]))) why.push(`@type ${String(o["@type"])}`);
      Object.values(o).forEach(walk);
    }
  };
  for (const body of ldBodies(html)) walk(JSON.parse(body));
  return why;
}

// The pricing tier cards: each must carry a "Coming Soon" badge and a waitlist link
// before its own call to action (a waitlist link, or a mailto contact link for the
// custom tier), so a card cannot be turned into a buy button while
// the sentence-level guards (which only see hosted-token sentences) stay green.
function pricingCardIssues(html: string): string[] {
  const live = withoutInert(html);
  const labels = (live.match(/class="pricing-card-label"/g) ?? []).length;
  const cards = live.split('<div class="pricing-card">').slice(1);
  const issues: string[] = [];
  if (cards.length !== labels) issues.push(`${cards.length} cards but ${labels} tier labels`);
  if (cards.length < 3) issues.push(`only ${cards.length} pricing cards`);
  cards.forEach((chunk, n) => {
    const ctaAt = chunk.indexOf("pricing-card-cta");
    if (ctaAt === -1) {
      issues.push(`card ${n + 1} has no call to action`);
      return;
    }
    const region = chunk.slice(0, chunk.indexOf("</a>", ctaAt) + 4);
    if (!/<span class="pricing-card-badge">Coming Soon<\/span>/.test(region)) issues.push(`card ${n + 1} has no Coming Soon badge`);
    const cta = region.match(/<a\s([^>]*pricing-card-cta[^>]*)>([\s\S]*?)<\/a>/);
    const waitlist = cta && /href="[^"]*#waitlist"/.test(cta[1]) && /waitlist/i.test(cta[2]);
    const contact = cta && /href="mailto:[^"]+"/.test(cta[1]) && /\bcontact\b/i.test(cta[2]);
    if (!waitlist && !contact) issues.push(`card ${n + 1} call to action is neither a waitlist link nor a contact link`);
  });
  return issues;
}

// A page that shows "Last updated <date>" must carry the same date in its WebPage
// dateModified (and so in the sitemap): page-freshness.njk asks for `date:` to equal
// `last_updated:`, and a crawler that re-fetches on lastmod otherwise keeps stale copy.
function freshnessMismatch(html: string): string | null {
  const byline = html.match(/<span class="page-meta-updated">Last updated <time datetime="([^"]+)">/);
  if (!byline) return null;
  const mods: string[] = [];
  const walk = (v: unknown): void => {
    if (Array.isArray(v)) v.forEach(walk);
    else if (v && typeof v === "object") {
      const o = v as Record<string, unknown>;
      if (typeof o.dateModified === "string") mods.push(o.dateModified);
      Object.values(o).forEach(walk);
    }
  };
  for (const body of ldBodies(html)) walk(JSON.parse(body));
  if (mods.length === 0) return `byline ${byline[1]} but no dateModified`;
  const off = mods.filter((d) => !d.startsWith(byline[1]));
  return off.length ? `byline ${byline[1]} but dateModified ${off.join(", ")}` : null;
}

describe("#9579 Guard 1 — hosted-claims copy (no Claude-plan wording on hosted, no 'private', nothing orderable)", () => {
  // Known gap, tracked in #9589: blog posts that state the hosted privacy posture
  // without naming the hosted tier ("No code is stored on Soleur servers") carry no
  // hosted token, so the sentence-local privacy rule cannot see them.
  test("no marketing or blog sentence applies Claude plan/login wording to hosted, over-claims hosted privacy, or sells an unavailable hosted tier", () => {
    const llmsPath = join(SITE, "llms.txt");
    expect(existsSync(llmsPath), "llms.txt is built").toBe(true);
    const arms = assemble(marketingPages(), blogPages(), readFileSync(llmsPath, "utf8"));
    // Each arm by name, so a dropped or mis-corpused arm cannot hide behind the others.
    expect(arms.marketing.violations, `marketing:\n${arms.marketing.violations.join("\n")}`).toEqual([]);
    expect(arms.blog.violations, `blog:\n${arms.blog.violations.join("\n")}`).toEqual([]);
    expect(arms.llms.violations, `llms:\n${arms.llms.violations.join("\n")}`).toEqual([]);
    // Floors, calibrated to the current corpus (measured, with one unit of slack where
    // a legitimate copy edit should not break them): an empty page glob, or a scanner
    // that reads only part of a page, must not read as clean.
    expect(arms.marketing.hostedText.size, "marketing pages scanned").toBeGreaterThanOrEqual(20);
    expect(arms.blog.hostedText.size, "blog pages scanned").toBeGreaterThanOrEqual(25);
    const total = [...arms.marketing.hostedText.values()].reduce((a, b) => a + b, 0);
    expect(total, "hosted sentences in marketing visible text (footer label excluded)").toBeGreaterThanOrEqual(40);
    expect(arms.marketing.hostedLd, "hosted sentences in marketing JSON-LD").toBeGreaterThanOrEqual(20);
    expect(arms.marketing.hostedAttr, "hosted sentences in marketing attributes").toBeGreaterThanOrEqual(20);
    const blogHosted = [...arms.blog.hostedText.values()].reduce((a, b) => a + b, 0);
    expect(blogHosted, "hosted sentences in blog visible text").toBeGreaterThanOrEqual(19);
    // Per page: the pages the CLO audit binds, and every page this PR rewrote, each
    // carry hosted wording, so blinding one of them (aggregate still above its floor)
    // cannot read as clean. The company-as-a-service count includes SaaS comparison
    // sentences (9 measured, none about the hosted tier), so it only pins that the
    // page is still read.
    const perPage: [string, number][] = [
      ["index.html", 4], ["pricing/index.html", 5], ["getting-started/index.html", 7],
      ["about/index.html", 2], ["company-as-a-service/index.html", 8], ["vision/index.html", 1],
      ["compare/soleur-vs-cursor/index.html", 2], ["compare/soleur-vs-devin/index.html", 1],
    ];
    for (const [rel, min] of perPage) {
      expect(arms.marketing.hostedText.get(rel) ?? 0, `${rel} hosted sentences`).toBeGreaterThanOrEqual(min);
    }
    expect(arms.llms.hosted, "hosted sentences in llms.txt").toBeGreaterThanOrEqual(3);
  });

  test("rule self-test: known-bad sentences per arm are flagged, known-good wording is not", () => {
    const bad: [string, Corpus][] = [
      ["You choose the Claude plan that fits your usage.", "marketing"],
      ["Hosted plan users pay their own Claude Pro, Max, or API costs.", "marketing"],
      ["Sign in to hosted Soleur with your Claude account.", "marketing"],
      ["Hosted uses your Claude.ai login.", "marketing"],
      ["Your Anthropic subscription covers the hosted version.", "marketing"],
      ["Hosted plans run on your Max plan.", "marketing"],
      ["Hosted runs on your Claude Enterprise plan.", "marketing"],
      ["Hosted Soleur uses your Claude Team seat.", "marketing"],
      ["Hosted runs on your Pro/Max login.", "marketing"],
      ["Use your Anthropic account on the hosted version.", "marketing"],
      ["Hosted Soleur lets you sign in with Claude.", "marketing"],
      ["Hosted users are signed in with Anthropic.", "marketing"],
      ["Hosted runs on your Claude usage limits.", "marketing"],
      ["Hosted needs your Claude subscription token.", "marketing"],
      ["Self-hosted is free; hosted usage draws on your Claude Pro plan.", "marketing"],
      ["Hosted Soleur runs on your Claude Pro plan.", "blog"],
      ["Hosted Soleur: your Claude usage is included.", "marketing"],
      ["Hosted plans bundle Claude usage.", "marketing"],
      ["Hosted includes unlimited Claude usage.", "marketing"],
      ["Soleur pays for your Claude usage on hosted.", "marketing"],
      ["Hosted plans include Claude usage, no API key needed.", "marketing"],
      ["Hosted plans include Claude usage, with no extra fee.", "marketing"],
      ["Soleur Cloud keeps your data private.", "marketing"],
      ["The cloud version keeps your data private.", "marketing"],
      ["Your workspace data stays private on app.soleur.ai.", "marketing"],
      ["The hosted version never sees your code.", "marketing"],
      ["The hosted version never touches your code.", "marketing"],
      ["Hosted workspaces are handled privately.", "marketing"],
      ["Hosted workspaces are confidential.", "marketing"],
      ["The web platform is zero-knowledge.", "marketing"],
      ["Hosted data is end-to-end encrypted.", "marketing"],
      ["Hosted data is encrypted at rest.", "marketing"],
      ["We do not read your hosted files.", "marketing"],
      ["We don't read your hosted files.", "marketing"],
      ["We don’t read your hosted files.", "marketing"],
      ["The hosted version doesn’t read your files.", "marketing"],
      ["The hosted version does not store your code.", "marketing"],
      ["We cannot view your hosted files.", "marketing"],
      ["Hosted data stays on your machine.", "marketing"],
      ["The hosted version keeps your data safe.", "marketing"],
      ["Hosted plans start at $49 per month.", "marketing"],
      ["Choose a paid tier for managed infrastructure.", "marketing"],
      ["Upgrade to the hosted version whenever you are ready.", "marketing"],
      ["Hosted plans start at $49 per month, no waitlist.", "marketing"],
      ["Hosted plans start at $49 per month, checkout opens now.", "marketing"],
      ["Hosted plans start at $49 per month, the dashboard opens in a new tab.", "marketing"],
      ["The hosted version adds priority support.", "marketing"],
      ["Priority support is included.", "marketing"],
    ];
    const good: [string, Corpus][] = [
      ["Self-hosted runs with your Claude plan or an Anthropic API key.", "marketing"],
      ["Hosted plans use your own Anthropic API key, billed by Anthropic to you.", "marketing"],
      ["Soleur plans don’t include Claude usage.", "marketing"],
      ["Hosted plans don’t include Claude usage.", "marketing"],
      ["Hosted plans no longer include Claude usage.", "marketing"],
      ["It runs inside your own Claude Code, so you pay for your own Claude usage.", "marketing"],
      ["The hosted version is coming soon, from $49 per month.", "marketing"],
      ["Hosted plans start at $49 per month once the waitlist opens.", "marketing"],
      ["Hosted plans are $49 per month once hosted plans open.", "marketing"],
      ["Join the waitlist for the hosted version.", "marketing"],
      ["The hosted version adds email support.", "marketing"],
      ["Startup adds a priority execution queue.", "marketing"],
      ["Cowork is bundled with every Claude subscription.", "blog"],
      ["Claude Pro runs $20/month.", "blog"],
      ["SaaS tools work in isolation.", "marketing"],
    ];
    for (const [s, corpus] of bad) {
      expect(violationsIn([s], corpus).length, `flagged: ${s}`).toBeGreaterThan(0);
    }
    for (const [s, corpus] of good) {
      expect(violationsIn([s], corpus), `not flagged: ${s}`).toEqual([]);
    }
    // The availability rule is marketing-only and `assumeHosted` extends it to meta tags.
    expect(violationsIn(["Plans start at $49 per month."], "marketing"), "no hosted token, not assumed").toEqual([]);
    expect(violationsIn(["Plans start at $49 per month."], "marketing", "", { assumeHosted: true }).length).toBeGreaterThan(0);
    expect(violationsIn(["Hosted plans start at $49 per month."], "blog"), "blog quotes other products' prices").toEqual([]);
  });

  test("every alternative of every restated rule is pinned by a probe (ablation), and the detector can fail", () => {
    for (const [name, { re, probes, minAlternatives }] of Object.entries(PROBES)) {
      const all = ablations(re);
      expect(all.length, `${name}: ablations generated`).toBeGreaterThanOrEqual(minAlternatives);
      expect(probes.every((p) => re.test(p)), `${name}: every probe matches the full rule`).toBe(true);
      expect(unpinnedAlternatives(re, probes), `${name}: alternatives no probe depends on`).toEqual([]);
    }
    // Control 1: with no probes, every alternative is unpinned (the detector is not vacuous).
    expect(unpinnedAlternatives(PLAN_WORDING_RE, []).length).toBe(ablations(PLAN_WORDING_RE).length);
    // Control 2: dropping the one probe a member depends on reports exactly that member.
    const without = PROBES.PLAN_WORDING_RE.probes.filter((p) => p !== "Hosted uses your Claude seat.");
    expect(unpinnedAlternatives(PLAN_WORDING_RE, without)).toEqual(["seat"]);
    // Control 3: the generator sees nested groups, character classes and escapes.
    expect(ablations(/a(?:b|c)[|x]\|d/).map((a) => a.removed)).toEqual(["b", "c"]);
  });

  test("arm wiring: a bad sentence that appears in only ONE input arm is still flagged, and each corpus keeps its own rules", () => {
    const bad = "Hosted Soleur is private.";
    const arms: [string, Entry, Corpus][] = [
      ["marketing visible text", synthetic("", `<p>${bad}</p>`), "marketing"],
      ["marketing JSON-LD", synthetic(LD(`{"@type":"Thing","description":"${bad}"}`), ""), "marketing"],
      ["marketing alt", synthetic("", `<img alt="${bad}">`), "marketing"],
      ["marketing meta description (single-quoted)", synthetic(`<meta name='description' content='${bad}'>`, ""), "marketing"],
      ["marketing meta description (unquoted name)", synthetic(`<meta name=description content="${bad}">`, ""), "marketing"],
      ["marketing og:description", synthetic(`<meta property="og:description" content="${bad}">`, ""), "marketing"],
      ["marketing title after a quoted >", synthetic("", `<img alt="x > y" title="${bad}">`), "marketing"],
      ["marketing aria-label with spaces around =", synthetic("", `<a aria-label = "${bad}">x</a>`), "marketing"],
      ["marketing unquoted placeholder", synthetic("", "<input placeholder=Hosted.Soleur.is.private>"), "marketing"],
      ["blog visible text", synthetic("", `<p>${bad}</p>`), "blog"],
      ["blog JSON-LD", synthetic(LD(`{"@type":"Thing","description":"${bad}"}`), ""), "blog"],
      ["blog meta description", synthetic(`<meta name="description" content="${bad}">`, ""), "blog"],
    ];
    for (const [arm, page, corpus] of arms) {
      expect(scanPages([page], corpus).violations.length, `${arm} arm is wired`).toBeGreaterThan(0);
    }
    expect(scanLlms(`- [x](u): ${bad}\n`).violations.length, "llms.txt arm is wired").toBeGreaterThan(0);
    // A zero-width character splits a word in every arm unless the arm normalises.
    const soft = String.fromCharCode(0xad);
    const split = `Hosted Soleur is pri${soft}vate.`;
    expect(scanPages([synthetic(LD(`{"@type":"Thing","description":"${split}"}`), "")], "marketing").violations.length, "JSON-LD normalises").toBeGreaterThan(0);
    expect(scanLlms(`- [x](u): ${split}\n`).violations.length, "llms.txt normalises").toBeGreaterThan(0);
    expect(scanPages([synthetic(`<meta name="description" content="${split}">`, "")], "marketing").violations.length, "attributes normalise").toBeGreaterThan(0);
    // The same arms stay quiet on clean content (the control for the assertions above).
    const clean = synthetic(
      `<meta name="description" content="Hosted Soleur is coming soon."> ${LD('{"@type":"Thing","description":"Hosted is coming soon."}')}`,
      '<p>Hosted is coming soon.</p><img alt="Hosted is coming soon.">',
    );
    expect(scanPages([clean], "marketing").violations).toEqual([]);
    expect(scanPages([clean], "blog").violations).toEqual([]);
    expect(scanLlms("- [x](u): Hosted is coming soon.\n").violations).toEqual([]);
    // Markdown list items carry no final period, so only the per-line split keeps a
    // self-hosted-scoped entry from merging with a hosted one into a flagged "sentence".
    expect(
      scanLlms("- [A](u): Self-hosted runs with your Claude plan\n- [B](u): The hosted version is coming soon\n").violations,
      "llms.txt entries are scanned line by line",
    ).toEqual([]);
    // A non-content meta tag and a non-meta `content` attribute are not claims.
    expect(attributeTexts('<meta name="viewport" content="Hosted is private."><div content="Hosted is private.">')).toEqual([]);

    // Assembly: the verdict is assembled per arm with the right corpus. A marketing-only
    // rule (availability) fires in the marketing arm and the llms arm, never in blog; the
    // blog rule (hosted AND plan wording in one sentence) fires in blog.
    const price = "Hosted plans start at $49 per month.";
    const planBlog = "Hosted Soleur runs on your Claude Pro plan.";
    const a = assemble([synthetic("", `<p>${price}</p>`)], [synthetic("", `<p>${price}</p><p>${planBlog}</p>`)], `- [x](u): ${price}\n`);
    expect(a.marketing.violations.length, "marketing arm: availability rule").toBe(1);
    expect(a.blog.violations.length, "blog arm: only the plan sentence, not the price").toBe(1);
    expect(a.blog.violations[0]).toContain("plan wording");
    expect(a.llms.violations.length, "llms arm runs as marketing").toBe(1);
    expect(assemble([], [], "").llms.hosted, "empty llms").toBe(0);
  });

  test("pricing meta tags are about the hosted tier even when no sentence names it", () => {
    const meta = (c: string) => synthetic(`<meta name="description" content="${c}">`, "", "pricing/index.html");
    expect(scanPages([meta("All 8 departments from $49/month.")], "marketing").violations.length, "price without coming soon").toBeGreaterThan(0);
    expect(scanPages([meta("All 8 departments from $49/month once hosted plans open.")], "marketing").violations).toEqual([]);
    expect(
      scanPages([synthetic('<meta name="description" content="All 8 departments from $49/month.">', "", "about/index.html")], "marketing").violations,
      "other pages are not assumed hosted",
    ).toEqual([]);
  });

  test("pricing tier cards each carry a Coming Soon badge and a waitlist call to action", () => {
    expect(pricingCardIssues(readSite("pricing/index.html"))).toEqual([]);
    const card = (badge: string, cta: string, label = '<span class="pricing-card-label">Solo</span>') =>
      `<div class="pricing-card">${label}${badge}${cta}</div>`;
    const ok = card('<span class="pricing-card-badge">Coming Soon</span>', '<a href="/pricing/#waitlist" class="btn pricing-card-cta">Join the waitlist</a>');
    expect(pricingCardIssues(ok.repeat(3))).toEqual([]);
    expect(pricingCardIssues(ok.repeat(2)).join(), "too few cards").toContain("only 2 pricing cards");
    const noBadge = card("", '<a href="/pricing/#waitlist" class="btn pricing-card-cta">Join the waitlist</a>');
    expect(pricingCardIssues(ok + ok + noBadge).join(), "badge removed").toContain("card 3 has no Coming Soon badge");
    const buy = card('<span class="pricing-card-badge">Coming Soon</span>', '<a href="/checkout" class="btn pricing-card-cta">Subscribe</a>');
    expect(pricingCardIssues(ok + ok + buy).join(), "buy button").toContain("card 3 call to action is neither");
    const contactCard = card('<span class="pricing-card-badge">Coming Soon</span>', '<a href="mailto:hello@soleur.ai" class="btn pricing-card-cta">Contact Us</a>');
    expect(pricingCardIssues(ok + ok + contactCard), "a contact card is allowed").toEqual([]);
    const fakeContact = card('<span class="pricing-card-badge">Coming Soon</span>', '<a href="/checkout" class="btn pricing-card-cta">Contact Us</a>');
    expect(pricingCardIssues(ok + ok + fakeContact).join(), "contact text on a non-mailto link").toContain("neither");
    const badgeAfter = card("", '<a href="/pricing/#waitlist" class="btn pricing-card-cta">Join the waitlist</a><span class="pricing-card-badge">Coming Soon</span>');
    expect(pricingCardIssues(ok + ok + badgeAfter).join(), "badge only after the cta").toContain("card 3 has no Coming Soon badge");
    const extraLabel = `${ok}${ok}${ok}<span class="pricing-card-label">Orphan</span>`;
    expect(pricingCardIssues(extraLabel).join(), "label without a card").toContain("tier labels");
  });

  test("no marketing page declares anything orderable in structured data; the hosted offer says coming soon", () => {
    const offenders: string[] = [];
    const pages = marketingPages();
    for (const { rel, html } of pages) for (const w of orderability(html)) offenders.push(`${rel}: ${w}`);
    expect(pages.length, "marketing pages scanned").toBeGreaterThanOrEqual(20);
    expect(offenders, offenders.join("\n")).toEqual([]);
    // orderability self-test: every way of declaring an orderable offer is seen.
    const ld = (extra: string) => LD(`{"@type":"Thing"${extra}}`);
    expect(orderability(ld(',"offers":{"@type":"Offer","availability":"https://schema.org/PreOrder"}')).length, "nested availability").toBe(1);
    expect(orderability(ld(',"offers":[{"@type":"Offer","availability":"https://schema.org/InStock"}]')).length, "availability in a list").toBe(1);
    expect(orderability(ld(',"potentialAction":{"@type":"ViewAction"}')).length, "potentialAction").toBe(1);
    expect(orderability(LD('{"@type":"BuyAction"}')).length, "BuyAction").toBe(1);
    expect(orderability(ld(',"offers":{"@type":"Offer","price":"49"}')), "price alone is not availability").toEqual([]);
    // The one hosted offer: coming soon in its name, waitlist and email support in its description.
    const offers: Record<string, unknown>[] = [];
    const walk = (v: unknown): void => {
      if (Array.isArray(v)) v.forEach(walk);
      else if (v && typeof v === "object") {
        if ((v as Record<string, unknown>)["@type"] === "Offer") offers.push(v as Record<string, unknown>);
        Object.values(v).forEach(walk);
      }
    };
    for (const body of ldBodies(readSite("index.html"))) walk(JSON.parse(body));
    const hosted = offers.filter((o) => HOSTED_RE.test(String(o.name)));
    expect(hosted.length, "exactly one hosted offer in the homepage JSON-LD").toBe(1);
    expect(String(hosted[0].name), "hosted offer name").toMatch(/coming soon/i);
    expect(String(hosted[0].description), "hosted offer description names the waitlist").toMatch(/waitlist/i);
    expect(String(hosted[0].description), "hosted offer support wording matches the pricing card").toMatch(/email support/i);
    const llms = readFileSync(join(SITE, "llms.txt"), "utf8").split("\n");
    for (const label of ["Getting Started", "Pricing"]) {
      const line = llms.find((l) => l.startsWith(`- [${label}]`));
      expect(line, `llms.txt ${label} entry present`).toBeDefined();
      expect(line!, `llms.txt ${label} entry says coming soon`).toMatch(/coming soon/i);
    }
  });

  test("a page's visible 'Last updated' date and its WebPage dateModified agree", () => {
    const withByline = marketingPages().filter(({ html }) => /page-meta-updated/.test(html));
    expect(withByline.length, "pages with a visible byline").toBeGreaterThanOrEqual(7);
    const mismatches = withByline
      .map(({ rel, html }) => [rel, freshnessMismatch(html)] as const)
      .filter(([, m]) => m !== null)
      .map(([rel, m]) => `${rel}: ${m}`);
    expect(mismatches, mismatches.join("\n")).toEqual([]);
    // self-test
    const page = (byline: string, mod: string) =>
      `<span class="page-meta-updated">Last updated <time datetime="${byline}">x</time></span>${LD(`{"@type":"WebPage","dateModified":"${mod}"}`)}`;
    expect(freshnessMismatch(page("2026-10-06", "2026-10-06T00:00:00Z")), "agree").toBeNull();
    expect(freshnessMismatch(page("2026-10-06", "2026-06-01T00:00:00Z")), "disagree").toContain("dateModified");
    expect(freshnessMismatch(`<span class="page-meta-updated">Last updated <time datetime="2026-10-06">x</time></span>`), "no dateModified").toContain("no dateModified");
    expect(freshnessMismatch("<p>no byline</p>"), "no byline").toBeNull();
  });

  test("edited FAQ answers are identical in the visible answer and the FAQPage JSON-LD twin, and carry the claim phrase", () => {
    const rows: { page: string; question: string; phrase?: string }[] = [
      { page: "pricing/index.html", question: "Do I pay for Claude separately?", phrase: "billed by Anthropic to you" },
      { page: "pricing/index.html", question: "Is there a free option?" },
      { page: "index.html", question: "Is Soleur free?", phrase: "billed by Anthropic to you" },
      { page: "index.html", question: "How do I get started?", phrase: "Anthropic API key" },
      { page: "index.html", question: "What is Soleur?" },
      { page: "getting-started/index.html", question: "What is the difference between the hosted version and self-hosted?", phrase: "(coming soon)" },
    ];
    for (const { page, question, phrase } of rows) {
      const html = readSite(page);
      const visible = faqAnswer(html, question);
      const twin = faqLdAnswer(html, question);
      expect(visible, `${page} "${question}" visible equals JSON-LD twin`).toBe(twin);
      if (phrase) expect(visible, `${page} "${question}"`).toContain(phrase);
    }
  });
});

describe("#9579 Guard 2 — computed counts on the homepage (re-pin of #3165)", () => {
  const STATS_JS = resolve(REPO_ROOT, "plugins/soleur/docs/_data/stats.js");
  const NUM_WORD = "(?:sixty|seventy|eighty|ninety|one hundred|a hundred)(?:[- ](?:one|two|three|four|five|six|seven|eight|nine))?";
  const LITERAL_COUNT_RES = [
    /\b\d{2,3}\+?(?:\s|&nbsp;|<[^>]{1,40}>)+(?:[A-Za-z-]+\s+){0,3}(?:agents|skills)\b/gi,
    /\b\d{2,3}\+?-(?:agent|skill)s?\b/gi,
    new RegExp(`\\b${NUM_WORD}\\s+(?:[A-Za-z-]+\\s+){0,3}(?:agents|skills)\\b`, "gi"),
  ];

  test("raw index.njk and page-freshness.njk carry no literal count in prose", () => {
    const sources = [
      { rel: "index.njk", floorOk: false, minLines: 200 },
      { rel: "_includes/page-freshness.njk", floorOk: true, minLines: 25 },
    ];
    const hits: string[] = [];
    for (const { rel, floorOk, minLines } of sources) {
      const src = readFileSync(resolve(REPO_ROOT, "plugins/soleur/docs", rel), "utf8");
      // Floor per file: a scan that examined nothing must not read as clean.
      expect(src.split("\n").length, `${rel} lines scanned`).toBeGreaterThanOrEqual(minLines);
      // Whole-source scan (not per line): a count hard-wrapped across two source
      // lines ("67\n agents") is still one count to a reader.
      for (const re of LITERAL_COUNT_RES) {
        for (const m of src.matchAll(re)) {
          // page-freshness.njk keeps the 60+ soft floor for every page without the flag.
          if (floorOk && m[0].startsWith("60+")) continue;
          hits.push(`${rel}:${src.slice(0, m.index).split("\n").length}: ${m[0].replace(/\s+/g, " ")}`);
        }
      }
    }
    expect(hits, hits.join("\n")).toEqual([]);
  });

  test("counting-pattern self-test: the spellings the scan exists to catch are caught", () => {
    const caught = [
      "67 AI agents", "<strong>67</strong> agents", "67&nbsp;agents", "67 fully autonomous AI agents",
      "a 67-agent team", "Sixty AI agents", "103 workflow skills", "67\n    AI agents",
    ];
    for (const s of caught) {
      expect(LITERAL_COUNT_RES.some((re) => [...s.matchAll(re)].length > 0), `caught: ${s}`).toBe(true);
    }
    expect(LITERAL_COUNT_RES.some((re) => [...("{{ stats.agents }} AI agents").matchAll(re)].length > 0)).toBe(false);
  });

  test("built homepage hero-sub, FAQ (HTML + JSON-LD), final CTA, summary and stat strip carry the stats.js counts", async () => {
    const stats = (await import(STATS_JS)).default() as { agents: number; skills: number; departments: number };
    expect(stats.agents, "stats.agents is a positive integer").toBeGreaterThan(0);
    expect(stats.skills, "stats.skills is a positive integer").toBeGreaterThan(0);
    const html = readSite("index.html");
    const agentsRe = new RegExp(`\\b${stats.agents}\\s+(?:AI\\s+)?agents\\b`);
    const skillsRe = new RegExp(`\\b${stats.skills}\\s+(?:AI\\s+)?skills\\b`);
    const grab = (re: RegExp, what: string): string => {
      const m = html.match(re);
      expect(m, `homepage ${what} present`).not.toBeNull();
      return plainText(m![1]);
    };
    const surfaces: { what: string; text: string }[] = [
      { what: "hero-sub", text: grab(/<p class="hero-sub">([\s\S]*?)<\/p>/, "hero-sub") },
      { what: "page summary", text: grab(/<p class="page-summary">([\s\S]*?)<\/p>/, "page summary") },
      { what: "FAQ 'What is Soleur?'", text: faqAnswer(html, "What is Soleur?") },
      { what: "FAQPage JSON-LD 'What is Soleur?'", text: faqLdAnswer(html, "What is Soleur?") },
      { what: "final CTA", text: grab(/<section class="landing-cta">[\s\S]*?<\/h2>\s*<p>([\s\S]*?)<\/p>/, "final CTA") },
    ];
    for (const { what, text } of surfaces) {
      expect(text, `${what} agents count`).toMatch(agentsRe);
      expect(text, `${what} skills count`).toMatch(skillsRe);
      expect(text.includes("60+"), `${what} has no 60+ soft floor`).toBe(false);
    }
    // The stat strip: value and label sit in sibling blocks, so pin the pair.
    const strip = new Map<string, number>();
    for (const m of html.matchAll(
      /<div class="landing-stat-value"[^>]*>(\d+)<\/div>\s*<div class="landing-stat-label">([^<]+)<\/div>/g,
    )) {
      strip.set(m[2].trim(), Number(m[1]));
    }
    expect(strip.get("AI Agents"), "stat strip agents").toBe(stats.agents);
    expect(strip.get("Skills"), "stat strip skills").toBe(stats.skills);
    expect(strip.get("Departments"), "stat strip departments").toBe(stats.departments);
    // statsLastVerified: a real ISO date, and the homepage renders exactly that value.
    const verified = JSON.parse(readFileSync(SITE_JSON, "utf8")).statsLastVerified as string;
    expect(verified, "statsLastVerified is an ISO date").toMatch(/^\d{4}-\d{2}-\d{2}$/);
    const stamps = [...html.matchAll(/data-last-verified="([^"]*)"/g)].map((m) => m[1]);
    expect(stamps.length, "stat tiles carry the verification date").toBeGreaterThanOrEqual(2);
    expect(new Set(stamps), "every tile renders site.json statsLastVerified").toEqual(new Set([verified]));
  });

  test("pricing, about, vision, agents, skills, getting-started keep the 60+ soft floor in their page summary (opt-in flag is homepage-only)", () => {
    const rels = [
      "pricing/index.html", "about/index.html", "vision/index.html",
      "agents/index.html", "skills/index.html", "getting-started/index.html",
    ];
    let checked = 0;
    for (const rel of rels) {
      const html = readSite(rel);
      const m = html.match(/<p class="page-summary">([\s\S]*?)<\/p>/);
      expect(m, `${rel} has a page summary`).not.toBeNull();
      const text = plainText(m![1]);
      expect(text.includes("60+"), `${rel} summary keeps the soft floor`).toBe(true);
      expect(/\b\d{2,3}\s+(?:AI\s+)?agents\b/.test(text), `${rel} summary has no exact agent count`).toBe(false);
      checked++;
    }
    expect(checked, "all cascade pages asserted").toBe(rels.length);
  });
});

// Scope: the Inc./Amodei/Krieger attribution on every marketing page (visible text,
// attributes and structured data) plus structured data on every page. Blog posts
// carry the same Inc. sources and are tracked in #9589.
const INC_SOURCE_RE = /<a\s[^>]*href="https:\/\/www\.inc\.com\/ben-sherry\/[^"]+"[^>]*>/i;
const CLAIM_KEYS = ["subjectOf", "citation", "isBasedOn"];

function pagesWithClaimKeys(entries: Entry[]): string[] {
  return entries
    .filter(({ html }) => ldBodies(html).some((b) => hasKey(JSON.parse(b), CLAIM_KEYS)))
    .map(({ rel }) => rel);
}
const citingInc = (entries: Entry[]): string[] =>
  entries.filter(({ html }) => jsonLdStrings(html).some((x) => /inc\.com/i.test(x))).map(({ rel }) => rel);

// Each phrase paired with a sentence it must catch: an emptied or mistyped pattern
// then fails the self-test instead of reading as a clean scan.
const BANNED_ATTRIBUTION: [RegExp, string][] = [
  [/as seen in/i, "As seen in Inc."],
  [/featured in inc/i, "Featured in Inc. magazine"],
  [/next couple of years/i, "he said in the next couple of years"],
  [/i would not be surprised/i, "I would not be surprised if"],
  [/predicted in an interview with inc/i, "predicted in an interview with Inc.com"],
  [/\btold inc\b/i, "He told Inc.com that"],
  [/\bassigns?\b[^.]{0,30}\b(?:probabilit|likelihood|chance)/i, "Anthropic's CEO assigns 70-80% probability"],
  [/\bpredict(?:s|ed)\b[^.]{0,30}\b70.{0,3}80/i, "he predicted a 70-80% chance"],
];

// Every text arm, each normalised through sentencesOf (whitespace, hidden characters).
function attributionOffenders(entries: Entry[]): string[] {
  const offenders: string[] = [];
  for (const { rel, html } of entries) {
    const live = [
      ...sentencesOf(visibleText(html)),
      ...attributeTexts(html).flatMap(sentencesOf),
      ...jsonLdStrings(html).flatMap(sentencesOf),
    ];
    for (const [re] of BANNED_ATTRIBUTION) {
      for (const t of live) if (re.test(t)) offenders.push(`${rel} matches ${re}: "${t.slice(0, 100)}"`);
    }
  }
  return offenders;
}

// The Inc. source must be a real anchor in live markup, not text inside a comment,
// <template> or <noscript>.
const liveIncAnchor = (html: string): boolean => INC_SOURCE_RE.test(withoutInert(html));

const NON_AFFILIATION = "is an independent product, not affiliated with, sponsored by, or endorsed by Anthropic.";
const footerHasNonAffiliation = (html: string): boolean => {
  const footer = withoutInert(html).match(/<footer[\s\S]*?<\/footer>/);
  return footer !== null && plainText(footer[0]).includes(NON_AFFILIATION);
};

// Why an opening tag hides what it contains. Attributes are read quote-aware in all
// three value forms, names case-insensitively; `hidden` hides whatever its value.
const HIDING_CLASSES = ["sr-only", "visually-hidden", "hidden", "d-none"];
function hidingReasons(openTag: string): string[] {
  const why: string[] = [];
  const attrs = new Map<string, string>();
  const body = openTag.replace(/^<\s*[A-Za-z][A-Za-z0-9]*/, "");
  for (const m of body.matchAll(/([^\s=/>"'`]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g)) {
    attrs.set(m[1].toLowerCase(), m[2] ?? m[3] ?? m[4] ?? "");
  }
  if (attrs.has("hidden")) why.push("hidden attribute");
  if ((attrs.get("aria-hidden") ?? "").toLowerCase() === "true") why.push("aria-hidden=true");
  const style = (attrs.get("style") ?? "").toLowerCase();
  if (/(?:^|;)\s*display\s*:\s*none/.test(style)) why.push("display:none");
  if (/(?:^|;)\s*visibility\s*:\s*(?:hidden|collapse)/.test(style)) why.push("visibility:hidden");
  if (/(?:^|;)\s*opacity\s*:\s*0(?![.\d])/.test(style)) why.push("opacity:0");
  if (/(?:^|;)\s*(?:max-)?height\s*:\s*0(?![.\d])/.test(style)) why.push("height:0");
  if (/(?:^|;)\s*font-size\s*:\s*0(?![.\d])/.test(style)) why.push("font-size:0");
  if (/(?:^|;)\s*(?:-webkit-text-fill-|)color\s*:\s*transparent/.test(style)) why.push("transparent text");
  if (/(?:^|;)\s*clip-path\s*:\s*inset\(\s*(?:50|100)%/.test(style)) why.push("clip-path");
  if (/(?:^|;)\s*text-indent\s*:\s*-\d{3,}/.test(style)) why.push("text-indent");
  for (const t of (attrs.get("class") ?? "").split(/\s+/).filter(Boolean)) {
    if (HIDING_CLASSES.includes(t)) why.push(`class ${t}`);
  }
  return why;
}

// Every ancestor of `targetIndex` that hides its contents, with the reason. The walk starts
// at the document root, so <html>, <body>, <main> and the hero section all count.
function hiddenAncestors(doc: string, targetIndex: number): string[] {
  return openAncestors(doc, targetIndex).flatMap((tag) => hidingReasons(tag).map((r) => `${tag}: ${r}`));
}

describe("#9579 Guard 3 — attribution (no false Inc.com subject claim, no unverified quotation)", () => {
  test("loop self-test: every claim key is flagged, at the top level and nested, and an Inc.com string anywhere in JSON-LD is flagged", () => {
    const ld = (extra: string) =>
      `<script type="application/ld+json" nonce="x">{"@type":"Organization"${extra}}</script>`;
    const flagged = pagesWithClaimKeys([
      { rel: "index.html", html: ld("") },
      { rel: "x/index.html", html: ld(',"subjectOf":{"@type":"NewsArticle"}') },
    ]);
    expect(flagged).toEqual(["x/index.html"]);
    for (const key of CLAIM_KEYS) {
      expect(pagesWithClaimKeys([{ rel: "top", html: ld(`,"${key}":"x"`) }]), `${key} at the top level`).toEqual(["top"]);
      expect(pagesWithClaimKeys([{ rel: "deep", html: ld(`,"a":[{"b":{"${key}":"x"}}]`) }]), `${key} nested`).toEqual(["deep"]);
    }
    expect(citingInc([{ rel: "n", html: ld(',"a":[{"b":["see https://www.inc.com/x"]}]') }]), "nested Inc.com string").toEqual(["n"]);
    expect(citingInc([{ rel: "ok", html: ld(',"a":"https://example.com"') }])).toEqual([]);
  });

  test("no built page declares a subjectOf/citation claim or cites Inc.com in structured data", () => {
    const all = allPages();
    expect(all.length, "pages scanned").toBeGreaterThanOrEqual(60);
    expect(pagesWithClaimKeys(all)).toEqual([]);
    expect(citingInc(all), "pages whose JSON-LD names Inc.com").toEqual([]);
  });

  test("banned-phrase self-test: every pattern catches its own sample", () => {
    for (const [re, sample] of BANNED_ATTRIBUTION) expect(re.test(sample), `${re} catches "${sample}"`).toBe(true);
  });

  test("arm wiring: a banned phrase in only ONE arm (text, attribute, JSON-LD), including whitespace and hidden-character variants, is flagged", () => {
    const phrase = "As seen in Inc.";
    const spaced = "As seen  in Inc.";
    const soft = String.fromCharCode(0xad);
    const hidden = `As se${soft}en in Inc.`;
    const wrapped = "As seen\n    in Inc.";
    for (const p of [phrase, spaced, hidden, wrapped]) {
      const label = JSON.stringify(p);
      expect(attributionOffenders([synthetic("", `<p>${p}</p>`)]).length, `text ${label}`).toBeGreaterThan(0);
      expect(attributionOffenders([synthetic(`<meta property="og:description" content="${p}">`, "")]).length, `attribute ${label}`).toBeGreaterThan(0);
      expect(attributionOffenders([synthetic(LD(`{"@type":"Thing","description":${JSON.stringify(p)}}`), "")]).length, `JSON-LD ${label}`).toBeGreaterThan(0);
    }
    expect(attributionOffenders([synthetic("", "<p>Inc. reported it.</p>")]), "clean page").toEqual([]);
  });

  test("the Inc. source must be a live anchor and the non-affiliation line must sit in the footer element", () => {
    const a = '<a href="https://www.inc.com/ben-sherry/x/1" rel="noopener">as Inc. reported</a>';
    expect(liveIncAnchor(`<p>${a}</p>`), "live anchor").toBe(true);
    expect(liveIncAnchor(`<!-- ${a} -->`), "anchor inside a comment").toBe(false);
    expect(liveIncAnchor(`<noscript>${a}</noscript>`), "anchor inside noscript").toBe(false);
    expect(liveIncAnchor(`<template>${a}</template>`), "anchor inside template").toBe(false);
    expect(liveIncAnchor('<p>https://www.inc.com/ben-sherry/x/1</p>'), "bare text is not a link").toBe(false);
    expect(liveIncAnchor('<a href="https://example.com/">https://www.inc.com/ben-sherry/x/1</a>'), "wrong target").toBe(false);
    const line = `Soleur ${NON_AFFILIATION}`;
    expect(footerHasNonAffiliation(`<footer><span>${line}</span></footer>`), "in footer").toBe(true);
    expect(footerHasNonAffiliation(`<p>${line}</p><footer>x</footer>`), "outside the footer").toBe(false);
    expect(footerHasNonAffiliation(`<footer><!-- ${line} --></footer>`), "comment in the footer").toBe(false);
    expect(footerHasNonAffiliation(`<p>${line}</p>`), "no footer").toBe(false);
  });

  test("no marketing page carries 'As seen in', the old paraphrase, or a 'told Inc.' framing; the Inc. source stays a real link", () => {
    const pages = marketingPages();
    expect(pages.length, "marketing pages scanned").toBeGreaterThanOrEqual(20);
    const offenders = attributionOffenders(pages);
    expect(offenders, offenders.join("\n")).toEqual([]);
    // The attribution is still present and is a real anchor (not text inside a comment).
    for (const rel of ["index.html", "about/index.html", "vision/index.html", "company-as-a-service/index.html"]) {
      expect(liveIncAnchor(readSite(rel)), `${rel} links the Inc. source`).toBe(true);
    }
    for (const rel of ["about/index.html", "vision/index.html"]) {
      expect(plainText(readSite(rel)), `${rel} says "as Inc. reported"`).toContain("as Inc. reported");
    }
    expect(plainText(readSite("company-as-a-service/index.html")), "CaaS dates the Krieger title").toContain(
      "then Anthropic’s chief product officer",
    );
  });

  test("the homepage quote section carries no quotation marks and keeps the non-affiliation line", () => {
    const home = withoutInert(readSite("index.html"));
    const quote = home.match(/<section class="landing-quote">([\s\S]*?)<\/section>/);
    expect(quote, "quote section present").not.toBeNull();
    expect(/<(?:blockquote|q)[\s>]/i.test(quote![1]), "no quotation element in the quote section").toBe(false);
    const text = plainText(quote![1]);
    const quoteMarks = String.fromCharCode(0x22, 0x201c, 0x201d, 0xab, 0xbb);
    expect([...text].filter((c) => quoteMarks.includes(c)), "no quotation marks around the attribution").toEqual([]);
    expect(text.includes("not affiliated with"), "non-affiliation line sits in the quote section").toBe(true);
  });

  test("the site-wide non-affiliation line is in the footer element itself", () => {
    for (const rel of ["index.html", "pricing/index.html", "about/index.html"]) {
      expect(footerHasNonAffiliation(readSite(rel)), `${rel} footer line`).toBe(true);
    }
  });
});

describe("#9579 hiding predicate — which opening tags hide their contents", () => {
  test.each([
    ["<form hidden>", "hidden attribute"],
    ['<form hidden="">', "hidden attribute"],
    ["<form hidden=hidden>", "hidden attribute"],
    ['<form HIDDEN class="x">', "hidden attribute"],
    ['<form hidden="until-found">', "hidden attribute"],
    ['<div aria-hidden="true">', "aria-hidden=true"],
    ["<div aria-hidden='true'>", "aria-hidden=true"],
    ['<div style="display:none">', "display:none"],
    ["<div style='display: none'>", "display:none"],
    ["<div style=display:none>", "display:none"],
    ['<div style="margin:0; visibility:hidden">', "visibility:hidden"],
    ['<div style="opacity:0">', "opacity:0"],
    ['<div style="height:0;overflow:hidden">', "height:0"],
    ['<div style="max-height:0">', "height:0"],
    ['<div style="font-size:0">', "font-size:0"],
    ['<div style="color:transparent">', "transparent text"],
    ['<div style="-webkit-text-fill-color:transparent">', "transparent text"],
    ['<div style="clip-path:inset(100%)">', "clip-path"],
    ['<div style="text-indent:-9999px">', "text-indent"],
    ['<div class="card sr-only">', "class sr-only"],
    ["<div class='d-none'>", "class d-none"],
    ["<div class=visually-hidden>", "class visually-hidden"],
    ['<div class="hidden">', "class hidden"],
  ])("%s hides (%s)", (tag, reason) => {
    expect(hidingReasons(tag)).toContain(reason);
  });

  test("hiddenAncestors reports every hiding ancestor, outermost first, and only those", () => {
    const doc = (open: string) => `<html><body><main>${open}<section class="landing-hero"><div><p id="t">x</p></div></section></main></body></html>`;
    const at = (html: string) => html.indexOf('<p id="t">');
    const clean = doc("");
    expect(hiddenAncestors(clean, at(clean)), "clean document").toEqual([]);
    for (const [open, why] of [
      ["<div hidden>", "hidden attribute"], ["<div style='display:none'>", "display:none"],
      ['<div aria-hidden="true">', "aria-hidden=true"], ['<div class="d-none">', "class d-none"],
    ] as const) {
      const html = doc(open);
      const got = hiddenAncestors(html, at(html));
      expect(got.length, `${open} reported once`).toBe(1);
      expect(got[0], `${open} reason`).toContain(why);
    }
    const body = clean.replace("<body>", "<body hidden>");
    expect(hiddenAncestors(body, at(body)).join(), "the walk includes <body>").toContain("<body hidden>");
    const html2 = clean.replace("<html>", '<html style="display:none">');
    expect(hiddenAncestors(html2, at(html2)).join(), "the walk includes <html>").toContain("display:none");
    const closed = '<div hidden></div><section><p id="t">x</p></section>';
    expect(hiddenAncestors(closed, closed.indexOf('<p id="t">')), "a closed hidden sibling is not an ancestor").toEqual([]);
  });

  test.each([
    '<div class="card">', '<div style="margin:0">', '<div style="opacity:0.5">', '<div style="height:0.5rem">',
    '<div aria-hidden="false">', '<div data-hidden="x">', '<div style="color:#fff">', "<section>", '<a href="/x" title="hidden">',
  ])("%s does not hide", (tag) => {
    expect(hidingReasons(tag)).toEqual([]);
  });
});

describe("#9579 hero structure — privacy line visible, one install CTA, hosted form labelled, compare link", () => {
  const classTokens = (attrs: string): string[] =>
    (attrs.match(/\bclass="([^"]*)"/)?.[1] ?? "").split(/\s+/).filter(Boolean);

  test("hero follows the committed wireframe contract", () => {
    // Inert markup (comments, <template>, <noscript>) is not what a visitor sees.
    const live = withoutInert(readSite("index.html"));
    const hero = live.match(/<section class="landing-hero">([\s\S]*?)<\/section>/);
    expect(hero, "hero section present").not.toBeNull();
    const h = hero![1];

    // Privacy line: visible, id kept, described-by resolves, same text as /pricing/.
    const privOpen = h.match(/<p([^>]*\bid="homepage-waitlist-privacy"[^>]*)>([\s\S]*?)<\/p>/);
    expect(privOpen, "privacy <p> present").not.toBeNull();
    const tokens = classTokens(privOpen![1]);
    expect(tokens, "privacy line uses the visible newsletter-privacy class").toContain("newsletter-privacy");
    for (const hiding of HIDING_CLASSES) {
      expect(tokens.includes(hiding), `privacy line is not class ${hiding}`).toBe(false);
    }
    expect(/\bhidden\b|\bstyle=/.test(privOpen![1].replace(/\bclass="[^"]*"/, "")), "privacy line has no hidden/style attribute").toBe(false);
    // Nor does any element that contains it (the walk starts at the document root, so the
    // hero section, <main> and <body> count too).
    expect(hidingReasons(`<p${privOpen![1]}>`), "privacy line's own tag hides nothing").toEqual([]);
    const heroAt = live.indexOf(hero![0]);
    const ancestors = openAncestors(live, heroAt + hero![0].indexOf(privOpen![0]));
    expect(ancestors.length, "privacy line sits inside the hero's markup").toBeGreaterThan(2);
    expect(hiddenAncestors(live, heroAt + hero![0].indexOf(privOpen![0])), "no ancestor of the privacy line hides it").toEqual([]);
    expect(h.includes('aria-describedby="homepage-waitlist-privacy"'), "input described by the privacy line").toBe(true);
    const pricing = withoutInert(readSite("pricing/index.html"));
    const pPriv = pricing.match(/<p[^>]*\bid="newsletter-privacy-pricing-waitlist"[^>]*>([\s\S]*?)<\/p>/);
    expect(pPriv, "pricing privacy <p> present").not.toBeNull();
    const heroPriv = plainText(privOpen![2]);
    expect(heroPriv, "hero and pricing privacy text are identical").toBe(plainText(pPriv![1]));
    expect(heroPriv, "names the processor").toContain("Buttondown");
    expect(heroPriv, "links the Privacy Policy").toContain("Privacy Policy");

    // Exactly one primary CTA in the hero: the tagged self-hosted install link.
    const primaries = [...h.matchAll(/\bclass="([^"]*)"/g)].filter((m) =>
      m[1].split(/\s+/).includes("btn-primary"),
    );
    expect(primaries.length, "exactly one btn-primary in the hero").toBe(1);
    const installs = [...h.matchAll(/<a\s([^>]*)>([\s\S]*?)<\/a>/g)].filter((m) =>
      /\bhref="\/getting-started\/#self-hosted"/.test(m[1]),
    );
    expect(installs.length, "exactly one install CTA").toBe(1);
    const installTokens = classTokens(installs[0][1]);
    expect(installTokens, "install CTA is the primary button").toContain("btn-primary");
    expect(installTokens, "install CTA is tagged for Plausible via its class").toContain(
      "plausible-event-name=Hero+Self-host+Click",
    );
    const installText = plainText(installs[0][2]);
    expect(installText, "install button label").toBe("Get the self-hosted version");
    expect(/\bfree\b/i.test(installText), "no 'free' on the install button").toBe(false);

    // Hosted submit is secondary; one compare link; old links gone.
    const form = h.match(/<form[\s\S]*?<\/form>/);
    expect(form, "hosted form present").not.toBeNull();
    expect(/<button type="submit" class="btn btn-secondary">/.test(form![0]), "hosted submit is secondary").toBe(true);
    expect(h.includes('href="/compare/soleur-vs-cursor/"'), "hero links the Cursor comparison page").toBe(true);
    expect(h.includes('href="#soleur-vs-copilots"'), "old in-page anchor link removed from the hero").toBe(false);

    // Plan line is two separate sentences; hosted one says API key only.
    const sentences = sentencesOf(visibleText(h));
    expect(sentences.some((s) => s.startsWith("Self-hosted runs inside your own Claude Code")), "self-hosted plan sentence").toBe(true);
    const hostedLine = sentences.find((s) => s.startsWith("Hosted version (coming soon): bring your own Anthropic API key"));
    expect(hostedLine, "hosted plan sentence present").toBeDefined();
    expect(hostedLine!.includes("billed by Anthropic to you"), "hosted sentence names who bills").toBe(true);
  });

  test("a Discord line follows the FAQ list inside the FAQ section and uses site.discord", () => {
    // Live markup only: a link moved into a comment is not a link.
    const html = withoutInert(readSite("index.html"));
    const discord = JSON.parse(readFileSync(SITE_JSON, "utf8")).discord as string;
    const faqStart = html.indexOf('class="faq-list"');
    expect(faqStart, "FAQ list located").toBeGreaterThan(-1);
    const sectionEnd = html.indexOf("</section>", faqStart);
    const lastItemEnd = html.lastIndexOf("</details>", sectionEnd);
    const linkPos = html.indexOf(`href="${discord}"`, lastItemEnd);
    // The footer also links Discord, so the link must sit before the FAQ section closes.
    expect(linkPos > lastItemEnd && linkPos < sectionEnd, "Discord link sits after the last FAQ item, before the section closes").toBe(true);
    expect(plainText(html.slice(lastItemEnd, sectionEnd)), "line names Discord").toContain("Discord");
  });
});
