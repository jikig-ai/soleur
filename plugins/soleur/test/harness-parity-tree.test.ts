/**
 * Tree census — every component reference in plugin prose is canonical (ADR-226, #8299).
 *
 * The gate. Born blocking, no baseline: the property is absolute (`NONCANONICAL == []` for every
 * doc in the population), so there is no number to pin. What can go quietly blind is the
 * INSTRUMENT, and this file carries the two checks that do not live in the fixture suite:
 *
 *   - the index invariant, computed from THIS file's own literal pathspecs (never imported from
 *     `INDEX_GLOBS`, so an emptied index constant is caught here rather than certified);
 *   - the census over `readPopulation()`, which throws on `0 docs examined`.
 *
 * The fixture suite (harness-parity.test.ts) asserts this file contains the literal
 * `expect(noncanonical).toEqual([])` — a cross-file sentinel, so deleting the assertion below
 * reds a different file than the one edited.
 *
 * Failure output is the per-site message: `path:line: <site> — <harness form>; write <id>`.
 * `bun plugins/soleur/scripts/harness-parity-census.ts --fix` repairs the mechanical shapes.
 */

import { describe, test, expect } from "bun:test";
import { execFileSync } from "child_process";
import { EXPECTED_SOLEUR_AGENT_COUNT } from "../lib/agent-registry";
import {
  REPO_ROOT,
  census,
  readIndex,
  readPopulation,
  type CensusResult,
  type Index,
} from "../lib/harness-parity";

/** Literal pathspecs — deliberately NOT `INDEX_GLOBS`, so this invariant is independent of it. */
const OWN_SKILL_DIRS = ":(glob)plugins/soleur/skills/*/SKILL.md";
const OWN_COMMAND_FILES = ":(glob)plugins/soleur/commands/*.md";

function lsFiles(pathspec: string): string[] {
  return execFileSync("git", ["ls-files", "--full-name", "--", pathspec], { cwd: REPO_ROOT, encoding: "utf-8" })
    .split("\n")
    .filter((l) => l.length > 0);
}

const index: Index = readIndex();

describe("harness-parity index invariant (N10)", () => {
  test("every skill directory resolves to a canonical id", () => {
    const dirs = lsFiles(OWN_SKILL_DIRS).map((p) => p.split("/").at(-2) as string);
    expect(dirs.length).toBeGreaterThan(0);
    const missing = dirs.filter((d) => !index.canonicalIds.has(`soleur:${d}`));
    expect(missing).toEqual([]);
  });

  test("every command file resolves to a canonical id", () => {
    const names = lsFiles(OWN_COMMAND_FILES).map((p) => (p.split("/").at(-1) as string).replace(/\.md$/, ""));
    expect(names.length).toBeGreaterThan(0);
    const missing = names.filter((n) => !index.canonicalIds.has(`soleur:${n}`));
    expect(missing).toEqual([]);
  });

  test("the agent index is the registry (67), with unique leaves disjoint from skill names", () => {
    expect(index.agentIds.length).toBe(EXPECTED_SOLEUR_AGENT_COUNT);
    expect(index.agentLeaves.size).toBe(index.agentIds.length);
    expect(index.grokStems.size).toBe(index.agentIds.length);
    const collisions = [...index.agentLeaves.keys()].filter((leaf) => index.skillNames.has(leaf));
    expect(collisions).toEqual([]);
  });

  test("|CANONICAL_IDS| equals the independently counted distinct total", () => {
    const skillDirs = new Set(lsFiles(OWN_SKILL_DIRS).map((p) => p.split("/").at(-2) as string));
    const commands = new Set(lsFiles(OWN_COMMAND_FILES).map((p) => (p.split("/").at(-1) as string).replace(/\.md$/, "")));
    const distinct = new Set([...skillDirs, ...commands]).size + EXPECTED_SOLEUR_AGENT_COUNT;
    expect(index.canonicalIds.size).toBe(distinct);
  });
});

describe("harness-parity tree census (Guard 3)", () => {
  const docs = readPopulation();
  const result: CensusResult = census(docs, index);

  test("the population is non-empty and carries no nested SKILL.md (N4, N12)", () => {
    expect(result.docsExamined).toBeGreaterThan(0);
    expect(docs.map((d) => d.path).filter((p) => p.includes("/references/"))).toEqual([]);
    expect(docs.map((d) => d.path)).not.toContain("plugins/soleur/commands/help.md");
  });

  test("no doc carries a malformed or unbalanced harness-forms marker", () => {
    expect(result.errors).toEqual([]);
  });

  // One test per doc so a RED names the doc in the runner's own summary.
  for (const doc of result.docs) {
    test(`${doc.path} names every known component canonically`, () => {
      const noncanonical = doc.sites.filter((s) => s.verdict === "NONCANONICAL").map((s) => s.message);
      expect(noncanonical).toEqual([]);
    });
  }

  test("summary", () => {
    console.log(
      `harness-parity: ${result.docsExamined} docs examined, ${result.noncanonical.length} non-canonical, ` +
        `${result.totals.CANONICAL} canonical, ${result.unknownNs.length} unknown-ns` +
        (result.unknownNs.length > 0
          ? "\n  unknown-ns (reported, not gated):\n" + result.unknownNs.map((s) => `    ${s.path}:${s.line}: ${s.raw}`).join("\n")
          : ""),
    );
    expect(result.docsExamined).toBe(result.docs.length);
  });
});
