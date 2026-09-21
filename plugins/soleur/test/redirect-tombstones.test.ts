// Guard 1 (#8364) — redirect tombstones: every public URL that STOPPED being
// served under plugins/soleur/docs/ (deleted post, reslug, retired page,
// changed permalink) must be covered by a declared edge 301, re-served by a
// live page, or carry a reasoned exemption.
//
// Why this gate exists: the drift-guard's expected map is a hand-written
// snapshot — it pins URLs someone remembered. It cannot see a URL nobody
// wrote down, so the reslug class (the ai-agents-cron post, /pages/articles.html,
// /pages/commands.html, /pages/mcp-servers.html — all live-404 on 2026-09-20)
// escaped every guard. This census derives the expectation set from git
// history, the only artifact that records both "was live" and "now gone".
//
// Event sources (see lib/tombstone-census.ts):
//   - git log --diff-filter=RD -M --name-status -- plugins/soleur/docs/
//   - git log -p -G'permalink:' -- plugins/soleur/docs/   (reslug detection)
//
// Coverage set (the union the census checks against):
//   literal `item` source_urls + local.blog_redirect_pairs expansion +
//   local.tombstone_redirect_pairs expansion + the seo_page_redirects zone
//   ruleset's `http.request.uri.path eq "..."` literals.
//
// The history anchor exists so the gate fails loudly — never vacuously — if
// history is unavailable (shallow clone) or rewritten: cat-file -e plus a
// --is-shallow-repository check throw. The census itself runs over ALL
// history so the one-time seed audit (the five tombstone_redirect_pairs seeds
// + two exemptions below) is continuously re-verified, not frozen at author
// time.
//
// Mutation battery (synthetic repos via mkdtemp + git init — git *reports*
// are input shapes, exercised per plan-sharp-edges #5):
//   uncovered D           -> uncovered non-empty
//   covered D             -> green (control — the assert is not vacuous)
//   date-only R           -> only the OLD dated family is required
//   permalink removal     -> old permalink URL set required
//   D under _data/        -> ignored (non-page input)
//   unreachable baseline  -> throws (never a silent skip)

import { describe, test, expect, afterAll } from "bun:test";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import {
  allDeclaredSources,
  bulkRedirectPairs,
  extractLocalMap,
  stripTfComments,
} from "./lib/bulk-redirect-pairs";
import {
  assertBaselineReachable,
  classifyCensus,
  collectNeeds,
  extractResourceBody,
  liveUrlPaths,
  type UrlNeed,
} from "./lib/tombstone-census";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const DOCS_PREFIX = "plugins/soleur/docs";

// History-integrity canary — the PR-B squash merge that deleted the
// meta-refresh machinery. The census enumerates ALL history; this anchor is
// preflighted (plus a shallow-repository check) so a clone missing history
// fails loudly instead of reporting "nothing died".
const HISTORY_ANCHOR = "35259f264";

// Exemptions: paths whose events are allowed to carry no redirect, each with
// an issue ref justifying "the URL set this file served is covered by
// construction" or "the file never served a public URL". An entry no event
// consumes is flagged stale — exemptions rot like anything else.
const TOMBSTONE_EXEMPT: Record<string, { ref: string; reason: string }> = {
  "plugins/soleur/docs/blog/redirects.njk": {
    ref: "#3328",
    reason:
      "generated meta-refresh stub template (permalink 'blog/{{ redirect.dateSlug }}/index.html'); the URL set it emitted IS the blog_redirect_pairs edge list, verified live before deletion in #8358",
  },
  "plugins/soleur/docs/page-redirects.njk": {
    ref: "#3328",
    reason:
      "generated meta-refresh stub template (permalink '{{ redirect.from }}'); emitted URL set IS the bulk list, verified live before deletion in #8358",
  },
};

const TF = resolve(REPO_ROOT, "apps/web-platform/infra/seo-bulk-redirects.tf");
const RULESETS_TF = resolve(
  REPO_ROOT,
  "apps/web-platform/infra/seo-rulesets.tf",
);

