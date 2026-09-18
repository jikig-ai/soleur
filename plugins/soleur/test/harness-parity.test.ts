/**
 * Fixture self-test for the harness-parity classifier (ADR-226, #8299).
 *
 * Every fixture under test/fixtures/harness-parity/{skills,commands}/ is SYNTHESIZED (never
 * copied from a live doc) and pins one rule, one allowlist member, or one region-grammar
 * clause of `classifyDoc`. The subdirectory selects `regionPolicy` through the same
 * path→policy function the tree census uses, so the mapping has a permanent fixture.
 *
 * These are the permanent anti-vacuity rows of the plan's Guard 3 (N5–N8, N5b–N5g): a
 * BOUNDARY member, a path-class character, a token-class character, the trailing-glue strip,
 * R9, R9's path exclusion, R6b, and the marker grammar each have a fixture that goes RED on
 * the same CI pass that would have certified the weakening.
 *
 * The cross-file sentinel: this file asserts the tree census file carries the literal
 * `expect(noncanonical).toEqual([])`, so deleting the gate's assertion reds a file the edit
 * did not touch (ADR-224 §Verification does the same).
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, readdirSync } from "fs";
import { resolve } from "path";
import {
  BOUNDARY,
  EXCLUDED_BY_PATH,
  INDEX_GLOBS,
  POPULATION_GLOBS,
  census,
  classifyDoc,
  fixDoc,
  readIndex,
  regionPolicyForPath,
  type DocResult,
  type Index,
  type RegionPolicy,
  type Site,
} from "../lib/harness-parity";

const FIXTURE_ROOT = resolve(import.meta.dir, "fixtures/harness-parity");

const index: Index = readIndex();

/** Read a fixture; `dir` is `skills` or `commands` and picks the policy via the lib's own mapping. */
function fixture(dir: "skills" | "commands", name: string): DocResult {
  const path = `${dir}/${name}`;
  const text = readFileSync(resolve(FIXTURE_ROOT, path), "utf-8");
  // A synthetic population path in the shape the matching glob would have produced, so the
  // policy is DERIVED from POPULATION_GLOBS, never hand-assigned here.
  const syntheticPath =
    dir === "commands"
      ? `plugins/soleur/commands/${name}`
      : `plugins/soleur/skills/${name.replace(/\.md$/, "")}/SKILL.md`;
  const policy = regionPolicyForPath(syntheticPath);
  if (policy === undefined) throw new Error(`fixture ${path}: no population glob matched ${syntheticPath}`);
  return classifyDoc(text, index, policy, path);
}

function verdicts(doc: DocResult, verdict: Site["verdict"]): Site[] {
  return doc.sites.filter((s) => s.verdict === verdict);
}

function nonc(doc: DocResult): Site[] {
  return verdicts(doc, "NONCANONICAL");
}

describe("harness-parity cross-file sentinel (N11, H1)", () => {
  test("the tree census file asserts the absolute property with the exact literal", () => {
    const tree = readFileSync(resolve(import.meta.dir, "harness-parity-tree.test.ts"), "utf-8");
    // Anchored on the CODE line, never a bare substring: the tree file's header comment quotes
    // this literal, and a substring match was satisfied by the comment with the assertion
    // deleted (measured — Guard 3 rows N11 and H1 survived the first battery).
    expect(tree).toMatch(/^\s+expect\(noncanonical\)\.toEqual\(\[\]\);$/m);
    expect(tree).toContain("readPopulation()");
    expect(tree).toContain("EXPECTED_SOLEUR_AGENT_COUNT");
  });
});

