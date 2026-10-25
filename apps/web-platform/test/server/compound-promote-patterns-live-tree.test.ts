// #8293 -- the validator over the REAL `knowledge-base/project/patterns/` tree (CI is not the only
// gate: loadOpenPatterns repeats the cheap checks at runtime, but this is where a bad seed or a
// learning archived by an unrelated PR turns red BEFORE merge, which is intended -- the page must
// be updated in the same PR).
//
// This suite reads the repository outside the app, so it is registered in `REPO_WIDE_SUITES`
// (`repo-wide-containment.test.ts` fails otherwise).
import { afterAll, describe, expect, it, vi } from "vitest";
import { execFileSync } from "node:child_process";
import { closeSync, constants as fsConstants, mkdirSync, mkdtempSync, openSync, readFileSync, readdirSync, existsSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { gitCleanEnv } from "../../../../plugins/soleur/test/lib/git-clean-env";

vi.hoisted(() => {
  // The handler module builds the Inngest client at import; this is the same guard the sibling handler suites use.
  process.env.NEXT_PHASE = "phase-production-build";
});

import { PII_REGEX as piiRegex } from "@/server/inngest/functions/cron-compound-promote";
import {
  MIN_PAGE_EVIDENCE,
  PATTERNS_DIR,
  isCanonicalEvidencePath,
  loadOpenPatterns,
  parsePatternPage,
  type PatternPage,
} from "@/server/compound-promote-patterns";

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../../..");
const SEED_CAP = 8;

// Shapes that must never appear in a page: a handle, a UUID, an internal host, a tenant/project ref.
const DENYLIST: Array<[string, RegExp]> = [
  ["@handle", /(^|[^A-Za-z0-9_])@[A-Za-z0-9][A-Za-z0-9_-]+/],
  ["uuid", /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i],
  ["internal-host", /\b[a-z0-9.-]+\.(internal|local)\b/i],
  ["project-ref", /\b[a-z]{20}\.supabase\.co\b/i],
];

function denylistHits(text: string): string[] {
  return DENYLIST.filter(([, re]) => re.test(text)).map(([name]) => name);
}

function trackedLearnings(): Set<string> {
  const out = execFileSync("git", ["-C", REPO_ROOT, "ls-files", "-z", "knowledge-base/project/learnings"], {
    env: gitCleanEnv() as NodeJS.ProcessEnv,
    encoding: "utf-8",
    maxBuffer: 64 * 1024 * 1024,
  });
  return new Set(out.split("\0").filter(Boolean));
}

/** Retired learning paths, read the way the runtime does (a path that appears in the retired-rule list). */
function retiredText(): string {
  const f = join(REPO_ROOT, "scripts/retired-rule-ids.txt");
  return existsSync(f) ? readFileSync(f, "utf-8") : "";
}

/**
 * The runtime drops an evidence learning that is retired, a symlink, or matches the PII regex in the
 * excerpt that is sent. A page citing one is CI-green but silently changes its cluster hash, so CI
 * mirrors those classes. `root` is injectable so the self-check can use a synthesized tree.
 */
function attritionProblems(p: string, root: string, retired: string): string[] {
  const out: string[] = [];
  if (retired.includes(p)) out.push(`evidence-retired:${p}`);
  const abs = join(root, p);
  // One open with O_NOFOLLOW instead of lstat-then-read: a symlink is refused by the kernel (ELOOP) and the
  // read goes through the same descriptor, so there is no window between the check and the use.
  let fd: number | null = null;
  try {
    fd = openSync(abs, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW);
    const excerpt = readFileSync(fd, "utf-8").split("\n").slice(0, 10).join("\n");
    if (piiRegex.test(excerpt)) out.push(`evidence-pii:${p}`);
  } catch (e) {
    out.push((e as NodeJS.ErrnoException).code === "ELOOP" ? `evidence-symlink:${p}` : `evidence-unreadable:${p}`);
  } finally {
    if (fd !== null) closeSync(fd);
  }
  return out;
}

function ciProblems(page: PatternPage, text: string, tracked: ReadonlySet<string>, root: string = REPO_ROOT, retired: string = retiredText()): string[] {
  const problems: string[] = [];
  for (const hit of denylistHits(text)) problems.push(`denylist:${hit}`);
  // A handle that only exists once YAML has decoded it (an escape sequence) is invisible to the raw-text scan.
  for (const hit of denylistHits([page.title, page.summary, ...page.tags].join("\n"))) problems.push(`denylist-decoded:${hit}`);
  for (const p of page.evidence) {
    if (!isCanonicalEvidencePath(p)) problems.push(`evidence-shape:${p}`);
    else if (p.includes("/archive/")) problems.push(`evidence-archived:${p}`);
    else if (!tracked.has(p)) problems.push(`evidence-untracked:${p}`);
    else problems.push(...attritionProblems(p, root, retired));
  }
  if (page.evidence.length < MIN_PAGE_EVIDENCE) problems.push("evidence-count");
  if (page.status === "open" && (page.closedOn !== undefined || page.closedBy !== undefined)) problems.push("open-with-closed-fields");
  if (page.status === "closed" && (page.closedOn === undefined || page.closedBy === undefined)) problems.push("closed-without-closed-fields");
  return problems;
}

describe("the validator can fail (instrument self-check)", () => {
  const good = (extra = "") =>
    `---\ntitle: "A pattern"\nsummary: "One line."\nstatus: open\nopened_on: "2026-10-24"\ntags: [guards]\nevidence:\n${Array.from({ length: 5 }, (_, i) => `  - knowledge-base/project/learnings/e${i}.md`).join("\n")}\nrequired_reading: false\n---\n## Root cause\n${extra}\n`;
  const tracked = new Set(Array.from({ length: 5 }, (_, i) => `knowledge-base/project/learnings/e${i}.md`));

  const synth = mkdtempSync(join(tmpdir(), "patterns-live-"));
  mkdirSync(join(synth, "knowledge-base/project/learnings"), { recursive: true });
  for (let i = 0; i < 5; i++) writeFileSync(join(synth, `knowledge-base/project/learnings/e${i}.md`), `# e${i}\n`);
  afterAll(() => rmSync(synth, { recursive: true, force: true }));

  it("passes a clean synthesized page", () => {
    const r = parsePatternPage(good(), `${PATTERNS_DIR}/a.md`, piiRegex);
    expect(r.ok).toBe(true);
    if (r.ok) expect(ciProblems(r.page, good(), tracked, synth, "")).toEqual([]);
  });

  it("flags a handle that only exists after YAML decoding", () => {
    const text = good().replace('title: "A pattern"', 'title: "Fix \\x40alice loop"');
    expect(denylistHits(text)).toEqual([]);
    const r = parsePatternPage(text, `${PATTERNS_DIR}/a.md`, piiRegex);
    expect(r.ok).toBe(true);
    if (r.ok) expect(ciProblems(r.page, text, tracked, synth, "")).toContain("denylist-decoded:@handle");
  });

  it("flags the runtime attrition classes: a retired, a symlinked and a PII-bearing evidence learning", () => {
    const r = parsePatternPage(good(), `${PATTERNS_DIR}/a.md`, piiRegex);
    if (!r.ok) throw new Error("fixture invalid");
    const lr = join(synth, "knowledge-base/project/learnings");
    writeFileSync(join(lr, "e1.md"), "# e1\ncontact someone@example.test\n");
    rmSync(join(lr, "e2.md"));
    symlinkSync(join(lr, "e3.md"), join(lr, "e2.md"));
    const problems = ciProblems(r.page, good(), tracked, synth, "retired | knowledge-base/project/learnings/e0.md\n");
    expect(problems).toEqual(
      expect.arrayContaining([
        "evidence-retired:knowledge-base/project/learnings/e0.md",
        "evidence-pii:knowledge-base/project/learnings/e1.md",
        "evidence-symlink:knowledge-base/project/learnings/e2.md",
      ]),
    );
  });

  it.each([
    ["handle", "ping @some-person about it", "denylist:@handle"],
    ["uuid", "id 123e4567-e89b-42d3-a456-426614174000", "denylist:uuid"],
    ["internal host", "see db.corp.internal", "denylist:internal-host"],
    ["project ref", "abcdefghijklmnopqrst.supabase.co", "denylist:project-ref"],
  ])("flags a body containing a %s", (_n, body, problem) => {
    const text = good(body);
    const r = parsePatternPage(text, `${PATTERNS_DIR}/a.md`, piiRegex);
    expect(r.ok).toBe(true);
    if (r.ok) expect(ciProblems(r.page, text, tracked)).toContain(problem);
  });

  it("flags an untracked and an archived evidence path", () => {
    const r = parsePatternPage(good(), `${PATTERNS_DIR}/a.md`, piiRegex);
    if (!r.ok) throw new Error("fixture invalid");
    expect(ciProblems(r.page, good(), new Set())).toContain("evidence-untracked:knowledge-base/project/learnings/e0.md");
    const archived = { ...r.page, evidence: [...r.page.evidence.slice(1), "knowledge-base/project/learnings/archive/x.md"] };
    expect(ciProblems(archived, good(), tracked)).toContain("evidence-archived:knowledge-base/project/learnings/archive/x.md");
  });

  it("the handler's PII regex still matches an email", () => {
    expect(piiRegex.test("someone@example.test")).toBe(true);
  });
});

describe("the real pattern tree", () => {
  const dir = join(REPO_ROOT, PATTERNS_DIR);
  const names = existsSync(dir) ? readdirSync(dir).filter((n) => n.endsWith(".md")).sort() : [];
  const tracked = trackedLearnings();

  // The seeded pages, by name: an emptied or renamed tree must not read as a pass (`it.each([])` registers nothing).
  const SEEDED = ["early-exit-reader-under-pipefail", "failure-signal-never-reaches-a-human", "fixture-cannot-distinguish-the-cases-it-claims", "guard-pins-artifact-not-wiring", "instrument-answers-instead-of-failing", "mutation-score-is-not-predicate-correctness", "verification-scaffolding-carries-the-defect"];

  it("holds the seeded pages (a missing directory or a vanished page fails here, not silently)", () => {
    for (const slug of SEEDED) expect(names, `missing seed page ${slug}`).toContain(`${slug}.md`);
  });

  it("is within the seed cap and every file is markdown", () => {
    expect(names.length).toBeLessThanOrEqual(SEED_CAP);
    const all = existsSync(dir) ? readdirSync(dir) : [];
    expect(all.filter((n) => !n.endsWith(".md"))).toEqual([]);
  });

  it("the runtime loader drops nothing from the real tree (alias, size and attrition classes included)", async () => {
    const r = await loadOpenPatterns({ repoRoot: REPO_ROOT, piiRegex, retiredPaths: new Set<string>() });
    expect(r.dirReadable).toBe(true);
    expect(r.dropped).toEqual([]);
    expect(r.droppedEvidence).toEqual([]);
    expect(r.open).toBeGreaterThanOrEqual(1);
  });

  it("the learnings subtree was enumerated (a vacuous tracked set would pass every page)", () => {
    expect(tracked.size).toBeGreaterThan(100);
  });

  it.each(names)("%s passes the schema, the PII scan, the denylist and the evidence checks", (name) => {
    const rel = `${PATTERNS_DIR}/${name}`;
    const text = readFileSync(join(REPO_ROOT, rel), "utf-8");
    const r = parsePatternPage(text, rel, piiRegex);
    expect(r, `${rel} failed to parse`).toMatchObject({ ok: true });
    if (!r.ok) return;
    expect(r.page.slug).toBe(name.replace(/\.md$/, ""));
    expect(ciProblems(r.page, text, tracked)).toEqual([]);
  });
});
