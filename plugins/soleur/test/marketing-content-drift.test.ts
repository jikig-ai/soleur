// Drift-guard suite for the 2026-04-19 SEO/AEO + content audit drain.
// Closes #2666, #2665, #2664, #2663, #2659, #2658, #2657 (Ref #2656).
//
// Test 1 prose sweep allowlist (DO NOT scan these directories):
//   - knowledge-base/marketing/audits/**              — frozen historical audit snapshots
//   - knowledge-base/marketing/distribution-content/**— dated social posts and drafts (numbers correct at post time)
//   - knowledge-base/marketing/copy/**                — page copy drafts with baked-in product stats
//   - knowledge-base/project/learnings/**             — frozen historical narratives
//   - knowledge-base/project/plans/**                 — plan documents may quote stale numbers as evidence
//   - knowledge-base/project/specs/**                 — spec/tasks documents likewise
// To extend: add the path prefix to PROSE_NUMERAL_ALLOWLIST below.

import { describe, test, expect, beforeAll } from "bun:test";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const TEST_DIR = import.meta.dir;
const REPO_ROOT = join(TEST_DIR, "..", "..", "..");
const KB_ROOT = join(REPO_ROOT, "knowledge-base");
const DOCS_ROOT = join(REPO_ROOT, "plugins", "soleur", "docs");
const SITE_ROOT = join(REPO_ROOT, "_site");

const PROSE_NUMERAL_ALLOWLIST = [
  join(KB_ROOT, "marketing", "audits"),
  join(KB_ROOT, "marketing", "distribution-content"),
  join(KB_ROOT, "marketing", "copy"),
  join(KB_ROOT, "project", "learnings"),
  join(KB_ROOT, "project", "plans"),
  join(KB_ROOT, "project", "specs"),
];

function isAllowlisted(filePath: string): boolean {
  return PROSE_NUMERAL_ALLOWLIST.some((prefix) => filePath.startsWith(prefix));
}

function walkMarkdown(dir: string, acc: string[] = []): string[] {
  if (!existsSync(dir)) return acc;
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const s = statSync(full);
    if (s.isDirectory()) walkMarkdown(full, acc);
    else if (entry.endsWith(".md")) acc.push(full);
  }
  return acc;
}

function walkSiteCopy(dir: string, acc: string[] = []): string[] {
  if (!existsSync(dir)) return acc;
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const s = statSync(full);
    if (s.isDirectory()) walkSiteCopy(full, acc);
    else if (entry.endsWith(".njk")) acc.push(full);
  }
  return acc;
}

let buildAttempted = false;
let buildOk = false;
let buildStderr = "";

// 30_000 ms: full Eleventy build measures 5-10s cold; default 5s bun hook
// timeout flakes. NOTE: bun reports this as `beforeEach/afterEach hook
// timed out` even for `beforeAll` — grep both when debugging.
beforeAll(async () => {
  // Build the Eleventy site once for tests 3-5. Argv array (no shell metacharacters).
  buildAttempted = true;
  // SOLEUR_DOCS_OFFLINE=1 makes the build hermetic — the _data/github.js,
  // githubStats.js, and communityStats.js loaders skip their live GitHub/Discord
  // fetches and return deterministic fallbacks, so a transient GitHub API
  // failure in CI cannot flake this full-site build. These drift-guards assert
  // on local prose/markup, not live release data.
  const proc = Bun.spawn(["npm", "run", "docs:build"], {
    cwd: REPO_ROOT,
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, SOLEUR_DOCS_OFFLINE: "1" },
  });
  const exitCode = await proc.exited;
  if (exitCode !== 0) {
    buildStderr = await new Response(proc.stderr).text();
    buildOk = false;
  } else {
    buildOk = true;
  }
}, 30_000);

