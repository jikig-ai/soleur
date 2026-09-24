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
  EXCLUDED_BY_PATH,
  REPO_ROOT,
  census,
  readIndex,
  readPopulation,
  regionPolicyForPath,
  type CensusResult,
  type Index,
} from "../lib/harness-parity";
import {
  MIN_TRACKED_COMMANDS,
  MIN_TRACKED_REFERENCES,
  MIN_TRACKED_SKILLS,
} from "./lib/population-floors";

/** Literal pathspecs — deliberately NOT `INDEX_GLOBS`, so this invariant is independent of it. */
const OWN_SKILL_DIRS = ":(glob)plugins/soleur/skills/*/SKILL.md";
const OWN_COMMAND_FILES = ":(glob)plugins/soleur/commands/*.md";
/** Same, for the population half — NOT `POPULATION_GLOBS`, for the same reason. */
const OWN_CODEX_SKILLS = ":(glob)plugins/soleur/codex/skills/*/SKILL.md";
const OWN_DEVIN_SKILLS = ":(glob)plugins/soleur/devin/skills/*/SKILL.md";
/** The references half of NG-P (#8317), added 2026-09-23. */
const OWN_SKILL_REFERENCES = ":(glob)plugins/soleur/skills/*/references/**/*.md";
/** The agent-body half of NG-P (#8317). */
const OWN_AGENTS = ":(glob)plugins/soleur/agents/**/*.md";

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
    // A leaf spelled like another agent's Grok spawn key would earn a self-name while naming a
    // different agent on Grok (#8317 review).
    expect([...index.agentLeaves.keys()].filter((leaf) => index.grokStems.has(leaf))).toEqual([]);
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

  // The population half of the index invariant. Without this the ONLY floors are census()'s
  // `0 docs examined` throw and `docsExamined > 0` — so the population can be narrowed (a `*` to
  // `p*`, a dropped glob, a new EXCLUDED_BY_PATH entry) and the gate still reports a clean
  // `0 non-canonical` over whatever survived. The index half already carries
  // EXPECTED_SOLEUR_AGENT_COUNT; this is its counterpart, counted from THIS file's own literal
  // pathspecs rather than from POPULATION_GLOBS.
  test("the population is exactly the tracked doc set the globs name, minus the path exclusions", () => {
    // THE ADMISSION PROOF. This is the only assertion that proves `readPopulation()`
    // actually ENUMERATED the references docs; the policy assertions below exercise
    // `regionPolicyForPath` (the regex) and never `gitLsFiles` (the enumeration), and
    // two different engines interpret these pathspecs. Adding the glob to
    // POPULATION_GLOBS without adding it here reds exactly here, by design.
    const referenceDocs = lsFiles(OWN_SKILL_REFERENCES).filter((p) => !p.endsWith("/SKILL.md"));
    const expected =
      lsFiles(OWN_SKILL_DIRS).length +
      lsFiles(OWN_COMMAND_FILES).length +
      lsFiles(OWN_CODEX_SKILLS).length +
      lsFiles(OWN_DEVIN_SKILLS).length +
      referenceDocs.length +
      lsFiles(OWN_AGENTS).length -
      EXCLUDED_BY_PATH.size;
    expect(expected).toBeGreaterThan(100);
    // Per-source floors, not one union figure: a single total is dispatch-blind — it
    // cannot name WHICH glob went empty and it tolerates a large partial loss. Measured
    // 2026-09-23: skills 102, commands 3, codex 3, devin 3, references 115.
    expect(lsFiles(OWN_SKILL_DIRS).length).toBeGreaterThanOrEqual(MIN_TRACKED_SKILLS);
    expect(lsFiles(OWN_COMMAND_FILES).length).toBeGreaterThanOrEqual(MIN_TRACKED_COMMANDS);
    expect(referenceDocs.length).toBeGreaterThanOrEqual(MIN_TRACKED_REFERENCES);
    expect(
      lsFiles(OWN_AGENTS).length,
      "every .md under plugins/soleur/agents/ loads as a Claude subagent; agent-owned reference text belongs in the agent body",
    ).toBe(EXPECTED_SOLEUR_AGENT_COUNT);
    expect(docs.length).toBe(expected);
    // Every excluded path must be one the globs would otherwise have admitted — an exclusion
    // naming a path outside the population is dead weight that reads as a deliberate carve-out.
    const admitted = new Set([
      ...lsFiles(OWN_SKILL_DIRS),
      ...lsFiles(OWN_COMMAND_FILES),
      ...lsFiles(OWN_CODEX_SKILLS),
      ...lsFiles(OWN_DEVIN_SKILLS),
      ...referenceDocs,
      ...lsFiles(OWN_AGENTS),
    ]);
    expect([...EXCLUDED_BY_PATH.keys()].filter((p) => !admitted.has(p))).toEqual([]);
  });

  // The exempt surface is the compensation channel this design rejected a baseline to avoid, so
  // it is pinned by size, not merely by policy. Growing a region (or adding a new one) changes
  // this count and must be a reviewed diff rather than a silent widening.
  test("the exempt surface is bounded: one file, three regions, a fixed site count", () => {
    const exemptDocs = result.docs.filter((d) => d.counts.EXEMPT > 0).map((d) => d.path);
    expect(exemptDocs).toEqual(["plugins/soleur/commands/go.md"]);
    expect(result.totals.EXEMPT).toBe(21);
    const goMd = docs.find((d) => d.path === "plugins/soleur/commands/go.md");
    expect(goMd).toBeDefined();
    const starts = (goMd as { text: string }).text.match(/^<!-- harness-forms:start -->$/gm) ?? [];
    expect(starts.length).toBe(3);
    expect(EXCLUDED_BY_PATH.size).toBe(4);
  });

  test("the population is non-empty and carries no nested SKILL.md (N4, N12)", () => {
    expect(result.docsExamined).toBeGreaterThan(0);
    // `/references/` docs ARE members since 2026-09-23 (#8317, the references half).
    // What stays excluded is a SKILL.md NESTED under references/: the entry file is
    // `skills/*/SKILL.md`, and a reference doc that happens to carry that basename is
    // a sample, not a second entry point (N12).
    expect(docs.map((d) => d.path).filter((p) => /\/references\/.*\/?SKILL\.md$/.test(p))).toEqual([]);
    expect(docs.map((d) => d.path)).not.toContain("plugins/soleur/commands/help.md");
  });

  // The REGEX proof, distinct from the admission proof above. It enumerates the
  // references paths independently and resolves each through `regionPolicyForPath`,
  // never through `doc.regionPolicy`: `readPopulation`'s `?? g.regionPolicy` fallback
  // would restore the right answer in production and hide a `**` regression entirely.
  test("every references doc resolves to the skill policy through regionPolicyForPath", () => {
    const referenceDocs = lsFiles(OWN_SKILL_REFERENCES).filter((p) => !p.endsWith("/SKILL.md"));
    expect(referenceDocs.length).toBeGreaterThanOrEqual(MIN_TRACKED_REFERENCES);
    const wrong = referenceDocs.filter((p) => regionPolicyForPath(p) !== "skill");
    expect(
      wrong,
      `${wrong.length} references doc(s) resolve to no policy — globToRegex lost its ` +
        `\`**\` handling, or the references glob left POPULATION_GLOBS. The census would ` +
        `still report clean: readPopulation falls back to \`?? g.regionPolicy\`.`,
    ).toEqual([]);

    // Deepest paths exercise `**` specifically. Measured 2026-09-23: 25 `.md` files at
    // depth 7 or 8 (13 and 12). A `**` that degraded to `[^/]+` resolves these to
    // undefined while leaving the depth-6 ones green, so the assertion above alone
    // would not name the regression.
    const deep = referenceDocs.filter((p) => p.split("/").length >= 7);
    expect(deep.length).toBeGreaterThanOrEqual(20);
    expect(deep.filter((p) => regionPolicyForPath(p) !== "skill")).toEqual([]);

    // The companion: the carve-out for a nested SKILL.md is scoped to the REFERENCES
    // glob. Applied globally it would return undefined for every real skill entry file
    // — invisible in production behind the same `??` fallback, and only the fixtures
    // would red.
    expect(regionPolicyForPath("plugins/soleur/skills/plan/SKILL.md")).toBe("skill");
    expect(regionPolicyForPath("plugins/soleur/codex/skills/go/SKILL.md")).toBe("skill");
    expect(regionPolicyForPath("plugins/soleur/devin/skills/go/SKILL.md")).toBe("skill");
    expect(regionPolicyForPath("plugins/soleur/skills/plan/references/SKILL.md")).toBeUndefined();
  });

  // One assertion covers: a non-agent .md dropped under agents/ (0 self-names), an agent whose
  // `name:` was rewritten, quoted or removed (0), a carve-out that matched more than its one line
  // (> 1), and a policy regression (0 on every doc). The denominator is pinned so a filter typo
  // that matches nothing cannot pass vacuously.
  // The population glob sees `*.md` only, so every other tracked file shape under agents/ (a .txt
  // an agent is told to read, a symlink, an uppercase .MD) would be agent-read and unexamined.
  test("every tracked file under plugins/soleur/agents/ is a regular lowercase .md file", () => {
    const entries = execFileSync("git", ["ls-files", "-s", "--", "plugins/soleur/agents"], { cwd: REPO_ROOT, encoding: "utf-8" })
      .split("\n")
      .filter((l) => l.length > 0)
      // An EMPTY `.gitkeep` (the empty-blob hash) holds a domain directory open and carries no text.
      .filter((l) => !/^100644 e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 0\t.*\/\.gitkeep$/.test(l));
    expect(entries.length).toBe(EXPECTED_SOLEUR_AGENT_COUNT);
    expect(entries.filter((l) => !/^100644 [0-9a-f]+ 0\t.*\.md$/.test(l))).toEqual([]);
  });

  test("each agent doc carries exactly one self-name", () => {
    const agentDocs = result.docs.filter((d) => d.path.startsWith("plugins/soleur/agents/"));
    expect(agentDocs.length).toBe(EXPECTED_SOLEUR_AGENT_COUNT);
    const offenders = agentDocs
      .filter((d) => d.counts["SELF-NAME"] !== 1)
      .map(
        (d) =>
          `${d.path}: ${d.counts["SELF-NAME"]} self-name — frontmatter must open on line 1 with --- ` +
          `and its first name: line must read exactly "name: <filename stem>"`,
      );
    expect(offenders).toEqual([]);
  });

  // Unknown `soleur:` ids are reported, not gated, repo-wide (ADR-226). The agent population had
  // none when it joined the census, so a typo such as `soleur:engineering:security-sentinel`
  // (missing `review:`) is held to zero here rather than joining that backlog.
  test("no agent doc names an unknown soleur: id", () => {
    const unknown = result.unknownNs
      .filter((s) => s.path.startsWith("plugins/soleur/agents/"))
      .map((s) => `${s.path}:${s.line}: ${s.raw}`);
    expect(unknown).toEqual([]);
  });

  test("no doc carries a malformed or unbalanced harness-forms marker", () => {
    expect(result.errors).toEqual([]);
  });

  // One test per doc so a RED names the doc in the runner's own summary. `gated` records which
  // docs the loop actually reached, so the sibling test below can compare that against the
  // census — a per-doc loop truncated to `.slice(0, 1)` otherwise drops 100+ assertions while
  // every surviving test still passes and the runner still exits 0.
  const gated: string[] = [];
  for (const doc of result.docs) {
    test(`${doc.path} names every known component canonically`, () => {
      gated.push(doc.path);
      const noncanonical = doc.sites.filter((s) => s.verdict === "NONCANONICAL").map((s) => s.message);
      expect(noncanonical).toEqual([]);
    });
  }

  // Dispatch: every doc the census examined must have been reached by a per-doc test above.
  // Bun runs the `for` body's tests before this one because they are registered first.
  test("every examined doc was dispatched to a per-doc assertion", () => {
    expect(gated.slice().sort()).toEqual(result.docs.map((d) => d.path).sort());
  });

  // The same property asserted WITHOUT going through the per-doc filter, so an edit that
  // neuters that filter (binding `noncanonical` to a constant, excluding an attribution) is
  // caught here rather than being byte-identical green.
  test("the whole census carries no non-canonical site", () => {
    expect(result.noncanonical.map((s) => s.message)).toEqual([]);
  });

  test("summary (docsExamined is derived from docs — see the population pin above for coverage)", () => {
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