describe("harness-parity fixtures — index and policy plumbing", () => {
  test("readIndex resolves a non-empty index with the registry's leaf and stem maps", () => {
    expect(index.skillNames.has("plan")).toBe(true);
    expect(index.canonicalIds.has("soleur:plan")).toBe(true);
    expect(index.canonicalIds.has("soleur:product:cpo")).toBe(true);
    expect(index.agentLeaves.get("cpo")).toBe("soleur:product:cpo");
    expect(index.grokStems.get("soleur-product-cpo")).toBe("soleur:product:cpo");
  });

  test("regionPolicyForPath derives the policy from the matching population glob", () => {
    expect(regionPolicyForPath("plugins/soleur/skills/plan/SKILL.md")).toBe("skill");
    expect(regionPolicyForPath("plugins/soleur/commands/go.md")).toBe("command");
    expect(regionPolicyForPath("plugins/soleur/codex/skills/go/SKILL.md")).toBe("skill");
    expect(regionPolicyForPath("plugins/soleur/devin/skills/go/SKILL.md")).toBe("skill");
    // N12: a nested SKILL.md is NOT a population member under `:(glob)`.
    expect(regionPolicyForPath("plugins/soleur/skills/plan/references/SKILL.md")).toBeUndefined();
    expect(regionPolicyForPath("plugins/soleur/agents/product/cpo.md")).toBeUndefined();
  });

  test("every population and index pathspec carries :(glob) magic (N12)", () => {
    for (const g of POPULATION_GLOBS) expect(g.pathspec.startsWith(":(glob)")).toBe(true);
    for (const g of Object.values(INDEX_GLOBS)) expect(g.startsWith(":(glob)")).toBe(true);
    // INDEX_GLOBS and POPULATION_GLOBS are distinct constants (spec-flow #7b): emptying one
    // must not empty the other.
    expect(POPULATION_GLOBS.map((g) => g.pathspec)).not.toEqual(Object.values(INDEX_GLOBS));
  });

  test("help.md is excluded by path with a stated reason", () => {
    const reason = EXCLUDED_BY_PATH.get("plugins/soleur/commands/help.md");
    expect(reason).toMatch(/whole-file exemption/);
    // The reason carries a measurement, so it is pinned as one: 11 marker pairs / 19 lines / 34
    // sites, re-derivable by running classifyDoc over help.md under the command policy.
    expect(reason).toMatch(/11 marker pairs \(22 lines\) around 19 content lines carrying 34 sites/);
  });

  test("BOUNDARY admits no invocation sigil", () => {
    for (const sigil of ["/", "$", "@", "!", "%", "~", "\\"]) expect(BOUNDARY.has(sigil)).toBe(false);
    for (const member of [" ", "`", "(", "[", "{", "*", ".", "=", "+", "&", "?", "#", "→", "—", "–"]) {
      expect(BOUNDARY.has(member)).toBe(true);
    }
  });

  test("the fixture corpus is the corpus this file enumerates (no orphan fixture)", () => {
    const onDisk = [
      ...readdirSync(resolve(FIXTURE_ROOT, "skills")).map((f) => `skills/${f}`),
      ...readdirSync(resolve(FIXTURE_ROOT, "commands")).map((f) => `commands/${f}`),
    ].sort();
    const here = readFileSync(import.meta.path, "utf-8");
    for (const f of onDisk) {
      const [dir, name] = f.split("/");
      expect(here).toContain(name);
    }
    expect(onDisk.length).toBeGreaterThanOrEqual(28); // the plan's Phase 2 table has 28 file rows
  });
});