/** source_url -> path form: `soleur.ai/x/y` -> `/x/y`. Non-apex hosts skipped. */
function sourceToPath(source: string): string | null {
  if (!source.startsWith("soleur.ai")) return null;
  const path = source.slice("soleur.ai".length);
  return path === "" ? "/" : path;
}

/** The declared redirect source set, as URL paths. */
function declaredCoverage(): Set<string> {
  const tf = readFileSync(TF, "utf8");
  const set = new Set<string>();
  for (const src of allDeclaredSources(tf).keys()) {
    const p = sourceToPath(src);
    if (p) set.add(p);
  }
  const ruleset = extractResourceBody(
    stripTfComments(readFileSync(RULESETS_TF, "utf8")),
    "cloudflare_ruleset",
    "seo_page_redirects",
  );
  // The path literals live INSIDE quoted HCL strings — the inner quotes are
  // backslash-escaped (`eq \"/pages/x.html\"`), so match the escaped form.
  for (const m of ruleset.matchAll(
    /http\.request\.uri\.path eq \\"([^\\"]+)\\"/g,
  )) {
    set.add(m[1]);
  }
  return set;
}

/** Copy-paste-ready tombstone_redirect_pairs entry for an uncovered URL. */
function suggestedEntry(need: UrlNeed): string {
  const prefix = need.url.replace(/^\/+|\/+$/g, "").replace(/\/index\.html$/, "");
  const target = need.url.startsWith("/blog/") ? "https://soleur.ai/blog/" : "https://soleur.ai/";
  return `    "${prefix}" = "${target}"  # tombstone: <issue> — stranded by ${need.commit.slice(0, 9)} "${need.subject}" (${need.kind}, ${need.path})`;
}

function censusReport(
  uncovered: UrlNeed[],
  underivable: { path: string; commit: string }[],
  stale: string[],
): string {
  const parts: string[] = [];
  if (uncovered.length) {
    parts.push(
      `Uncovered dead URLs (${uncovered.length}):\n` +
        uncovered
          .map(
            (n) =>
              `  ${n.url}  <- ${n.kind} of ${n.path} @ ${n.commit.slice(0, 9)} "${n.subject}"`,
          )
          .join("\n") +
        "\n\nRemediation — add to local.tombstone_redirect_pairs in " +
        "apps/web-platform/infra/seo-bulk-redirects.tf (each entry expands to " +
        "the 3 URL shapes), or add a TOMBSTONE_EXEMPT entry with an issue ref " +
        "if the URL was never live:\n" +
        uncovered.map(suggestedEntry).join("\n"),
    );
  }
  if (underivable.length) {
    parts.push(
      `Underivable template permalinks with no exemption (${underivable.length}):\n` +
        underivable
          .map((u) => `  ${u.path} @ ${u.commit.slice(0, 9)}`)
          .join("\n") +
        "\nAdd a TOMBSTONE_EXEMPT entry with an issue ref.",
    );
  }
  if (stale.length) {
    parts.push(
      `Stale TOMBSTONE_EXEMPT entries (no event consumed them — remove or re-justify):\n` +
        stale.map((p) => `  ${p}`).join("\n"),
    );
  }
  return parts.join("\n\n");
}

// -- synthetic-repo harness (mutation battery) --------------------------------

const tmpDirs: string[] = [];
afterAll(() => {
  for (const d of tmpDirs) rmSync(d, { recursive: true, force: true });
});

function sh(dir: string, cmd: string, args: string[]): string {
  return execFileSync(cmd, args, { cwd: dir, encoding: "utf8" });
}

function commitAll(dir: string, msg: string): string {
  sh(dir, "git", ["add", "-A"]);
  sh(dir, "git", [
    "-c",
    "user.email=tombstone@test",
    "-c",
    "user.name=tombstone-test",
    "commit",
    "-qm",
    msg,
  ]);
  return sh(dir, "git", ["rev-parse", "HEAD"]).trim();
}

function synthRepo(): string {
  const dir = mkdtempSync(join(tmpdir(), "tombstone-census-"));
  tmpDirs.push(dir);
  sh(dir, "git", ["init", "-q"]);
  mkdirSync(join(dir, DOCS_PREFIX, "blog"), { recursive: true });
  mkdirSync(join(dir, DOCS_PREFIX, "pages"), { recursive: true });
  return dir;
}

