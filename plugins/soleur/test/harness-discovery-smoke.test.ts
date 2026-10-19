import { describe, test, expect } from "bun:test";
import { mkdirSync, mkdtempSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import {
  expectedOpenCodeSkillFiles,
  expectedSkills,
  isStructurallyParseable,
  parseCodexPromptInput,
  parseArgs,
  parseDevinSkillsList,
  parseOpenCodeSkillList,
  resolveBin,
  resolveExit,
  sanitizeForLog,
  verdict,
} from "../scripts/harness-discovery-smoke";
import { PLUGIN_ROOT_TOKEN } from "../scripts/sync-opencode-adapter";
import { MIN_MANIFEST_DECLARED_SKILLS } from "./lib/population-floors";

// Guard 6 of the harness-parity hardening bundle (ADR-245).
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

  test("an ABSENT declared root throws — it does not silently expect less", () => {
    // The shape that made the gate exit 0 on a 99-skill loss: one root typo'd,
    // the expectation collapses to the shim stems, all of them are discovered,
    // and `verdict` is clean.
    const { root, manifest } = fixturePluginRoot({ skills: ["plan"] });
    writeFileSync(manifest, JSON.stringify({ skills: ["./skills", "./skilz"] }));
    expect(() => expectedSkills(manifest, root)).toThrow(/does not exist/);
  });

  test("roots that exist but hold no skill throw", () => {
    const root = mkdtempSync(join(tmpdir(), "harness-discovery-bare-"));
    mkdirSync(join(root, "skills"), { recursive: true });
    const manifest = join(root, "plugin.json");
    writeFileSync(manifest, JSON.stringify({ skills: ["./skills"] }));
    expect(() => expectedSkills(manifest, root)).toThrow(/contain no SKILL\.md/);
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

const clean = { missing: [], extra: [], badMultiplicity: [], mode: "additive" as const };

describe("resolveExit — UNRESOLVED is never a PASS, and never a partial loss", () => {

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

  test("an unreadable version is UNRESOLVED, never an unenforced pin", () => {
    // `cliVersion()` returns undefined whenever `--version` exits non-zero or
    // prints no semver. The old `pin && version && …` form skipped the
    // comparison entirely there, so `--pin` failed OPEN on exactly the binary
    // it could not identify.
    expect(resolveExit({ cliPresent: true, parseable: true, pin: "0.156.1", verdict: clean })).toEqual({
      code: 3,
      reason: "version-unknown",
    });
  });

  test("a probe that died is UNRESOLVED, not a set mismatch", () => {
    // A timed-out CLI yields PARTIAL output, and a partial listing parses — so
    // without this the gate reports a regression that did not happen.
    const v = { missing: ["soleur:a", "soleur:b"], extra: [], badMultiplicity: [], mode: "dedup" as const };
    expect(resolveExit({ cliPresent: true, probeFailed: true, parseable: true, verdict: v })).toEqual({
      code: 3,
      reason: "probe-failed",
    });
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

  test("devin: the header is the marker, so a total loss is FAIL and not UNRESOLVED", () => {
    // This row previously asserted `false` for a listing that carried the header
    // and no names — pinning the bug. A CLI that answered and registered NOTHING
    // is the worst regression this gate catches; grading it `unparseable-output`
    // made it indistinguishable from an outage, and would have been the triage
    // signal #8574's soak is read from.
    expect(isStructurallyParseable("devin", "Available skills:\n", new Map())).toBe(true);
    expect(isStructurallyParseable("devin", "  /soleur:plan", new Map([["soleur:plan", 1]]))).toBe(true);
    // Genuinely unreadable — no header, no names — stays UNRESOLVED.
    expect(isStructurallyParseable("devin", "boom: connection refused", new Map())).toBe(false);
  });

  test("devin: a header with no names exits 1 naming them, not 3", () => {
    const expected = new Map([["soleur:plan", 1], ["soleur:ship", 1]]);
    const raw = "Available skills:\n";
    const discovered = parseDevinSkillsList(raw);
    const parseable = isStructurallyParseable("devin", raw, discovered);
    const r = resolveExit({ cliPresent: true, parseable, verdict: verdict(expected, discovered) });
    expect(r.code).toBe(1);
    expect(r.reason).toContain("2 missing");
  });
});

// OpenCode's skill ids are BARE directory basenames with no `soleur:` namespace
// (measurement §2.3), so the id `plan` is shared by this plugin's skill and by any
// operator-level `plan` in `~/.claude/skills` or `~/.agents/skills`. The id therefore
// cannot anchor the expectation; the absolute `path` the server reports is what does.
// The probe drives a real server (measurement §11.0), which is why the shapes below
// mirror a `/api/skill` payload rather than a transcript.
function fixtureOpenCodeRoot(names: string[]): { root: string; manifest: string } {
  const root = mkdtempSync(join(tmpdir(), "harness-discovery-opencode-"));
  for (const name of names) {
    mkdirSync(join(root, "skills", name), { recursive: true });
    writeFileSync(join(root, "skills", name, "SKILL.md"), `---\nname: ${name}\n---\n`);
  }
  const manifest = join(root, "opencode.json");
  writeFileSync(manifest, JSON.stringify({ skills: [`${PLUGIN_ROOT_TOKEN}/skills`] }));
  return { root, manifest };
}

describe("opencode — the listing is keyed on `path`, never on the bare id", () => {
  test("the expectation is the declared roots' SKILL.md files, sentinel resolved", () => {
    const { root, manifest } = fixtureOpenCodeRoot(["plan", "ship"]);
    const expected = expectedOpenCodeSkillFiles(manifest, root);
    expect([...expected.keys()].sort()).toEqual(["skills/plan/SKILL.md", "skills/ship/SKILL.md"]);
    expect([...expected.values()]).toEqual([1, 1]);
  });

  test("a declared root that does not exist throws rather than expecting less", () => {
    const { root, manifest } = fixtureOpenCodeRoot(["plan"]);
    writeFileSync(manifest, JSON.stringify({ skills: [`${PLUGIN_ROOT_TOKEN}/skilz`] }));
    expect(() => expectedOpenCodeSkillFiles(manifest, root)).toThrow(/does not exist/);
  });

  test("a directory under a declared root with no SKILL.md is not a skill", () => {
    const { root, manifest } = fixtureOpenCodeRoot(["plan"]);
    mkdirSync(join(root, "skills", "references"), { recursive: true });
    expect([...expectedOpenCodeSkillFiles(manifest, root).keys()]).toEqual(["skills/plan/SKILL.md"]);
  });

  test("a bare id from OUTSIDE the plugin root is not a hit, and neither is a built-in", () => {
    // The whole reason this arm keys on `path`: the second row carries the SAME id
    // (`plan`) as the first from the operator's own tree, and `/builtin/opencode.md`
    // ships with the harness. Neither may be counted as a Soleur registration.
    const { root } = fixtureOpenCodeRoot(["plan", "ship"]);
    const raw = JSON.stringify({
      location: { directory: "/elsewhere" },
      data: [
        { id: "plan", description: "…", path: join(root, "skills", "plan", "SKILL.md"), content: "…" },
        { id: "opencode", description: "…", path: "/builtin/opencode.md", content: "…" },
        { id: "plan", description: "…", path: "/home/operator/.claude/skills/plan/SKILL.md", content: "…" },
      ],
    });
    const counts = parseOpenCodeSkillList(raw, root);
    expect([...counts.keys()]).toEqual(["skills/plan/SKILL.md"]);
    expect(counts.get("skills/plan/SKILL.md")).toBe(1);
  });

  test("an unreadable payload is an empty map, not a throw — parseability decides the exit", () => {
    expect(parseOpenCodeSkillList("Error: connect ECONNREFUSED 127.0.0.1:1", "/root").size).toBe(0);
    expect(parseOpenCodeSkillList(JSON.stringify({ location: {}, data: null }), "/root").size).toBe(0);
  });
});

describe("opencode — a path-keyed verdict has no multi-root names", () => {
  const expected = new Map([
    ["skills/plan/SKILL.md", 1],
    ["skills/ship/SKILL.md", 1],
  ]);

  test("every path is k=1, so the mode is `single`, not an inferred dedup/additive", () => {
    // The Codex/Devin modes describe CROSS-ROOT multiplicity. There is none here —
    // one canonical tree, no shim roots — so reporting `indeterminate` would read
    // as a problem in a gate log when it is the normal shape.
    const v = verdict(expected, new Map(expected));
    expect(v).toMatchObject({ missing: [], extra: [], badMultiplicity: [], mode: "single" });
  });

  test("a stray plugin-local SKILL.md is EXTRA", () => {
    const v = verdict(expected, new Map([...expected, ["skills/rogue/SKILL.md", 1]]));
    expect(v.extra).toEqual(["skills/rogue/SKILL.md"]);
  });
});

describe("opencode — structural parseability and the exit taxonomy", () => {
  // Measured §11.1: until a session exists (or a config-reload fires), `GET /api/skill`
  // answers `{location, data: []}` for a fully CORRECT install.
  const emptyListing = JSON.stringify({ location: { directory: "/proj" }, data: [] });

  test("a valid payload with no data is READABLE — a total loss grades exit 1, not 3", () => {
    expect(isStructurallyParseable("opencode", emptyListing, new Map())).toBe(true);
    const expected = new Map([
      ["skills/plan/SKILL.md", 1],
      ["skills/ship/SKILL.md", 1],
    ]);
    const discovered = parseOpenCodeSkillList(emptyListing, "/proj");
    const parseable = isStructurallyParseable("opencode", emptyListing, discovered);
    const r = resolveExit({ cliPresent: true, parseable, verdict: verdict(expected, discovered) });
    expect(r.code).toBe(1);
    expect(r.reason).toContain("2 missing");
  });

  test("a non-payload response is UNRESOLVED", () => {
    expect(isStructurallyParseable("opencode", "Error: connect ECONNREFUSED", new Map())).toBe(false);
    expect(isStructurallyParseable("opencode", JSON.stringify({ location: { directory: "/p" } }), new Map())).toBe(false);
  });
});

describe("the live manifests are the ones this gate will judge", () => {
  test("both declare two roots, and the expectation covers every tracked skill dir", () => {
    const codex = expectedSkills(new URL("../.codex-plugin/plugin.json", import.meta.url).pathname);
    const devin = expectedSkills(new URL("../.devin-plugin/plugin.json", import.meta.url).pathname);
    // Floor: a manifest that dropped `./skills` collapses the expectation.
    expect(codex.size).toBeGreaterThanOrEqual(MIN_MANIFEST_DECLARED_SKILLS);
    expect(devin.size).toBeGreaterThanOrEqual(MIN_MANIFEST_DECLARED_SKILLS);
    // The k>=2 names are exactly the shared shim stems, derived not hardcoded.
    expect([...codex.entries()].filter(([, k]) => k >= 2).map(([n]) => n).sort()).toEqual([
      "soleur:go",
      "soleur:help",
      "soleur:sync",
    ]);
  });

  test("the opencode fragment declares the canonical skills root, and nothing else", () => {
    const opencode = expectedOpenCodeSkillFiles(new URL("../opencode/opencode.json", import.meta.url).pathname);
    // Floor: a fragment that dropped its `skills` root collapses the expectation.
    expect(opencode.size).toBeGreaterThanOrEqual(MIN_MANIFEST_DECLARED_SKILLS);
    // Every member is a canonical skill, and every k is 1 (there are no shim roots here).
    expect([...opencode.keys()].every((p) => /^skills\/[^/]+\/SKILL\.md$/.test(p))).toBe(true);
    expect(new Set(opencode.values())).toEqual(new Set([1]));
  });
});

describe("argument parsing refuses, rather than defaulting to something plausible", () => {
  // Both arms below were LIVE fail-opens, and both failed towards a reassuring green.
  test("an absent --harness is an error, not argv[0]", () => {
    // `argv.indexOf("--harness") + 1` is 0 when the flag is missing, so the old form read
    // the first positional as the harness and ran a whole arm nobody selected.
    expect(parseArgs(["codex"])).toEqual({ error: "missing --harness" });
    expect(parseArgs([])).toEqual({ error: "missing --harness" });
  });

  test("an unknown harness is named in the error, not silently coerced", () => {
    const r = parseArgs(["--harness", "cursor"]);
    expect("error" in r && r.error).toContain("cursor");
  });

  test("--pin without a value is an error, NOT an unpinned run", () => {
    // The dangerous direction: `undefined` is indistinguishable from "no pin given", so the
    // version comparison is skipped while the job's log still advertises a pin.
    expect("error" in parseArgs(["--harness", "codex", "--pin"])).toBe(true);
    expect("error" in parseArgs(["--harness", "codex", "--pin", "--verbose"])).toBe(true);
  });

  test("the accepting cases still accept", () => {
    expect(parseArgs(["--harness", "codex"])).toEqual({ harness: "codex" });
    expect(parseArgs(["--harness", "devin", "--pin", "3000.11.1"])).toEqual({
      harness: "devin",
      pin: "3000.11.1",
    });
    expect(parseArgs(["--harness", "opencode"])).toEqual({ harness: "opencode" });
  });
});

describe("resolveBin — the shim is followed to a HOME-independent launcher", () => {
  test("a binary that is not on PATH is undefined, not an empty string", () => {
    // `driveOpenCode` falls back to the bare name, which under a hermetic HOME would be
    // a shim that tries to reinstall — so the undefined case must be a clean signal.
    expect(resolveBin("soleur-no-such-binary-9f3a1c")).toBeUndefined();
  });
});

describe("untrusted text cannot author the CI log", () => {
  // The names in `missing`/`extra` come from directory names in the checkout, which on a fork
  // PR is the fork's. A GitHub workflow command is any line whose first non-whitespace bytes
  // are `::`, so a crafted skill directory name could emit annotations, `::add-mask::`
  // arbitrary strings out of the log, or `::stop-commands::` every real annotation after it.
  test("a line that would be a workflow command is no longer one", () => {
    expect(sanitizeForLog("::error::spoofed")).toBe(" ::error::spoofed");
    expect(sanitizeForLog("::stop-commands::tok")).toBe(" ::stop-commands::tok");
  });

  test("leading whitespace does not smuggle one through — GitHub trims it, so we must too", () => {
    expect(sanitizeForLog("\t  ::add-mask::secret")).toBe(" \t  ::add-mask::secret");
  });

  test("a bare CR starts a line too, and is normalised before the line split", () => {
    // Without the `\r` normalisation the payload is one "line" that does not START with `::`,
    // so the neutralisation never fires while a terminal still renders it as its own line.
    expect(sanitizeForLog("harmless\r::error::spoofed")).toBe("harmless\n ::error::spoofed");
  });

  test("C0 control characters are dropped, newline and tab survive", () => {
    expect(sanitizeForLog("a\u0000b\u0007c\u001bd")).toBe("abcd");
    expect(sanitizeForLog("a\nb\tc")).toBe("a\nb\tc");
  });

  test("ordinary output is returned unchanged", () => {
    const plain = "  - soleur:plan: Create implementation plans\n  - soleur:work: Execute";
    expect(sanitizeForLog(plain)).toBe(plain);
  });
});
