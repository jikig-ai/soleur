import { describe, test, expect } from "bun:test";
import { createHash } from "crypto";
import { mkdtempSync, readFileSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join, resolve } from "path";
import { MIN_TRACKED_SKILLS } from "./lib/population-floors";

// grok-harness-invoke.test.ts — Guard 1 of the harness-parity hardening bundle
// (#8390, ADR-245).
//
// PROPERTY: every skill entry file Grok Build can load carries EXACTLY ONE Grok
// invoke block, byte-equal to the canonical block, sitting before the first `# `
// heading and outside fenced code.
//
// ASSEMBLY. The chokepoint is the skills root Grok's loader reads: `.grok/config.toml`
// points at `plugins/soleur`, and skills are flat at `skills/*/SKILL.md`. The guard
// spans three pieces — the population (`git ls-files`, floored), the canonical block
// (`skills/plan/SKILL.md`, md5-pinned) and the scaffold (`init_skill.py`), so a new
// skill is born compliant rather than backfilled later.
//
// The Codex and Devin shim roots (`codex/skills/`, `devin/skills/`) are NOT
// Grok-loaded and are out of the population by design.
//
// ANCHOR (honest statement of what the md5 pin buys). The pin lives in this file, so
// one diff can move the block text, all 102 copies and the pin together: that is
// CONSISTENCY, not integrity, and it is the right trade for a template. The anchor
// outside this diff is `workflow-fidelity.test.ts`, which asserts Grok routing
// semantics without reading these bytes.

const PLUGIN_ROOT = resolve(import.meta.dir, "..");
const REPO_ROOT = resolve(PLUGIN_ROOT, "../..");
const CANONICAL_SOURCE = join(PLUGIN_ROOT, "skills/plan/SKILL.md");
const INIT_SKILL = join(PLUGIN_ROOT, "skills/skill-creator/scripts/init_skill.py");

const START = "<!-- grok-harness-invoke:start -->";
const END = "<!-- grok-harness-invoke:end -->";

// Measured 2026-09-23 over all 12 pre-backfill copies: identical bytes, all at line 10.
const CANONICAL_MD5 = "f212ba057179bf8c0e79a029af403a10";

// The floor exists so a pathspec that stops matching (a rename, a glob regression, a
// hardcoded 12-name list replacing the enumeration) cannot report a clean fleet over an
// empty or narrowed population. Single-sourced: four suites floored this same population
// at four different numbers before `population-floors.ts`.
const MIN_SKILLS = MIN_TRACKED_SKILLS;

function gitLsFiles(pathspec: string): string[] {
  const out = Bun.spawnSync(["git", "ls-files", pathspec], {
    cwd: REPO_ROOT,
    stdout: "pipe",
    stderr: "pipe",
  });
  if (out.exitCode !== 0) {
    throw new Error(`git ls-files ${pathspec} failed: ${out.stderr.toString()}`);
  }
  return out.stdout.toString().split("\n").filter(Boolean);
}

/**
 * The block as it appears in the canonical file: start-marker line through
 * end-marker line inclusive, each line carrying its trailing newline (the
 * `awk '/start/,/end/' | md5sum` convention the pin above was computed under).
 */
function extractBlock(text: string): string | null {
  const lines = text.split("\n");
  const s = lines.indexOf(START);
  const e = lines.indexOf(END);
  if (s === -1 || e === -1 || e < s) return null;
  return lines.slice(s, e + 1).join("\n") + "\n";
}

const canonicalText = readFileSync(CANONICAL_SOURCE, "utf8");
const CANONICAL = extractBlock(canonicalText);
if (CANONICAL === null) {
  throw new Error(`canonical Grok block not found in ${CANONICAL_SOURCE}`);
}

/**
 * Fenced-code spans, run-length aware: a fence opens on 3+ backticks (or tildes)
 * and closes only on a run at least as long. A naive `startsWith("```")` scanner
 * is defeated by a four-backtick fence, which is exactly the mutation row 6c
 * below drives.
 */