describe("marketing-content-drift", () => {
  test("Test 1: prose uses soft floors, not stale exact counts", () => {
    // User-facing prose that must stay drift-free. Allowlist (constant above)
    // exempts dated/archival directories where exact counts were correct at
    // time of writing (audits, learnings, plans, specs, distribution-content,
    // copy drafts). To extend targets, add the root path here; to exempt a
    // new archival tree, extend PROSE_NUMERAL_ALLOWLIST.
    //
    // Root README.md is NOT swept here — scripts/sync-readme-counts.sh
    // auto-maintains its counts with exact integers and has a CI drift check.
    // Two guards with conflicting rules (soft-floor vs exact-int) on the same
    // file is wrong; the sync script owns that file.
    const targets = [
      ...walkMarkdown(join(KB_ROOT, "marketing")),
      ...walkMarkdown(join(KB_ROOT, "project", "components")),
      join(KB_ROOT, "project", "README.md"),
      ...walkMarkdown(join(DOCS_ROOT, "pages", "legal")),
    ].filter((p) => existsSync(p) && !isAllowlisted(p));

    // Window of "plausibly stale" exact counts around the current live total.
    // Soft-floor phrasing ("60+ agents", "60+ skills") is the load-bearing fix
    // per content-plan SF-10; bare exact counts in this window will drift.
    const stalePattern = /\b(59|61|62|63|65|66|67) (agents?|skills?)\b/;
    const offenders: { file: string; line: number; text: string }[] = [];
    for (const file of targets) {
      const lines = readFileSync(file, "utf8").split("\n");
      lines.forEach((text, i) => {
        if (stalePattern.test(text)) {
          offenders.push({ file: file.replace(REPO_ROOT + "/", ""), line: i + 1, text: text.trim() });
        }
      });
    }
    if (offenders.length > 0) {
      const detail = offenders
        .map((o) => `  ${o.file}:${o.line}\n    ${o.text.slice(0, 160)}${o.text.length > 160 ? "…" : ""}`)
        .join("\n");
      throw new Error(
        `Found ${offenders.length} stale exact count(s) in prose. Use soft floors ("60+ agents", "60+ skills") per content-plan SF-10, or extend PROSE_NUMERAL_ALLOWLIST for legitimate historical files:\n${detail}`,
      );
    }
  });

  test('Test 2: site copy contains no "Spark" tier references', () => {
    const targets = [
      ...walkSiteCopy(join(DOCS_ROOT, "_includes")),
      ...walkSiteCopy(join(DOCS_ROOT, "pages")),
      join(DOCS_ROOT, "index.njk"),
    ].filter((p) => existsSync(p));

    const offenders: { file: string; line: number; text: string }[] = [];
    for (const file of targets) {
      const lines = readFileSync(file, "utf8").split("\n");
      lines.forEach((text, i) => {
        if (/\bSpark\b/.test(text)) {
          offenders.push({ file: file.replace(REPO_ROOT + "/", ""), line: i + 1, text: text.trim() });
        }
      });
    }
    if (offenders.length > 0) {
      const detail = offenders
        .map((o) => `  ${o.file}:${o.line}\n    ${o.text.slice(0, 160)}${o.text.length > 160 ? "…" : ""}`)
        .join("\n");
      throw new Error(
        `Found ${offenders.length} "Spark" reference(s) in site copy (should be "Solo" — tier renamed in #2664):\n${detail}`,
      );
    }
  });

  // Present-tense BSL→Apache conversion language is legitimate ("converts to
  // Apache-2.0 four years after each release"); these tokens whitelist it.
  const LICENSE_CONVERSION = /converts|change date|Prior versions|remain under/i;

  test("Test 2b: site copy makes no Soleur-subject Apache / open-source license claim (#5038)", () => {
    // The current license is BSL 1.1 (source-available), NOT Apache-2.0; and
    // BSL is not OSI-approved, so a Soleur-subject "open source" claim is itself
    // a misrepresentation. Generic ecosystem "open source" (plugin marketplaces,
    // MCP "open standard") is NOT matched — only Soleur-subject phrasings.
    // pages/legal/** legitimately describes the BSL→Apache conversion → excluded.
    // Dated blog-body Soleur-subject "open source" positioning is resolved (#5043)
    // and enforced by Test 2c2 below; this .njk walk covers evergreen site copy only.
    const OFFENDER =
      /Apache[- ]2|LICENSE-2\.0|Apache-2\.0 licensed|open[- ]source (version|Company-as-a-Service|Claude Code platform|AI agents)|is open source|open source under|Apache-2\.0 open source/i;
    const targets = [
      ...walkSiteCopy(join(DOCS_ROOT, "_includes")),
      ...walkSiteCopy(join(DOCS_ROOT, "pages")),
      join(DOCS_ROOT, "index.njk"),
    ].filter((p) => existsSync(p) && !p.includes("/pages/legal/"));

    const offenders: { file: string; line: number; text: string }[] = [];
    for (const file of targets) {
      const lines = readFileSync(file, "utf8").split("\n");
      lines.forEach((text, i) => {
        if (OFFENDER.test(text) && !LICENSE_CONVERSION.test(text)) {
          offenders.push({ file: file.replace(REPO_ROOT + "/", ""), line: i + 1, text: text.trim() });
        }
      });
    }
    if (offenders.length > 0) {
      const detail = offenders
        .map((o) => `  ${o.file}:${o.line}\n    ${o.text.slice(0, 160)}${o.text.length > 160 ? "…" : ""}`)
        .join("\n");
      throw new Error(
        `Found ${offenders.length} Soleur-subject Apache/open-source license claim(s) — the site is source-available (BSL 1.1), not Apache/open-source (#5038):\n${detail}`,
      );
    }
  });

  test("Test 2c: blog posts make no explicit Apache-2.0 license claim (#5038)", () => {
    // Soleur-subject blog-body "open source" positioning is resolved (#5043) and
    // banned by Test 2c2 below; explicit Apache claims (#5038) name a license the
    // project no longer uses. Competitor/ecosystem "open source" (CrewAI MIT,
    // Paperclip MIT, Spec Kit "open-sourced by GitHub") is NOT matched.
    const OFFENDER = /Apache[- ]2|LICENSE-2\.0/i;
    const targets = walkMarkdown(join(DOCS_ROOT, "blog")).filter((p) => existsSync(p));
    const offenders: { file: string; line: number; text: string }[] = [];
    for (const file of targets) {
      const lines = readFileSync(file, "utf8").split("\n");
      lines.forEach((text, i) => {
        if (OFFENDER.test(text) && !LICENSE_CONVERSION.test(text)) {
          offenders.push({ file: file.replace(REPO_ROOT + "/", ""), line: i + 1, text: text.trim() });
        }
      });
    }
    if (offenders.length > 0) {
      const detail = offenders
        .map((o) => `  ${o.file}:${o.line}\n    ${o.text.slice(0, 160)}${o.text.length > 160 ? "…" : ""}`)
        .join("\n");
      throw new Error(
        `Found ${offenders.length} explicit Apache-2.0 license claim(s) in blog posts (#5038):\n${detail}`,
      );
    }
  });

  test("Test 2c2: blog posts make no Soleur-subject open-source claim (#5043)", () => {
    // Soleur is BSL 1.1 (source-available), NOT OSI-approved; a Soleur-subject
    // "open source" claim is a misrepresentation — resolved per CMO call (#5043).
    // Subject-anchored so competitor/ecosystem "open source" (CrewAI MIT,
    // Paperclip MIT, Spec Kit "open-sourced by GitHub", the bare `open-source`
    // frontmatter tag) stays verbatim and must NOT match — including a future
    // sentence-lead "Open source." about a competitor. Three frames:
    //   (1) "Soleur" within 40 same-line chars of open-source — covers
    //       "**Soleur** is an open-source", "Soleur is open-source",
    //       "Soleur's open-source model", "the Soleur open-source platform";
    //   (2) pronoun "it is (public, it is) open-source" (Soleur's own copy);
    //   (3) "open-source CaaS"/"open-source transparency".
    // Frames are phrasing-specific, not a general OSS detector; the sweep-time
    // AC1 grep is the completeness gate (e.g. bare table cells with no subject
    // token). Validated RED against reconstructed pre-sweep forms + GREEN on the
    // swept files, with zero competitor/ecosystem false-positives.
    const SOLEUR_OPEN_SOURCE =
      /Soleur\b[^.\n]{0,40}\bopen[- ]source|\bit\s+is\s+(?:public,\s+it\s+is\s+)?open[- ]source\b|open[- ]source\s+(?:CaaS|transparency)/i;
    const targets = walkMarkdown(join(DOCS_ROOT, "blog")).filter((p) => existsSync(p));
    const offenders: { file: string; line: number; text: string }[] = [];
    for (const file of targets) {
      const lines = readFileSync(file, "utf8").split("\n");
      lines.forEach((text, i) => {
        if (SOLEUR_OPEN_SOURCE.test(text)) {
          offenders.push({ file: file.replace(REPO_ROOT + "/", ""), line: i + 1, text: text.trim() });
        }
      });
    }
    if (offenders.length > 0) {
      const detail = offenders
        .map((o) => `  ${o.file}:${o.line}\n    ${o.text.slice(0, 160)}${o.text.length > 160 ? "…" : ""}`)
        .join("\n");
      throw new Error(
        `Found ${offenders.length} Soleur-subject "open source" claim(s) in blog posts — Soleur is source-available (BSL 1.1), not OSI-approved (#5043):\n${detail}`,
      );
    }
  });

  test("Test 3: homepage Organization JSON-LD has @id, founder, foundingDate", () => {
    if (!buildOk) throw new Error(`Eleventy build failed:\n${buildStderr}`);
    const html = readFileSync(join(SITE_ROOT, "index.html"), "utf8");
    const ldMatches = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)];
    expect(ldMatches.length).toBeGreaterThan(0);

    const orgs: any[] = [];
    for (const m of ldMatches) {
      let parsed: any;
      try {
        parsed = JSON.parse(m[1]);
      } catch {
        continue;
      }
      const graph = Array.isArray(parsed["@graph"]) ? parsed["@graph"] : [parsed];
      for (const node of graph) {
        if (node && node["@type"] === "Organization") orgs.push(node);
      }
    }
    expect(orgs.length).toBeGreaterThanOrEqual(1);
    // Select the canonical Organization node by @id rather than graph order —
    // robust if a second Organization node is ever added to the graph.
    const org =
      orgs.find((o) => String(o["@id"]).endsWith("#organization")) ?? orgs[0];
    // @id hosts derive from site.url, which is the bare apex canonical host
    // (https://soleur.ai) after the 2026-05-29 www→apex flip — www 301s to apex.
    expect(org["@id"]).toBe("https://soleur.ai/#organization");
    // founder is a cross-page @id reference (PR #2973); the canonical Person
    // node with name/sameAs/jobTitle lives on /about/.
    expect(org.founder?.["@id"]).toBe("https://soleur.ai/about/#jean-deruelle");
    expect(org.foundingDate).toMatch(/^\d{4}(-\d{2}(-\d{2})?)?$/);
  });

  test("Test 4: CaaS pillar reachable at /company-as-a-service/ + 301 from blog", () => {
    if (!buildOk) throw new Error(`Eleventy build failed:\n${buildStderr}`);
    const pillarPath = join(SITE_ROOT, "company-as-a-service", "index.html");
    expect(existsSync(pillarPath)).toBe(true);
    const pillarHtml = readFileSync(pillarPath, "utf8");
    expect(/<h1[^>]*>[\s\S]*Company-as-a-Service[\s\S]*<\/h1>/i.test(pillarHtml)).toBe(true);

    const redirectPath = join(SITE_ROOT, "blog", "what-is-company-as-a-service", "index.html");
    expect(existsSync(redirectPath)).toBe(true);
    const redirectHtml = readFileSync(redirectPath, "utf8");
    expect(/<meta\s+http-equiv=["']refresh["']\s+content=["']0;\s*url=\/company-as-a-service\/["']/i.test(redirectHtml)).toBe(true);

    // Canonical must point FORWARD to the new pillar, never back to the deleted blog URL
    // (Search Engine Journal 2026: Google ignores declared canonicals when they conflict
    // with the redirect target). Positive assertion catches template regressions that
    // either drop the tag or flip it backward; a bare negative-space check would be
    // tautological here (the template emits `{{ redirect.to }}`, so a back-canonical
    // cannot occur without an unrelated template edit).
    const forwardCanonical = /<link\s+rel=["']canonical["']\s+href=["']\/company-as-a-service\/?["']/i;
    expect(forwardCanonical.test(redirectHtml)).toBe(true);
  });

  test("Test 5: /pricing/ footnote has >=2 external citations + a YYYY-MM-DD date", () => {
    if (!buildOk) throw new Error(`Eleventy build failed:\n${buildStderr}`);
    const html = readFileSync(join(SITE_ROOT, "pricing", "index.html"), "utf8");
    const footnoteMatch = html.match(/<p\s+class=["']hiring-footnote["'][^>]*>([\s\S]*?)<\/p>/i);
    expect(footnoteMatch).not.toBeNull();
    const footnote = footnoteMatch![1];
    const links = footnote.match(/<a\s+[^>]*href=["']https:\/\//gi) || [];
    expect(links.length).toBeGreaterThanOrEqual(2);
    expect(/\b\d{4}-\d{2}-\d{2}\b/.test(footnote)).toBe(true);
  });
});