describe("harness-parity fixtures — must-PASS (permitted contexts)", () => {
  test("canonical.md: 4 CANONICAL, 0 NONCANONICAL", () => {
    const doc = fixture("skills", "canonical.md");
    expect(nonc(doc)).toEqual([]);
    expect(verdicts(doc, "CANONICAL").map((s) => s.raw).sort()).toEqual(
      ["soleur:go", "soleur:plan", "soleur:preflight", "soleur:product:cpo"].sort(),
    );
    expect(doc.errors).toEqual([]);
  });

  test("bare-prose.md: BARE only (R6 — skill names are English words)", () => {
    const doc = fixture("skills", "bare-prose.md");
    expect(nonc(doc)).toEqual([]);
    expect(doc.sites.every((s) => s.verdict === "BARE")).toBe(true);
    expect(verdicts(doc, "BARE").map((s) => s.raw).sort()).toEqual(["plan", "plan", "review", "work"]);
  });

  test("path.md: PATH only (R7 — path components)", () => {
    const doc = fixture("skills", "path.md");
    expect(nonc(doc)).toEqual([]);
    expect(doc.sites.every((s) => s.verdict === "PATH")).toBe(true);
    expect(verdicts(doc, "PATH").map((s) => s.raw).sort()).toEqual(
      ["cpo", "plan", "plan", "plan", "soleur-product-cpo"].sort(),
    );
  });

  test("path-home-relative.md: `~/` is a path component, not a sigil (PATH_PREV)", () => {
    const doc = fixture("skills", "path-home-relative.md");
    expect(nonc(doc)).toEqual([]);
    expect(verdicts(doc, "PATH").map((s) => s.raw).sort()).toEqual(["plan", "work"]);
  });

  test("path-compound.md: not a reference at all (R9 path exclusion — N5f)", () => {
    const doc = fixture("skills", "path-compound.md");
    expect(doc.sites).toEqual([]);
  });

  test("boundary-punctuation.md: every BOUNDARY member and the token class (N5, N5c)", () => {
    const doc = fixture("skills", "boundary-punctuation.md");
    expect(nonc(doc)).toEqual([]);
    // Each member admits the bare word: `=`, `+`, `→`, `.`, `?` and line start / whitespace.
    expect(verdicts(doc, "BARE").map((s) => `${s.before}${s.raw}`).sort()).toEqual(
      ["=plan", "+work", "→work", ".go", "?plan", " deepen-plan", "\nplan", "\nplan"].sort(),
    );
    // `-` is in the token class, so `--plan`, `re-plan`, `post-review` and `#plan-heading` are
    // whole tokens that name nothing — N5c (drop `-`) would make `deepen-plan` report `plan`.
    expect(doc.sites.map((s) => s.raw)).not.toContain("re-plan");
    expect(doc.sites.map((s) => s.raw)).not.toContain("post-review");
    expect(doc.sites.map((s) => s.raw)).not.toContain("breach-notice-triage");
    expect(doc.sites.filter((s) => s.line === 8)).toEqual([]);
    expect(doc.sites.filter((s) => s.line === 9)).toEqual([]);
  });

  test("commands/region-forms.md: EXEMPT inside harness-forms under the command policy (H3)", () => {
    const doc = fixture("commands", "region-forms.md");
    expect(nonc(doc)).toEqual([]);
    expect(doc.errors).toEqual([]);
    expect(verdicts(doc, "EXEMPT").map((s) => s.raw)).toEqual(["go"]);
  });

  test("commands/region-nested-unknown.md: unknown markers are transparent (H3)", () => {
    const doc = fixture("commands", "region-nested-unknown.md");
    expect(nonc(doc)).toEqual([]);
    expect(doc.errors).toEqual([]);
    expect(verdicts(doc, "EXEMPT").map((s) => s.raw)).toEqual(["go"]);
  });
});