function fencedLineFlags(lines: string[]): boolean[] {
  const flags: boolean[] = new Array(lines.length).fill(false);
  let openLen = 0;
  let openChar = "";
  for (let i = 0; i < lines.length; i++) {
    const m = /^\s*(`{3,}|~{3,})(.*)$/.exec(lines[i]);
    if (m) {
      const run = m[1];
      const char = run[0];
      if (openLen === 0) {
        openLen = run.length;
        openChar = char;
        flags[i] = true;
        continue;
      }
      if (char === openChar && run.length >= openLen && m[2].trim() === "") {
        flags[i] = true;
        openLen = 0;
        openChar = "";
        continue;
      }
    }
    flags[i] = openLen > 0;
  }
  return flags;
}

/**
 * Paste-ready remediation. The insertion point is the same one the backfill used:
 * immediately after the cloud-mode end marker when present, else immediately after
 * the closing frontmatter `---`.
 */
function remediation(rel: string, text: string): string {
  const lines = text.split("\n");
  const cloudEnd = lines.indexOf("<!-- soleur-cloud-mode:end -->");
  let where: string;
  if (cloudEnd !== -1) {
    where = `after the \`<!-- soleur-cloud-mode:end -->\` line (line ${cloudEnd + 1})`;
  } else {
    const close = lines.indexOf("---", 1);
    where =
      close !== -1
        ? `after the closing frontmatter \`---\` (line ${close + 1})`
        : "at the top of the file";
  }
  return (
    `${rel}: insert the canonical Grok invoke block ${where}, ` +
    `with one blank line on each side:\n\n${CANONICAL}`
  );
}

describe("grok invoke block fleet", () => {
  const skills = gitLsFiles("plugins/soleur/skills/*/SKILL.md");

  test("the population is the tracked skills-root fleet, not a hand list", () => {
    expect(
      skills.length,
      `git ls-files 'plugins/soleur/skills/*/SKILL.md' returned ${skills.length} files, ` +
        `below the floor of ${MIN_SKILLS}. The pathspec has narrowed or been replaced by a ` +
        `hardcoded list — a PASS below this floor certifies a subset while reporting on the fleet.`,
    ).toBeGreaterThanOrEqual(MIN_SKILLS);
  });

  test("the canonical block matches its pinned md5", () => {
    const got = createHash("md5").update(CANONICAL as string).digest("hex");
    expect(
      got,
      `the canonical block in skills/plan/SKILL.md hashes to ${got}, not the pinned ` +
        `${CANONICAL_MD5}. If the block text is being changed deliberately, update every ` +
        `copy and this pin in ONE diff — that is what makes the fleet assertion below ` +
        `meaningful rather than self-satisfying.`,
    ).toBe(CANONICAL_MD5);
  });

  test("every skill carries exactly one canonical block, before the first heading, outside fences", () => {
    const missing: string[] = [];
    const notCanonical: string[] = [];
    const duplicated: string[] = [];
    const misplaced: string[] = [];

    for (const rel of skills) {
      const text = readFileSync(join(REPO_ROOT, rel), "utf8");
      const lines = text.split("\n");

      const starts = lines.reduce<number[]>((acc, l, i) => (l === START ? [...acc, i] : acc), []);
      const ends = lines.reduce<number[]>((acc, l, i) => (l === END ? [...acc, i] : acc), []);

      if (starts.length === 0 && ends.length === 0) {
        missing.push(remediation(rel, text));
        continue;
      }
      if (starts.length !== 1 || ends.length !== 1) {
        duplicated.push(`${rel}: ${starts.length} start marker(s), ${ends.length} end marker(s) — expected exactly one of each`);
        continue;
      }

      const block = extractBlock(text);
      if (block !== CANONICAL) notCanonical.push(rel);

      // Placement. The block must reach a Grok session that reads the top of the
      // file, so it sits before the first `# ` heading; and it must be prose, not
      // a sample, so it sits outside fenced code.
      const fenced = fencedLineFlags(lines);
      if (fenced[starts[0]]) {
        misplaced.push(`${rel}: the block is inside a fenced code block (line ${starts[0] + 1}) — it reads as a sample, not as the contract`);
        continue;
      }
      // Skip YAML frontmatter before looking for the first heading: a `#` there is
      // a YAML COMMENT, not a markdown heading. `skills/go/SKILL.md` carries an
      // eight-line comment above `user-invocable: false`, and reading its first
      // line as a heading reported a correctly-placed block as misplaced.
      const bodyStart = lines[0] === "---" ? lines.indexOf("---", 1) + 1 : 0;

      // INSIDE the frontmatter is not "before the first heading" — it is inside a
      // YAML document, where the block is not markdown and its `<!-- -->` lines
      // are a parse error. `name:`/`description:` then stop resolving, so the
      // skill is unloadable by EVERY harness. The old form computed `bodyStart`
      // only to start the heading search and never bounded the block with it, so
      // moving a block between the two `---` fences reported 6 pass / 0 fail —
      // clean, on a file no loader can read. The guard is named for loadability.
      if (bodyStart > 0 && starts[0] < bodyStart) {
        misplaced.push(
          `${rel}: the block is INSIDE the YAML frontmatter (line ${starts[0] + 1}, frontmatter ends line ${bodyStart}) — it is not markdown there, and it breaks name:/description: parsing`,
        );
        continue;
      }

      // `^#{1,6} `, not `^# `. Four skills carry no H1 at all
      // (agent-native-architecture, frontend-design, heal-skill, triage), so an
      // H1-only scan short-circuits on `firstHeading === -1` and the placement
      // clause is VACUOUS for exactly those files — measured: moving triage's
      // block to line 402 of 403 stayed green. A file whose first heading is
      // `## ` has the same hole.
      const firstHeading = lines.findIndex(
        (l, i) => i >= bodyStart && !fenced[i] && /^#{1,6} /.test(l),
      );
      if (firstHeading !== -1 && starts[0] > firstHeading) {
        misplaced.push(`${rel}: the block sits below the first heading (block line ${starts[0] + 1}, heading line ${firstHeading + 1})`);
      } else if (firstHeading === -1 && starts[0] > bodyStart + 3) {
        // No heading anywhere: the block must still sit at the top of the body,
        // or "before the first heading" degenerates to "anywhere in the file".
        misplaced.push(
          `${rel}: the file has no heading, so the block must sit at the top of the body (block line ${starts[0] + 1}, body starts line ${bodyStart + 1})`,
        );
      }
    }

    expect(
      { missing: missing.length, notCanonical, duplicated, misplaced },
      [
        missing.length ? `${missing.length} skill(s) carry no Grok invoke block:\n\n${missing.join("\n\n")}` : "",
        notCanonical.length ? `block text drifted from the canonical copy in: ${notCanonical.join(", ")}` : "",
        duplicated.length ? duplicated.join("\n") : "",
        misplaced.length ? misplaced.join("\n") : "",
      ]
        .filter(Boolean)
        .join("\n\n"),
    ).toEqual({ missing: 0, notCanonical: [], duplicated: [], misplaced: [] });
  });

  test("the scaffold GENERATES a compliant skill, round-tripped through init_skill.py", () => {
    // NOT `template.includes(CANONICAL)`. A presence check on the source file is
    // satisfied by a DEAD constant: lifting the block out of SKILL_TEMPLATE into
    // an unused `_UNUSED_GROK_BLOCK = '''…'''` left this assertion green while
    // every newly scaffolded skill landed non-compliant — the backfill treadmill
    // the message below claims to prevent. Measured 6 pass / 0 fail.
    //
    // So run the scaffold and audit its OUTPUT through the same placement rules
    // the fleet uses, which also gives those rules a synthesized fixture.
    const dir = mkdtempSync(join(tmpdir(), "grok-scaffold-"));
    const out = Bun.spawnSync(["python3", INIT_SKILL, "zz-scaffold-probe", "--path", dir], {
      stdout: "pipe",
      stderr: "pipe",
    });
    expect(out.exitCode, `init_skill.py failed: ${out.stderr.toString()}`).toBe(0);

    const generated = readFileSync(join(dir, "zz-scaffold-probe", "SKILL.md"), "utf8");
    const lines = generated.split("\n");
    const starts = lines.filter((l) => l === START).length;
    const ends = lines.filter((l) => l === END).length;
    expect({ starts, ends }, "the generated SKILL.md carries no Grok invoke block").toEqual({
      starts: 1,
      ends: 1,
    });
    expect(extractBlock(generated)).toBe(CANONICAL as string);

    // And it must satisfy the same placement rules as the fleet: outside fences,
    // inside the body, above the first heading.
    const fenced = fencedLineFlags(lines);
    const at = lines.indexOf(START);
    const bodyStart = lines[0] === "---" ? lines.indexOf("---", 1) + 1 : 0;
    const firstHeading = lines.findIndex((l, i) => i >= bodyStart && !fenced[i] && /^#{1,6} /.test(l));
    expect(fenced[at], "the generated block is inside a fence").toBe(false);
    expect(at, "the generated block is inside the frontmatter").toBeGreaterThanOrEqual(bodyStart);
    expect(at, "the generated block sits below the first heading").toBeLessThan(firstHeading);

    rmSync(dir, { recursive: true, force: true });
  });

  // Anti-vacuity for the fence detector specifically. The placement rules are NEW
  // code here — `devin-cloud-mode.test.ts` has no placement logic, no fence logic
  // and no hash, so nothing about them is inherited from that precedent and they
  // need their own driving. A four-backtick fence is the input that defeats a naive
  // `startsWith("```")` scanner.
  test("the fence detector is run-length aware", () => {
    const naiveDefeating = ["````", START, END, "````", "# Title"];
    expect(fencedLineFlags(naiveDefeating)[1]).toBe(true);

    const threeBacktick = ["```", START, "```", "# Title"];
    expect(fencedLineFlags(threeBacktick)[1]).toBe(true);

    const unfenced = ["---", "name: x", "---", START, END, "# Title"];
    expect(fencedLineFlags(unfenced)[3]).toBe(false);

    // A tilde fence does not close a backtick fence.
    const mixed = ["```", START, "~~~", END, "```"];
    expect(fencedLineFlags(mixed)[1]).toBe(true);
    expect(fencedLineFlags(mixed)[3]).toBe(true);
  });

  // Must-PASS non-canonical input: the block directly after the frontmatter with NO
  // cloud-mode block. Both placements are permitted, so a suite that only ever saw
  // the cloud-mode-preceded shape would reject a legitimate new skill.
  test("a block placed directly after the frontmatter passes", () => {
    const synthesized = ["---", "name: zz-synth", "description: x", "---", "", START, END, "", "# Synth"];
    const fenced = fencedLineFlags(synthesized);
    const s = synthesized.indexOf(START);
    const firstHeading = synthesized.findIndex((l, i) => !fenced[i] && /^# /.test(l));
    expect(fenced[s]).toBe(false);
    expect(s).toBeLessThan(firstHeading);
  });
});
