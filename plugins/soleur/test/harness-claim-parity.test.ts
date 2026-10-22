/**
 * Harness-claim parity gate for the public marketing surfaces.
 *
 * Why this exists: adding OpenCode as a supported harness (#10815) was a "mechanical, all-or-nothing
 * enumeration sweep" by CLO instruction, and the sweep missed six surfaces across two passes —
 * `plugins/soleur/README.md`, `page-freshness.njk`'s page summaries, `about.njk`, `community.njk`,
 * `vision.njk`, and the two comparison pages. Every miss was the same shape: a page still said the
 * harness set was four, or said Soleur is "built on Claude Code". Nothing failed, because no gate
 * looked at prose enumerations. This is that gate, so the next harness flip is a test failure
 * instead of a repo-wide hunt.
 *
 * Scope and its exclusions, deliberately:
 * - `docs/pages/legal/**` is EXCLUDED. The canonical harness parenthetical is a CLO-owned,
 *   attested, non-exhaustive `including …` list with a T&C version and SHA-pin ritual around it;
 *   it is edited only by a CLO-signed PR, never by a docs sweep.
 * - `docs/blog/**` is EXCLUDED. Published posts are a dated record; rewriting them is historical
 *   revision, not a claim fix.
 * - Archive/plan/learning records under `knowledge-base/` are EXCLUDED for the same reason: they
 *   describe the world as it was at the time and are cited by anchor.
 *
 * The rules are phrased to fire on the DEFECT, not on every mention:
 * - Rule 1 catches a four-member enumeration that omits the fifth.
 * - Rule 2 catches the single-harness identity claim, but not the fixed form where "Claude Code"
 *   opens a longer list ("… inside Claude Code, Grok Build, …").
 * - Rule 3 catches the stale cardinality that shipped in the plugin README ("the other three").
 */
import { describe, expect, test } from "bun:test";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative, resolve } from "node:path";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const DOCS = join(REPO_ROOT, "plugins/soleur/docs");

/** Public surfaces that state what Soleur runs on. */
function publicSurfaces(): string[] {
  const files = [
    join(REPO_ROOT, "README.md"),
    join(REPO_ROOT, "plugins/soleur/README.md"),
    join(REPO_ROOT, "CONTRIBUTING.md"),
  ];
  const walk = (dir: string): void => {
    for (const entry of readdirSync(dir)) {
      const abs = join(dir, entry);
      if (statSync(abs).isDirectory()) {
        // legal is CLO-owned (non-exhaustive `including` lists with a version/SHA ritual); blog is
        // a dated record. Neither is swept by a claim flip.
        if (entry === "legal" || entry === "blog" || entry === "_site" || entry === "node_modules") continue;
        walk(abs);
        continue;
      }
      if (/\.(njk|md)$/.test(entry)) files.push(abs);
    }
  };
  walk(DOCS);
  return files;
}

/** One line, tagged with its file and 1-based line number, for a readable failure message. */
interface Hit {
  where: string;
  line: string;
}

function scan(predicate: (line: string) => boolean): Hit[] {
  const hits: Hit[] = [];
  for (const file of publicSurfaces()) {
    const lines = readFileSync(file, "utf8").split("\n");
    lines.forEach((line, i) => {
      if (predicate(line)) hits.push({ where: `${relative(REPO_ROOT, file)}:${i + 1}`, line: line.trim().slice(0, 200) });
    });
  }
  return hits;
}

/** A line that names all four pre-OpenCode harnesses and does not name OpenCode. */
const FOUR_MEMBER_WITHOUT_FIFTH = (line: string): boolean =>
  /Claude Code/.test(line) &&
  /Grok Build/.test(line) &&
  /Codex/.test(line) &&
  /Devin/.test(line) &&
  !/OpenCode/.test(line);

/** A single-harness identity claim that is NOT the head of a longer harness list. */
const SINGLE_HARNESS_IDENTITY = (line: string): boolean =>
  [
    /(?:built on|runs (?:on|inside)|ships as|is) Claude Code(?!\s*[,\u2014-]\s*Grok)/,
  ].some((re) => re.test(line));

/** Stale cardinality: the harness set is named by count. */
const STALE_CARDINALITY = (line: string): boolean => /the other three harness/i.test(line);

describe("public harness-claim parity (the sweep a harness flip must not miss)", () => {
  test("the scan is not vacuous", () => {
    const files = publicSurfaces();
    expect(files.length, "public surfaces discovered").toBeGreaterThan(30);
    const readme = readFileSync(join(REPO_ROOT, "README.md"), "utf8");
    expect(readme, "README names the fifth harness").toContain("OpenCode");
    const pluginReadme = readFileSync(join(REPO_ROOT, "plugins/soleur/README.md"), "utf8");
    expect(pluginReadme, "the shipped plugin README names the fifth harness").toContain("OpenCode");
  });

  test("no public surface enumerates the harness set without OpenCode", () => {
    expect(scan(FOUR_MEMBER_WITHOUT_FIFTH)).toEqual([]);
  });

  test("no public surface still claims Claude Code as the only harness", () => {
    expect(scan(SINGLE_HARNESS_IDENTITY)).toEqual([]);
  });

  test("no public surface names the harness set by a stale count", () => {
    expect(scan(STALE_CARDINALITY)).toEqual([]);
  });
});
