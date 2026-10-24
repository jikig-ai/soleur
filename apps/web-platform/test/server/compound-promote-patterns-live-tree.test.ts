// #8293 -- the validator over the REAL `knowledge-base/project/patterns/` tree (CI is not the only
// gate: loadOpenPatterns repeats the cheap checks at runtime, but this is where a bad seed or a
// learning archived by an unrelated PR turns red BEFORE merge, which is intended -- the page must
// be updated in the same PR).
//
// This suite reads the repository outside the app, so it is registered in `REPO_WIDE_SUITES`
// (`repo-wide-containment.test.ts` fails otherwise).
import { describe, expect, it, vi } from "vitest";
import { execFileSync } from "node:child_process";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { gitCleanEnv } from "../../../../plugins/soleur/test/lib/git-clean-env";

vi.hoisted(() => {
  // The handler module builds the Inngest client at import; this is the same guard the sibling handler suites use.
  process.env.NEXT_PHASE = "phase-production-build";
});

import { PII_REGEX as piiRegex } from "@/server/inngest/functions/cron-compound-promote";
import {
  EVIDENCE_PATH_RE,
  MIN_PAGE_EVIDENCE,
  PATTERNS_DIR,
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

function ciProblems(page: PatternPage, text: string, tracked: ReadonlySet<string>): string[] {
  const problems: string[] = [];
  for (const hit of denylistHits(text)) problems.push(`denylist:${hit}`);
  for (const p of page.evidence) {
    if (!EVIDENCE_PATH_RE.test(p) || p.includes("..")) problems.push(`evidence-shape:${p}`);
    else if (p.includes("/archive/")) problems.push(`evidence-archived:${p}`);
    else if (!tracked.has(p)) problems.push(`evidence-untracked:${p}`);
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

  it("passes a clean synthesized page", () => {
    const r = parsePatternPage(good(), `${PATTERNS_DIR}/a.md`, piiRegex);
    expect(r.ok).toBe(true);
    if (r.ok) expect(ciProblems(r.page, good(), tracked)).toEqual([]);
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

  it("is within the seed cap and every file is markdown", () => {
    expect(names.length).toBeLessThanOrEqual(SEED_CAP);
    const all = existsSync(dir) ? readdirSync(dir) : [];
    expect(all.filter((n) => !n.endsWith(".md"))).toEqual([]);
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
