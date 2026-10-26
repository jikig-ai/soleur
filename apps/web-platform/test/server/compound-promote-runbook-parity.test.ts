// WikiSkill Phase 2 (#10550), review round -- the runbook names every closed `create_detail` token the code can emit.
// Own file: it reads the runbook, which lives outside apps/web-platform (so it is a REPO_WIDE suite, see
// test/repo-wide-suites.ts). Window: the three create modules, each read whole; the runbook, read whole.
import { describe, expect, it, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const SERVER_DIR = join(__dirname, "..", "..", "server");
const CREATE_MODULE = join(SERVER_DIR, "compound-promote-create.ts");
const CREATE_ARM = join(SERVER_DIR, "compound-promote-create-arm.ts");
const CREATE_GATES = join(SERVER_DIR, "compound-promote-create-gates.ts");

// ---------------------------------------------------------------------------
// #10550 review -- the runbook names every closed `create_detail` token the code can emit (an operator reading a marker
// row must find its token). Window: the three create modules, each parsed whole; the runbook, read whole.
// ---------------------------------------------------------------------------
describe("every closed refusal detail token in the create modules is in the runbook", () => {
  beforeEach(() => {
    expect.hasAssertions();
  });
  const RUNBOOK = join(__dirname, "..", "..", "..", "..", "knowledge-base", "engineering", "operations", "runbooks", "compound-promote-runbook.md");
  const code = (f: string) => readFileSync(f, "utf-8").split("\n").map((l) => l.replace(/^\s*\/\/.*$/, "").replace(/^\s*\*.*$/, "")).join("\n");

  /** Detail literals: second argument of `fail(`/`refusal(`/`refuse(`, first argument of the gates' own constructors. */
  function detailTokens(src: string): string[] {
    const out: string[] = [];
    for (const m of src.matchAll(/\b(?:fail|refusal|refuse)\(\s*"[a-z-]+",\s*"([^"$]+)"/g)) out.push(m[1]);
    for (const m of src.matchAll(/\b(?:scanRefusal|readmeRefusal|collectRefusal)\(\s*"([^"$]+)"/g)) out.push(m[1]);
    for (const m of src.matchAll(/\bdetail:\s*"([a-z][a-z0-9-]*)"/g)) out.push(m[1]);
    return out;
  }

  it("every detail literal appears, backticked, in the runbook (and the census found a meaningful number of them)", () => {
    const runbook = readFileSync(RUNBOOK, "utf-8");
    const tokens = [...new Set([CREATE_MODULE, CREATE_ARM, CREATE_GATES].flatMap((f) => detailTokens(code(f))))];
    expect(tokens.length).toBeGreaterThan(60); // non-vacuity: a census that found a handful would read clean
    const missing = tokens.filter((t) => !runbook.includes(`\`${t}\``) && !new RegExp(`\`[^\`]*\\b${t}\\b[^\`]*\``).test(runbook));
    expect(missing).toEqual([]);
  });

  it("mutation: a detail token the runbook does not name is RED", () => {
    const runbook = readFileSync(RUNBOOK, "utf-8");
    const arm = code(CREATE_ARM).replace('fail("persist", "deadline")', 'fail("persist", "a-token-no-runbook-names")');
    expect(arm).not.toBe(code(CREATE_ARM));
    const tokens = detailTokens(arm);
    expect(tokens).toContain("a-token-no-runbook-names");
    expect(runbook.includes("`a-token-no-runbook-names`")).toBe(false);
  });
});
