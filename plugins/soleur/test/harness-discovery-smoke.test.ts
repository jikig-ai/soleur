import { describe, test, expect } from "bun:test";
import { mkdirSync, mkdtempSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import {
  expectedSkills,
  isStructurallyParseable,
  parseCodexPromptInput,
  parseDevinSkillsList,
  resolveExit,
  verdict,
} from "../scripts/harness-discovery-smoke";

// Guard 6 of the harness-parity hardening bundle (ADR-240).
//
// Every row below is a PURE-function case over SYNTHESIZED output — never a copied
// transcript (`cq-test-fixtures-synthesized-only`). The shapes mirror what was measured
// on Codex CLI 0.156.1 and Devin CLI 3000.11.1 on 2026-09-23; the live CI arm exercises
// the same functions under the real binaries.
//
// ANCHOR: the expectation comes from the manifests, which ship to users; the observation
// comes from the vendor binary. No single diff can make the two agree without a
// behaviour change the CLI would reflect.

function fixturePluginRoot(roots: Record<string, string[]>): { root: string; manifest: string } {
  const root = mkdtempSync(join(tmpdir(), "harness-discovery-fixture-"));
  for (const [rel, skills] of Object.entries(roots)) {
    for (const name of skills) {
      mkdirSync(join(root, rel, name), { recursive: true });
      writeFileSync(join(root, rel, name, "SKILL.md"), `---\nname: ${name}\n---\n`);
    }
  }
  const manifest = join(root, "plugin.json");
  writeFileSync(manifest, JSON.stringify({ skills: Object.keys(roots).map((r) => `./${r}`) }));
  return { root, manifest };
}

describe("expectedSkills — keyed on the directory basename", () => {
  test("a skill that lost its frontmatter name: is still expected", () => {
    const { root, manifest } = fixturePluginRoot({ skills: ["plan", "ship"] });
    // Blank the frontmatter entirely; the expectation must not shrink with it.
    writeFileSync(join(root, "skills/plan/SKILL.md"), "# no frontmatter at all\n");
    const expected = expectedSkills(manifest, root);
    expect([...expected.keys()].sort()).toEqual(["soleur:plan", "soleur:ship"]);
  });

  test("multiplicity k is derived from the declared roots, not acked by hand", () => {
    const { root, manifest } = fixturePluginRoot({
      skills: ["plan", "go", "help"],
      "codex/skills": ["go", "help"],
    });
    const expected = expectedSkills(manifest, root);
    expect(expected.get("soleur:plan")).toBe(1);
    expect(expected.get("soleur:go")).toBe(2);
    expect(expected.get("soleur:help")).toBe(2);
  });

  test("a manifest declaring no roots throws rather than expecting nothing", () => {
    const root = mkdtempSync(join(tmpdir(), "harness-discovery-empty-"));
    const manifest = join(root, "plugin.json");
    writeFileSync(manifest, JSON.stringify({ skills: [] }));
    expect(() => expectedSkills(manifest, root)).toThrow();
  });
});

describe("parsers", () => {
  test("codex: the listing is decoded from the escaped JSON string first", () => {
    // The measured shape: real output carries `\n` as two characters, not newlines.
    const escaped = `{"input":"<skills_instructions>\\n- soleur:plan: plan things\\n- soleur:ship: ship things\\n</skills_instructions>"}`;
    const counts = parseCodexPromptInput(escaped);
    expect([...counts.keys()].sort()).toEqual(["soleur:plan", "soleur:ship"]);
    // A line-anchored regex over the RAW bytes returns zero — this is the regression.
    expect([...escaped.matchAll(/^\s*-\s+(soleur:[a-z0-9-]+):/gm)]).toHaveLength(0);
  });

  test("codex: repeated names are counted, not deduped by the parser", () => {
    const counts = parseCodexPromptInput(
      ["<skills_instructions>", "- soleur:go: x", "- soleur:go: x", "- soleur:plan: y", "</skills_instructions>"].join("\n"),
    );
    expect(counts.get("soleur:go")).toBe(2);
    expect(counts.get("soleur:plan")).toBe(1);
  });

  test("devin: one record per registration line", () => {
    const counts = parseDevinSkillsList(
      ["Available skills:", "  /soleur:plan  Plan things", "  /soleur:ship  Ship things", ""].join("\n"),
    );
    expect([...counts.keys()].sort()).toEqual(["soleur:plan", "soleur:ship"]);
  });
});

describe("verdict — one multiplicity mode per harness run", () => {
  const expected = new Map([
    ["soleur:plan", 1],
    ["soleur:go", 2],
    ["soleur:help", 2],
  ]);

  test("row 4 must-PASS: an additive listing (k each) is clean", () => {
    const v = verdict(expected, new Map([["soleur:plan", 1], ["soleur:go", 2], ["soleur:help", 2]]));
    expect(v).toMatchObject({ missing: [], extra: [], badMultiplicity: [], mode: "additive" });
  });

  test("row 4 must-PASS: a dedup listing (1 each) is clean", () => {
    const v = verdict(expected, new Map([["soleur:plan", 1], ["soleur:go", 1], ["soleur:help", 1]]));
    expect(v).toMatchObject({ missing: [], extra: [], badMultiplicity: [], mode: "dedup" });
  });

  test("row 4: k+1 occurrences are bad multiplicity", () => {
    const v = verdict(expected, new Map([["soleur:plan", 1], ["soleur:go", 3], ["soleur:help", 2]]));
    expect(v.badMultiplicity.length).toBeGreaterThan(0);
  });

  test("row 4b: a MIXED mode in one run is bad multiplicity", () => {
    // `go` twice, `help` once. Every name satisfies "1 or k" on its own, which is
    // exactly why a per-name test passes this and the mode inference does not.
    const v = verdict(expected, new Map([["soleur:plan", 1], ["soleur:go", 2], ["soleur:help", 1]]));
    expect(v.mode).toBe("indeterminate");
    expect(v.badMultiplicity.join(" ")).toContain("mixed multiplicity mode");
  });

  test("row 1: a name the CLI omitted is MISSING", () => {
    const v = verdict(expected, new Map([["soleur:go", 2], ["soleur:help", 2]]));
    expect(v.missing).toEqual(["soleur:plan"]);
  });

  test("row 5: a soleur: skill from outside the manifest roots is EXTRA", () => {
    const v = verdict(
      expected,
      new Map([["soleur:plan", 1], ["soleur:go", 2], ["soleur:help", 2], ["soleur:rogue", 1]]),
    );
    expect(v.extra).toEqual(["soleur:rogue"]);
  });

  test("row 7 anti-vacuity: the expectation carries both a k>=2 and a k=1 name", () => {
    // Mirrors components.test.ts. With no multi-root name the mode can never be
    // inferred and the whole multiplicity clause asserts nothing; with no k=1 name
    // the dedup/additive distinction is untestable.
    const multi = [...expected.values()].filter((k) => k >= 2).length;
    const single = [...expected.values()].filter((k) => k === 1).length;
    expect(
      { multi: multi > 0, single: single > 0 },
      "no manifest reached the multi-root path; the multiplicity clause asserted nothing",
    ).toEqual({ multi: true, single: true });
  });

  test("harness row: verdict fed discovered === expected is tautological, so the suite never does that", () => {
    // Driving it once, explicitly, to show what the tautology looks like: every case
    // above builds `discovered` independently of `expected`.
    const tautology = verdict(expected, new Map(expected));
    expect(tautology.missing).toEqual([]);
  });
});

describe("resolveExit — UNRESOLVED is never a PASS, and never a partial loss", () => {
  const clean = { missing: [], extra: [], badMultiplicity: [], mode: "additive" as const };

  test("row 3: an empty, structurally-unreadable listing exits 3, never 0", () => {
    expect(resolveExit({ cliPresent: true, parseable: false })).toEqual({
      code: 3,
      reason: "unparseable-output",
    });
  });

  test("row 3b: a listing that PARSED but is short exits 1 and names the loss", () => {
    const v = { missing: Array.from({ length: 40 }, (_, i) => `soleur:s${i}`), extra: [], badMultiplicity: [], mode: "dedup" as const };
    const r = resolveExit({ cliPresent: true, parseable: true, verdict: v });
    expect(r.code).toBe(1);
    expect(r.reason).toContain("40 missing");
  });

  test("row 6: a missing binary and a version mismatch are distinct exit-3 reasons", () => {
    expect(resolveExit({ cliPresent: false, parseable: false })).toEqual({ code: 3, reason: "cli-missing" });
    expect(
      resolveExit({ cliPresent: true, parseable: true, version: "0.157.0", pin: "0.156.1", verdict: clean }),
    ).toEqual({ code: 3, reason: "version-mismatch:0.157.0!=0.156.1" });
  });

  test("an install failure is its own reason, not a parse failure", () => {
    expect(resolveExit({ cliPresent: true, installFailed: true, parseable: false })).toEqual({
      code: 3,
      reason: "install-failed",
    });
  });

  test("the clean path exits 0 and reports the inferred mode", () => {
    const r = resolveExit({ cliPresent: true, parseable: true, verdict: clean });
    expect(r.code).toBe(0);
    expect(r.reason).toContain("additive");
  });
});

describe("structural parseability", () => {
  test("codex: the marker is what distinguishes unreadable from empty", () => {
    expect(isStructurallyParseable("codex", "garbage with no marker", new Map())).toBe(false);
    expect(isStructurallyParseable("codex", "<skills_instructions>\n</skills_instructions>", new Map())).toBe(true);
    expect(isStructurallyParseable("codex", "anything", new Map([["soleur:plan", 1]]))).toBe(true);
  });

  test("devin: zero soleur: lines is unreadable", () => {
    expect(isStructurallyParseable("devin", "Available skills:\n", new Map())).toBe(false);
    expect(isStructurallyParseable("devin", "  /soleur:plan", new Map([["soleur:plan", 1]]))).toBe(true);
  });
});

describe("the live manifests are the ones this gate will judge", () => {
  test("both declare two roots, and the expectation covers every tracked skill dir", () => {
    const codex = expectedSkills(new URL("../.codex-plugin/plugin.json", import.meta.url).pathname);
    const devin = expectedSkills(new URL("../.devin-plugin/plugin.json", import.meta.url).pathname);
    // Floor: a manifest that dropped `./skills` collapses the expectation.
    expect(codex.size).toBeGreaterThanOrEqual(100);
    expect(devin.size).toBeGreaterThanOrEqual(100);
    // The k>=2 names are exactly the shared shim stems, derived not hardcoded.
    expect([...codex.entries()].filter(([, k]) => k >= 2).map(([n]) => n).sort()).toEqual([
      "soleur:go",
      "soleur:help",
      "soleur:sync",
    ]);
  });
});