describe("harness-parity fixtures — NONCANONICAL rules and messages", () => {
  test("grok-slash.md: 4 NONCANONICAL grok, message ends `write soleur:plan` (R8, N5, N5b)", () => {
    const doc = fixture("skills", "grok-slash.md");
    const hits = nonc(doc);
    expect(hits.length).toBe(4);
    for (const h of hits) {
      expect(h.attribution).toBe("grok");
      expect(h.message).toMatch(/: \/plan — grok; write soleur:plan$/);
    }
    expect(hits.map((h) => h.line)).toEqual([3, 4, 5, 6]);
    expect(doc.sites.filter((s) => s.verdict === "BARE" || s.verdict === "PATH")).toEqual([]);
  });

  test("claude-devin-slash.md: 2 NONCANONICAL claude/devin (R1)", () => {
    const hits = nonc(fixture("skills", "claude-devin-slash.md"));
    expect(hits.map((h) => h.message)).toEqual([
      "skills/claude-devin-slash.md:3: /soleur:plan — claude/devin; write soleur:plan",
      "skills/claude-devin-slash.md:3: /soleur:work — claude/devin; write soleur:work",
    ]);
  });

  test("codex-dollar.md: 1 NONCANONICAL codex (R1)", () => {
    const hits = nonc(fixture("skills", "codex-dollar.md"));
    expect(hits.map((h) => h.message)).toEqual([
      "skills/codex-dollar.md:3: $soleur:plan — codex; write soleur:plan",
    ]);
  });

  test("claude-agent-mention.md: 1 NONCANONICAL claude, hint is the registry id (R4)", () => {
    const hits = nonc(fixture("skills", "claude-agent-mention.md"));
    expect(hits.map((h) => h.message)).toEqual([
      "skills/claude-agent-mention.md:3: @agent-soleur:product:cpo — claude; write soleur:product:cpo",
    ]);
  });

  test("claude-agent-leaf-mention.md: 3 NONCANONICAL claude, hints resolve to registry ids (R9, N5d)", () => {
    const hits = nonc(fixture("skills", "claude-agent-leaf-mention.md"));
    expect(hits.map((h) => h.message)).toEqual([
      "skills/claude-agent-leaf-mention.md:3: @agent-cpo — claude; write soleur:product:cpo",
      "skills/claude-agent-leaf-mention.md:3: @agent-kieran-rails-reviewer — claude; write soleur:engineering:review:kieran-rails-reviewer",
      "skills/claude-agent-leaf-mention.md:3: @agent-soleur-product-cpo — claude; write soleur:product:cpo",
    ]);
  });

  test("bare-agent-leaf.md: 3 NONCANONICAL bare leaves, dead on grok, hint = registry id (R6b, N5g)", () => {
    const hits = nonc(fixture("skills", "bare-agent-leaf.md"));
    expect(hits.length).toBe(3);
    for (const h of hits) {
      expect(h.attribution).toBe("bare-leaf");
      expect(h.message).toContain("bare agent leaf, dead on grok");
      expect(h.message).toContain("brace/rename the identifier");
    }
    expect(hits[0].message).toMatch(
      /^skills\/bare-agent-leaf\.md:3: cpo — bare agent leaf, dead on grok; write soleur:product:cpo/,
    );
    expect(hits[1].message).toContain("write soleur:engineering:research:git-history-analyzer");
    expect(hits[2].message).toContain("write soleur:engineering:review:security-sentinel");
  });

  test("grok-stem.md: 1 NONCANONICAL grok, hint resolves the stem (R5)", () => {
    const hits = nonc(fixture("skills", "grok-stem.md"));
    expect(hits.map((h) => h.message)).toEqual([
      "skills/grok-stem.md:3: soleur-product-cpo — grok; write soleur:product:cpo",
    ]);
  });

  test("trailing-punctuation.md: 4 NONCANONICAL — trailing glue is stripped for lookup (Kieran #1, N5e)", () => {
    const hits = nonc(fixture("skills", "trailing-punctuation.md"));
    expect(hits.map((h) => `${h.before}${h.raw}`)).toEqual(["/plan:", "/work-", "@agent-cpo:", " soleur-product-cpo:"]);
    expect(hits.map((h) => h.fix)).toEqual(["soleur:plan", "soleur:work", "soleur:product:cpo", "soleur:product:cpo"]);
  });

  test("metavariable.md: 1 UNKNOWN-NS and 1 NONCANONICAL (R3, R1 — H3)", () => {
    const doc = fixture("skills", "metavariable.md");
    expect(verdicts(doc, "UNKNOWN-NS").length).toBe(1);
    const hits = nonc(doc);
    expect(hits.length).toBe(1);
    expect(hits[0].before).toBe("/");
    expect(hits[0].attribution).toBe("claude-devin");
  });

  test("novel-sigil.md: 3 NONCANONICAL unrecognised sigil with the brace/rename tail", () => {
    const hits = nonc(fixture("skills", "novel-sigil.md"));
    expect(hits.map((h) => `${h.before}${h.raw}`)).toEqual(["%plan", "!plan", "~plan"]);
    for (const h of hits) {
      expect(h.attribution).toBe("unrecognised");
      expect(h.message).toContain("unrecognised sigil; write soleur:plan");
      expect(h.message).toContain("brace/rename the identifier");
    }
  });

  test("unknown-name.md: /frobnicate is nothing, $soleur:frobnicate is R1 (the index bound)", () => {
    const doc = fixture("skills", "unknown-name.md");
    const hits = nonc(doc);
    expect(hits.length).toBe(1);
    expect(`${hits[0].before}${hits[0].raw}`).toBe("$soleur:frobnicate");
    expect(doc.sites.map((s) => s.raw)).not.toContain("frobnicate");
  });

  test("fenced.md: fenced code is classified like prose (H5)", () => {
    const hits = nonc(fixture("skills", "fenced.md"));
    expect(hits.map((h) => h.message)).toEqual(["skills/fenced.md:4: /soleur:work — claude/devin; write soleur:work"]);
  });

  test("region-forms-in-skill.md: harness-forms is not honoured under skills/ (N6)", () => {
    const doc = fixture("skills", "region-forms-in-skill.md");
    expect(nonc(doc).map((h) => h.message)).toEqual([
      "skills/region-forms-in-skill.md:4: /go — grok; write soleur:go",
    ]);
    expect(verdicts(doc, "EXEMPT")).toEqual([]);
  });

  test("commands/region-unknown-name.md: an unknown marker is content, not a region (N7)", () => {
    const doc = fixture("commands", "region-unknown-name.md");
    expect(nonc(doc).map((h) => h.message)).toEqual([
      "commands/region-unknown-name.md:4: /plan — grok; write soleur:plan",
    ]);
    expect(doc.errors).toEqual([]);
  });

  test("two-violations.md: both line numbers reported (the classifier does not stop at the first)", () => {
    const hits = nonc(fixture("skills", "two-violations.md"));
    expect(hits.map((h) => h.line)).toEqual([4, 5]);
    expect(hits.map((h) => h.attribution)).toEqual(["grok", "codex"]);
  });

  test("frontmatter.md: frontmatter is not exempt", () => {
    const hits = nonc(fixture("skills", "frontmatter.md"));
    expect(hits.map((h) => h.message)).toEqual([
      "skills/frontmatter.md:3: /soleur:one-shot — claude/devin; write soleur:one-shot",
    ]);
  });
});