function writeDoc(dir: string, rel: string, body: string): void {
  const p = join(dir, DOCS_PREFIX, rel);
  mkdirSync(dirname(p), { recursive: true });
  writeFileSync(p, body);
}

const DATED_POST = (slug: string, date: string) => `---
title: ${slug}
---
post body for ${slug}
`;

describe("Guard 1 — redirect tombstones: dead-URL census over docs history (#8364)", () => {
  test("history anchor is reachable and the clone is not shallow — never a vacuous census", () => {
    assertBaselineReachable(REPO_ROOT, HISTORY_ANCHOR);
  });

  test("every deleted/renamed/reslugged docs URL is covered, live, or exempt", () => {
    const census = collectNeeds(REPO_ROOT, DOCS_PREFIX);
    // Anti-vacuity: history enumeration must have produced events — a broken
    // enumerator must not read as "nothing to cover".
    expect(
      census.fileEvents,
      "git log --diff-filter=RD produced zero events — the enumerator broke",
    ).toBeGreaterThan(0);
    expect(
      census.permalinkEvents,
      "git log -G'permalink:' produced zero events — the enumerator broke",
    ).toBeGreaterThan(0);

    const result = classifyCensus(
      census,
      declaredCoverage(),
      liveUrlPaths(REPO_ROOT, DOCS_PREFIX),
      new Set(Object.keys(TOMBSTONE_EXEMPT)),
    );

    const report = censusReport(
      result.uncovered,
      result.underivableUnexempt,
      result.staleExempt,
    );
    expect(
      report,
      `tombstone census failed (${census.fileEvents} file events, ${census.permalinkEvents} permalink events scanned):\n\n${report}`,
    ).toBe("");
    // Non-vacuity on the positive side: the seed audit's covered set must be
    // non-trivial or the census is not exercising coverage at all.
    expect(
      result.counts.covered + result.counts.live + result.counts.exempt,
      "census classified zero URLs — coverage set or live set is empty",
    ).toBeGreaterThan(0);
  });

  test("the seed tombstones exist in local.tombstone_redirect_pairs (live-404 verified 2026-09-20)", () => {
    // The census sees these URLs already (all history is enumerated); the
    // pin is that the seed entries THEMSELVES cannot silently regress — a
    // dropped map key must fail here, not just shift the coverage check.
    const pairs = extractLocalMap(
      readFileSync(TF, "utf8"),
      "tombstone_redirect_pairs",
    );
    const expected = new Map<string, string>([
      // #5215 — post published+unpublished 2026-06-12; both URL families died.
      [
        "blog/ai-agents-cron-without-exfiltrating-secrets",
        "https://soleur.ai/blog/",
      ],
      [
        "blog/2026-06-12-ai-agents-cron-without-exfiltrating-secrets",
        "https://soleur.ai/blog/",
      ],
      // #1851 — articles index reslug; the /articles/ items cover only the
      // post-reslug shape.
      ["pages/articles.html", "https://soleur.ai/blog/"],
      // #118 — nav-restructure deletions ("redundant/empty" pages).
      ["pages/commands.html", "https://soleur.ai/"],
      ["pages/mcp-servers.html", "https://soleur.ai/"],
    ]);
    const missing: string[] = [];
    const mismatched: string[] = [];
    for (const [prefix, target] of expected) {
      if (!pairs.has(prefix)) missing.push(prefix);
      else if (pairs.get(prefix) !== target)
        mismatched.push(`${prefix} -> ${pairs.get(prefix)} (expected ${target})`);
    }
    expect(
      missing,
      `tombstone pairs missing (dead URLs would 404): ${missing.join(", ")}`,
    ).toEqual([]);
    expect(
      mismatched,
      `tombstone pairs with wrong target: ${mismatched.join(", ")}`,
    ).toEqual([]);
  });

  // -- parser mutations (Guard 5a) -------------------------------------------

  test("parser: a duplicate literal source_url throws naming both items", () => {
    const tf = `resource "cloudflare_list" "x" {
  item { value { redirect { source_url = "soleur.ai/a/" target_url = "https://soleur.ai/b/" } } }
  item { value { redirect { source_url = "soleur.ai/a/" target_url = "https://soleur.ai/c/" } } }
}`;
    expect(() => bulkRedirectPairs(tf)).toThrow(/duplicate source_url/);
  });

  test("parser: a tombstone key colliding with a blog-pair expansion throws", () => {
    const tf = `locals {
  blog_redirect_pairs = { "2026-01-01-x" = "x" }
  tombstone_redirect_pairs = { "blog/2026-01-01-x" = "https://soleur.ai/blog/" }
}`;
    expect(() => allDeclaredSources(tf)).toThrow(
      /duplicate source_url "soleur\.ai\/blog\/2026-01-01-x/,
    );
  });

  test("parser: tombstone pairs expand to all 3 exact-match shapes", () => {
    const tf = `locals {
  blog_redirect_pairs = {}
  tombstone_redirect_pairs = { "pages/gone.html" = "https://soleur.ai/" }
}`;
    const sources = [...allDeclaredSources(tf).keys()];
    expect(sources).toContain("soleur.ai/pages/gone.html/");
    expect(sources).toContain("soleur.ai/pages/gone.html/index.html");
    expect(sources).toContain("soleur.ai/pages/gone.html");
  });

  // -- mutation battery ------------------------------------------------------

  test("mutation: uncovered D of a dated post reds with both URL families", () => {
    const dir = synthRepo();
    writeDoc(dir, "blog/2026-01-01-x.md", DATED_POST("x", "2026-01-01"));
    commitAll(dir, "add post");
    rmSync(join(dir, DOCS_PREFIX, "blog/2026-01-01-x.md"));
    commitAll(dir, "delete post");

    const result = classifyCensus(
      collectNeeds(dir, DOCS_PREFIX),
      new Set(),
      liveUrlPaths(dir, DOCS_PREFIX),
      new Set(),
    );
    const urls = result.uncovered.map((n) => n.url).sort();
    // canonical family + dated family = 6 shapes
    expect(urls).toEqual([
      "/blog/2026-01-01-x",
      "/blog/2026-01-01-x/",
      "/blog/2026-01-01-x/index.html",
      "/blog/x",
      "/blog/x/",
      "/blog/x/index.html",
    ]);
  });

  test("mutation: covered D is green (control — the assert is not vacuous)", () => {
    const dir = synthRepo();
    writeDoc(dir, "blog/2026-01-01-x.md", DATED_POST("x", "2026-01-01"));
    commitAll(dir, "add post");
    rmSync(join(dir, DOCS_PREFIX, "blog/2026-01-01-x.md"));
    commitAll(dir, "delete post");

    const coverage = new Set([
      "/blog/2026-01-01-x",
      "/blog/2026-01-01-x/",
      "/blog/2026-01-01-x/index.html",
      "/blog/x",
      "/blog/x/",
      "/blog/x/index.html",
    ]);
    const result = classifyCensus(
      collectNeeds(dir, DOCS_PREFIX),
      coverage,
      liveUrlPaths(dir, DOCS_PREFIX),
      new Set(),
    );
    expect(result.uncovered).toEqual([]);
  });

  test("mutation: date-only rename requires the OLD dated family, not the canonical", () => {
    const dir = synthRepo();
    writeDoc(dir, "blog/2026-01-01-x.md", DATED_POST("x", "2026-01-01"));
    commitAll(dir, "add post");
    sh(dir, "git", [
      "mv",
      `${DOCS_PREFIX}/blog/2026-01-01-x.md`,
      `${DOCS_PREFIX}/blog/2026-01-02-x.md`,
    ]);
    commitAll(dir, "date-only rename");

    const result = classifyCensus(
      collectNeeds(dir, DOCS_PREFIX),
      new Set(),
      liveUrlPaths(dir, DOCS_PREFIX),
      new Set(),
    );
    const urls = result.uncovered.map((n) => n.url).sort();
    // Canonical /blog/x/ is re-served by the rename — only the stranded dated
    // alias may be required.
    expect(urls).toEqual([
      "/blog/2026-01-01-x",
      "/blog/2026-01-01-x/",
      "/blog/2026-01-01-x/index.html",
    ]);
  });

  test("mutation: permalink removal on a surviving file requires the old URL", () => {
    const dir = synthRepo();
    writeDoc(
      dir,
      "pages/foo.md",
      "---\npermalink: old-page/\n---\nbody\n",
    );
    commitAll(dir, "add page");
    writeDoc(
      dir,
      "pages/foo.md",
      "---\npermalink: new-page/\n---\nbody\n",
    );
    commitAll(dir, "reslug");

    const result = classifyCensus(
      collectNeeds(dir, DOCS_PREFIX),
      new Set(),
      liveUrlPaths(dir, DOCS_PREFIX),
      new Set(),
    );
    const urls = result.uncovered.map((n) => n.url).sort();
    expect(urls).toEqual(["/old-page", "/old-page/", "/old-page/index.html"]);
    // /new-page/ is live (the file exists at HEAD with that permalink) and
    // must NOT appear as a need.
    expect(urls.some((u) => u.includes("new-page"))).toBe(false);
  });

  test("mutation: restored permalink is live, but the window URL is honestly stranded", () => {
    const dir = synthRepo();
    writeDoc(dir, "pages/foo.md", "---\npermalink: foo/\n---\nbody\n");
    commitAll(dir, "add page");
    writeDoc(dir, "pages/foo.md", "---\n# permalink removed\n---\nbody\n");
    commitAll(dir, "remove permalink");
    writeDoc(dir, "pages/foo.md", "---\npermalink: foo/\n---\nbody\n");
    commitAll(dir, "restore permalink");

    const result = classifyCensus(
      collectNeeds(dir, DOCS_PREFIX),
      new Set(),
      liveUrlPaths(dir, DOCS_PREFIX),
      new Set(),
    );
    // /foo/ itself is live again (restored at HEAD) and must NOT be demanded.
    // But /pages/foo/ — the path-derived URL the file served during the
    // remove→restore window — is genuinely dead and IS demanded. The
    // before-vs-after diff model reports this honestly.
    const urls = result.uncovered.map((n) => n.url).sort();
    expect(urls).toEqual(["/pages/foo", "/pages/foo/", "/pages/foo/index.html"]);
    expect(urls.some((u) => u === "/foo" || u.startsWith("/foo/"))).toBe(false);
  });

  test("mutation: D under _data/ is out of scope", () => {
    const dir = synthRepo();
    mkdirSync(join(dir, DOCS_PREFIX, "_data"), { recursive: true });
    writeDoc(dir, "_data/nav.js", "export default {};\n");
    commitAll(dir, "add data file");
    rmSync(join(dir, DOCS_PREFIX, "_data/nav.js"));
    commitAll(dir, "delete data file");

    const census = collectNeeds(dir, DOCS_PREFIX);
    expect(census.needs).toEqual([]);
  });

  test("mutation: unreachable baseline throws — never a silent skip", () => {
    const dir = synthRepo();
    writeDoc(dir, "pages/x.md", "---\npermalink: x/\n---\nbody\n");
    commitAll(dir, "seed");
    expect(() => assertBaselineReachable(dir, "deadbeefdeadbeef")).toThrow(
      /not a commit|vacuous/i,
    );
  });

  test("mutation: template-permalink deletion requires an exemption", () => {
    const dir = synthRepo();
    writeDoc(
      dir,
      "page-redirects.njk",
      "---\npermalink: \"{{ redirect.from }}\"\n---\nstub\n",
    );
    commitAll(dir, "add template");
    rmSync(join(dir, DOCS_PREFIX, "page-redirects.njk"));
    commitAll(dir, "delete template");

    const census = collectNeeds(dir, DOCS_PREFIX);
    const underivable = census.underivablePaths.map((u) => u.path);
    expect(underivable).toContain(`${DOCS_PREFIX}/page-redirects.njk`);
    // Unexempted -> flagged; exempted -> consumed.
    const flagged = classifyCensus(census, new Set(), new Set(), new Set());
    expect(flagged.underivableUnexempt.length).toBe(1);
    const exempted = classifyCensus(
      census,
      new Set(),
      new Set(),
      new Set([`${DOCS_PREFIX}/page-redirects.njk`]),
    );
    expect(exempted.underivableUnexempt).toEqual([]);
  });

  test("mutation: reslug-by-permalink-ADDITION strands the path-derived URL", () => {
    // The defect the -G enumeration was blind to pre-review: a path-derived
    // page gaining a permalink kills its old URL without any -permalink: line.
    const dir = synthRepo();
    writeDoc(dir, "pages/foo.md", "---\ntitle: foo\n---\nbody\n");
    commitAll(dir, "add page (path-derived URL /foo/)");
    writeDoc(
      dir,
      "pages/foo.md",
      "---\ntitle: foo\npermalink: bar/\n---\nbody\n",
    );
    commitAll(dir, "reslug via permalink addition");

    const result = classifyCensus(
      collectNeeds(dir, DOCS_PREFIX),
      new Set(),
      liveUrlPaths(dir, DOCS_PREFIX),
      new Set(),
    );
    const urls = result.uncovered.map((n) => n.url).sort();
    expect(urls).toEqual(["/pages/foo", "/pages/foo/", "/pages/foo/index.html"]);
    // The new permalink URL is live and must NOT be demanded.
    expect(urls.some((u) => u.includes("bar"))).toBe(false);
  });

  test("mutation: nested dated post serves /blog/<slug>/ — fileSlug strips dir+date", () => {
    const dir = synthRepo();
    writeDoc(dir, "blog/sub/2026-01-01-x.md", DATED_POST("x", "2026-01-01"));
    commitAll(dir, "add nested dated post");
    rmSync(join(dir, DOCS_PREFIX, "blog/sub/2026-01-01-x.md"));
    commitAll(dir, "delete nested post");

    const result = classifyCensus(
      collectNeeds(dir, DOCS_PREFIX),
      new Set(),
      liveUrlPaths(dir, DOCS_PREFIX),
      new Set(),
    );
    const urls = result.uncovered.map((n) => n.url).sort();
    // fileSlug semantics: /blog/x/ family + dated alias family. The WRONG
    // derivation (/blog/sub/x/) must not appear — it was never served.
    expect(urls).toEqual([
      "/blog/2026-01-01-x",
      "/blog/2026-01-01-x/",
      "/blog/2026-01-01-x/index.html",
      "/blog/x",
      "/blog/x/",
      "/blog/x/index.html",
    ]);
  });

  test("mutation: rename OUT of the docs tree re-serves nothing", () => {
    const dir = synthRepo();
    writeDoc(dir, "pages/foo.md", "---\ntitle: foo\n---\nbody\n");
    commitAll(dir, "add page");
    mkdirSync(join(dir, "other"), { recursive: true });
    sh(dir, "git", [
      "mv",
      `${DOCS_PREFIX}/pages/foo.md`,
      "other/foo.md",
    ]);
    commitAll(dir, "move page out of docs");

    const result = classifyCensus(
      collectNeeds(dir, DOCS_PREFIX),
      new Set(),
      liveUrlPaths(dir, DOCS_PREFIX),
      new Set(),
    );
    const urls = result.uncovered.map((n) => n.url).sort();
    // The new path is outside the docs prefix — it emits nothing, so the
    // whole /foo family is stranded.
    expect(urls).toEqual(["/pages/foo", "/pages/foo/", "/pages/foo/index.html"]);
  });

  test("mutation: adding permalink: false strands the path-derived URL", () => {
    const dir = synthRepo();
    writeDoc(dir, "pages/foo.md", "---\ntitle: foo\n---\nbody\n");
    commitAll(dir, "add page");
    writeDoc(
      dir,
      "pages/foo.md",
      "---\ntitle: foo\npermalink: false\n---\nbody\n",
    );
    commitAll(dir, "disable emission");

    const result = classifyCensus(
      collectNeeds(dir, DOCS_PREFIX),
      new Set(),
      liveUrlPaths(dir, DOCS_PREFIX),
      new Set(),
    );
    const urls = result.uncovered.map((n) => n.url).sort();
    expect(urls).toEqual(["/pages/foo", "/pages/foo/", "/pages/foo/index.html"]);
  });
});
