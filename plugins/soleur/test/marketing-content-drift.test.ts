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

beforeAll(async () => {
  // Build the Eleventy site once for tests 3-5. Argv array (no shell metacharacters).
  buildAttempted = true;
  const proc = Bun.spawn(["npm", "run", "docs:build"], {
    cwd: REPO_ROOT,
    stdout: "pipe",
    stderr: "pipe",
  });
  const exitCode = await proc.exited;
  if (exitCode !== 0) {
    buildStderr = await new Response(proc.stderr).text();
    buildOk = false;
  } else {
    buildOk = true;
  }
});

describe("marketing-content-drift", () => {
  test("Test 1: knowledge-base prose uses soft floors, not stale exact counts", () => {
    const targets = [
      ...walkMarkdown(join(KB_ROOT, "marketing")),
      ...walkMarkdown(join(KB_ROOT, "project", "components")),
      join(KB_ROOT, "project", "README.md"),
    ].filter((p) => existsSync(p) && !isAllowlisted(p));

    const stalePattern = /\b(63|62|61|59|65|66|67) (agents?|skills?)\b/;
    const offenders: { file: string; line: number; text: string }[] = [];
    for (const file of targets) {
      const lines = readFileSync(file, "utf8").split("\n");
      lines.forEach((text, i) => {
        if (stalePattern.test(text)) {
          offenders.push({ file: file.replace(REPO_ROOT + "/", ""), line: i + 1, text: text.trim() });
        }
      });
    }
    expect(offenders).toEqual([]);
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
    expect(offenders).toEqual([]);
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
    const org = orgs[0];
    expect(org["@id"]).toBe("https://soleur.ai/#organization");
    expect(org.founder?.name).toBe("Jean Deruelle");
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

    // Never combine 301 with a back-pointing canonical (Search Engine Journal 2026).
    const backCanonical = /<link\s+rel=["']canonical["']\s+href=["'][^"']*\/blog\/what-is-company-as-a-service\/?["']/i;
    expect(backCanonical.test(redirectHtml)).toBe(false);
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