describe("harness-parity fixtures — marker grammar", () => {
  test("commands/region-malformed.md: case, CRLF and inline text are each RED malformed (N8)", () => {
    const doc = fixture("commands", "region-malformed.md");
    expect(doc.errors.length).toBe(3);
    for (const e of doc.errors) expect(e).toMatch(/malformed marker/);
    expect(doc.errors.map((e) => /:(\d+):/.exec(e)?.[1])).toEqual(["3", "5", "7"]);
  });

  test("commands/region-stray-end.md: RED", () => {
    const doc = fixture("commands", "region-stray-end.md");
    expect(doc.errors).toEqual(["commands/region-stray-end.md:3: stray harness-forms:end with no open region"]);
  });

  test("commands/region-unterminated.md: RED, and the open region does not exempt the doc", () => {
    const doc = fixture("commands", "region-unterminated.md");
    expect(doc.errors).toEqual(["commands/region-unterminated.md:3: harness-forms:start never closed"]);
  });

  test("commands/region-double-start.md: RED", () => {
    const doc = fixture("commands", "region-double-start.md");
    expect(doc.errors).toEqual(["commands/region-double-start.md:4: harness-forms:start while a region is open"]);
  });
});

describe("harness-parity fixtures — fixDoc and census", () => {
  test("fix-roundtrip.md: fixDoc inverts the mechanical shapes only, and is idempotent (H4)", () => {
    const before = readFileSync(resolve(FIXTURE_ROOT, "skills/fix-roundtrip.md"), "utf-8");
    const once = fixDoc(before, index);
    expect(once).not.toBe(before);
    expect(fixDoc(once, index)).toBe(once);
    const after = classifyDoc(once, index, "skill", "skills/fix-roundtrip.md");
    // The only residue is the bare leaf, which is a hand edit by design (never rewritten).
    expect(nonc(after).map((h) => h.shape)).toEqual(["bare-agent-leaf"]);
    expect(once).toContain('Task cpo("left alone")');
    // Under the skill policy the region is not honoured, so its `/go` is a site and is fixed;
    // under the command policy the region is left byte-identical.
    expect(once).toContain("<!-- harness-forms:start -->\nsoleur:go\n<!-- harness-forms:end -->");
    const asCommand = fixDoc(before, index, "command");
    expect(asCommand).toContain("<!-- harness-forms:start -->\n/go\n<!-- harness-forms:end -->");
    expect(asCommand).toContain("Run soleur:plan then soleur:work then soleur:product:cpo.");
    expect(once).toContain("Run soleur:plan then soleur:work then soleur:product:cpo.");
    expect(once).toContain("Then soleur:plan and `soleur:review` and (soleur:ship: done).");
  });

  test("fix-refuses-unsound.md: fixDoc never emits a rewrite that classifies non-canonical", () => {
    const before = readFileSync(resolve(FIXTURE_ROOT, "skills/fix-refuses-unsound.md"), "utf-8");
    const once = fixDoc(before, index);
    // `~/ship` is a PATH and needs no rewrite; `!/plan` and `%/plan` are sigils the splice
    // cannot repair (it consumes the preceding character), so fixDoc leaves them for the hand
    // edit rather than emitting `!soleur:plan`, which no further --fix pass can undo.
    expect(once).toBe(before);
    const after = classifyDoc(once, index, "skill", "skills/fix-refuses-unsound.md");
    expect(nonc(after).map((h) => `${h.before}${h.raw}`)).toEqual(["/plan", "/plan"]);
    expect(verdicts(after, "PATH").map((s) => s.raw)).toEqual(["ship"]);
  });

  test("census over an empty population throws (N4)", () => {
    expect(() => census([], index)).toThrow("harness-parity: 0 docs examined");
  });

  test("census folds per-doc results and attributes each NONCANONICAL site", () => {
    const docs = (["grok-slash.md", "codex-dollar.md", "bare-agent-leaf.md", "canonical.md"] as const).map((name) => ({
      path: `skills/${name}`,
      text: readFileSync(resolve(FIXTURE_ROOT, "skills", name), "utf-8"),
      regionPolicy: "skill" as RegionPolicy,
    }));
    const result = census(docs, index);
    expect(result.docsExamined).toBe(4);
    expect(result.noncanonical.length).toBe(8);
    expect(result.docsWithNoncanonical).toBe(3);
    expect(result.attribution.grok).toBe(4);
    expect(result.attribution.codex).toBe(1);
    expect(result.attribution["bare-leaf"]).toBe(3);
    expect(result.totals.CANONICAL).toBe(4);
  });

  test("H5: the fixture corpus through census reds on exactly the violating fixtures", () => {
    const load = (dir: "skills" | "commands") =>
      readdirSync(resolve(FIXTURE_ROOT, dir)).map((name) => ({
        path: `${dir}/${name}`,
        text: readFileSync(resolve(FIXTURE_ROOT, dir, name), "utf-8"),
        regionPolicy: (dir === "commands" ? "command" : "skill") as RegionPolicy,
      }));
    const result = census([...load("skills"), ...load("commands")], index);
    const red = result.docs
      .filter((d) => d.errors.length > 0 || d.sites.some((s) => s.verdict === "NONCANONICAL"))
      .map((d) => d.path)
      .sort();
    expect(red).toEqual(
      [
        "commands/region-double-start.md",
        "commands/region-malformed.md",
        "commands/region-stray-end.md",
        "commands/region-unknown-name.md",
        "commands/region-unterminated.md",
        "skills/bare-agent-leaf.md",
        "skills/claude-agent-leaf-mention.md",
        "skills/claude-agent-mention.md",
        "skills/claude-devin-slash.md",
        "skills/codex-dollar.md",
        "skills/fenced.md",
        "skills/fix-refuses-unsound.md",
        "skills/fix-roundtrip.md",
        "skills/frontmatter.md",
        "skills/grok-slash.md",
        "skills/grok-stem.md",
        "skills/metavariable.md",
        "skills/novel-sigil.md",
        "skills/region-forms-in-skill.md",
        "skills/trailing-punctuation.md",
        "skills/two-violations.md",
        "skills/unknown-name.md",
      ].sort(),
    );
  });
});
