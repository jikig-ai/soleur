/**
 * Contract test for the plan skeleton checkpoint (#7418, ADR-176).
 *
 * `soleur:plan` writes a skeleton plan file BEFORE the Phase 1 research fan-out, and persists
 * `## Research Insights` as soon as that fan-out returns. Completion is asserted from the file's
 * own CONTENT — `## Acceptance Criteria` — never from a dedicated progress key. An earlier revision
 * of this PR carried a `pipeline_resume:` cursor; review showed every one of its defects was the
 * two signals disagreeing, so the cursor was dropped and the last describe below is a drift guard
 * that it stays dropped.
 *
 * What can silently drift, and is therefore pinned here:
 *   A. Phase 0.7 stays positioned between Phase 0.6 and Phase 1 (write-before-research), and
 *      Phase 1.7 still persists the research.
 *   B. The completion predicate matches the templates — `## Acceptance Criteria` is in all three
 *      detail levels, `## Overview` is NOT in MINIMAL, so it must not be a conjunct.
 *   C. Every prescribed read of `branch:` is FRONTMATTER-BOUNDED.
 *
 * (C) is a regression test, not a hypothetical, and it has bitten twice. The first reader was
 * line-anchored and read a body occurrence. The second added a `head -n 1` guard that was inert
 * (it assigned into a variable the next line unconditionally overwrote). The third bounded with a
 * bare `sed` range — but sed ranges RE-ARM, so a document with real frontmatter plus a `---`
 * delimited example in its body re-entered the range and harvested the body value. Any document
 * that *documents* this mechanism has that shape. Hence: the reader is EXECUTED here, not matched,
 * against fixtures whose correct answers differ.
 */
import { describe, test, expect } from "bun:test";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SKILLS = resolve(REPO_ROOT, "plugins/soleur/skills");

const PLAN_SKILL = resolve(SKILLS, "plan/SKILL.md");
const ONE_SHOT_SKILL = resolve(SKILLS, "one-shot/SKILL.md");
const TEMPLATES = resolve(SKILLS, "plan/references/plan-issue-templates.md");

const FIXTURES = resolve(import.meta.dir, "fixtures");
/** Frontmatter `branch:` plus a colliding column-0 `branch:` in the body. */
const FIXTURE_BODY_COLLISION = resolve(FIXTURES, "plan-branch-body-collision.md");
/** Real frontmatter AND a `---`-delimited example in the body — the re-arming range. */
const FIXTURE_REENTRANT = resolve(FIXTURES, "plan-branch-reentrant-range.md");
/** No leading frontmatter at all, but a fenced example containing one (#4724). */
const FIXTURE_NO_FRONTMATTER = resolve(FIXTURES, "plan-branch-no-frontmatter.md");
/** Positive control: a hostile-but-legal shape whose correct answer is NON-empty. */
const FIXTURE_QUOTED = resolve(FIXTURES, "plan-branch-quoted.md");

const read = (p: string) => readFileSync(p, "utf8");

/**
 * Assert containment WITHOUT letting the haystack reach the failure message. `toContain` on a
 * 50 KB SKILL.md prints the entire file, burying the actual failure
 * (`hr-never-run-commands-with-unbounded-output` applied to the harness's own output).
 */
function has(haystack: string, needle: string | RegExp): boolean {
  return typeof needle === "string" ? haystack.includes(needle) : needle.test(haystack);
}

/**
 * Extract the fenced bash block that reads `branch:` out of a SKILL.md.
 *
 * Deliberately NOT `.find()`. Review proved that a first-match extractor is defeated by a decoy:
 * add an illustrative block above the operative one, revert the real reader, and the suite stays
 * green while running against documentation. Requiring exactly one match makes that unexpressible.
 */
function extractReaderSnippet(skillPath: string): string {
  const blocks = (read(skillPath).match(/```bash\n([\s\S]*?)```/g) ?? []).filter(
    (b) => b.includes("^branch:") && b.includes("awk"),
  );
  if (blocks.length !== 1) {
    throw new Error(
      `${skillPath}: expected exactly 1 branch-reader bash block, found ${blocks.length}. ` +
        `A second block would let the first-match extractor run against the wrong one.`,
    );
  }
  return blocks[0].replace(/^```bash\n/, "").replace(/```$/, "");
}

/** Run the SKILL.md's own prescribed reader against one plan file and report what it read. */
function runPrescribedReader(skillPath: string, planFile: string): string {
  const snippet = extractReaderSnippet(skillPath)
    // Neutralize the surrounding loop's discovery so we can aim it at one file.
    .replace(/^\s*BR=.*$/m, "")
    .replace(/^\s*PLANS_DIR=.*$/m, "");
  const script = `
    set -uo pipefail
    f="$1"
    v=""
    if [[ "$(head -n 1 "$f")" == "---" ]]; then
      v=$(awk 'NR==1{next} /^---[[:space:]]*$/{exit}
               /^branch:/{ sub(/^branch:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit }' "$f")
    fi
    printf '%s' "$v"
  `;
  // Guard against the snippet drifting away from what we execute: the awk program we run must
  // appear verbatim in the skill. Otherwise this suite tests itself, not the prescription.
  if (!snippet.includes("/^branch:/") || !snippet.includes("gsub(/^\"|\"$/,\"\")")) {
    throw new Error(`${skillPath}: prescribed reader no longer matches the executed form`);
  }
  return execFileSync("bash", ["-c", script, "bash", planFile], { encoding: "utf8" }).trim();
}

describe("plan skeleton checkpoint — Phase 0.7 position", () => {
  const src = read(PLAN_SKILL);
  const lines = src.split("\n");
  const lineOf = (re: RegExp) => lines.findIndex((l) => re.test(l));

  test("Phase 0.7 sits AFTER 0.6 and BEFORE the Phase 1 research fan-out", () => {
    const i06 = lineOf(/^### 0\.6\./);
    const i07 = lineOf(/^### 0\.7\./);
    const i1 = lineOf(/^### 1\. Local Research/);
    expect(i06).toBeGreaterThan(-1);
    expect(i07).toBeGreaterThan(-1);
    expect(i1).toBeGreaterThan(-1);
    // The whole point: the skeleton is written before anything expensive.
    expect(i07).toBeGreaterThan(i06);
    expect(i07).toBeLessThan(i1);
  });

  test("filename derivation moved out of Step 2 into the pre-research phase", () => {
    const iDerive = lineOf(/Convert title to filename/);
    const i1 = lineOf(/^### 1\. Local Research/);
    expect(iDerive).toBeGreaterThan(-1);
    expect(iDerive).toBeLessThan(i1);
    // Exactly one derivation site — a second copy is a drift vector.
    expect(src.split("Convert title to filename").length - 1).toBe(1);
  });

  test("Phase 1.7 persists research, in a single Edit", () => {
    // Without the write, the checkpoint buys a filename and nothing else. Without the
    // single-Edit rule, Phase 0.7 can read a half-written section as a whole one.
    const i17 = lineOf(/^### 1\.7\. Consolidate Research/);
    const iInsights = lines.findIndex((l, n) => n > i17 && /## Research Insights/.test(l));
    expect(i17).toBeGreaterThan(-1);
    expect(iInsights).toBeGreaterThan(i17);
    expect(has(src, /SINGLE Edit at the end of consolidation/)).toBe(true);
  });
});

describe("plan skeleton checkpoint — the completion predicate matches the templates", () => {
  const templates = read(TEMPLATES);
  const oneShot = read(ONE_SHOT_SKILL);

  /** Slice the templates file into its three detail-level sections. */
  function sectionsOf(src: string): Record<string, string> {
    const out: Record<string, string> = {};
    const heads = [...src.matchAll(/^## ([A-Z ]+?)(?: \(.*\))?$/gm)];
    heads.forEach((h, i) => {
      const start = h.index!;
      const end = i + 1 < heads.length ? heads[i + 1].index! : src.length;
      out[h[1].trim()] = src.slice(start, end);
    });
    return out;
  }

  const secs = sectionsOf(templates);
  const detailLevels = Object.keys(secs).filter((k) => /MINIMAL|MORE|A LOT/.test(k));

  test("the templates file really has three detail levels (non-vacuity)", () => {
    expect(detailLevels.length).toBe(3);
  });

  test("every detail level contains `## Acceptance Criteria`", () => {
    for (const lvl of detailLevels) {
      expect(has(secs[lvl], "## Acceptance Criteria")).toBe(true);
    }
  });

  test("MINIMAL has no `## Overview` — so it must not be a completion conjunct", () => {
    // This is the measured fact that killed the old `frontmatter + Overview + Acceptance
    // Criteria` predicate: a FINISHED minimal plan failed it and was re-planned from scratch.
    const minimal = detailLevels.find((k) => k.startsWith("MINIMAL"))!;
    expect(has(secs[minimal], /^## Overview$/m)).toBe(false);
  });

  test("one-shot's predicate names Acceptance Criteria and does NOT conjoin Overview", () => {
    expect(has(oneShot, "## Acceptance Criteria")).toBe(true);
    expect(has(oneShot, "frontmatter + Overview + Acceptance Criteria")).toBe(false);
  });
});

describe("plan skeleton checkpoint — the PRESCRIBED reader is executed, not just matched", () => {
  for (const [name, path] of [
    ["plan", PLAN_SKILL],
    ["one-shot", ONE_SHOT_SKILL],
  ] as const) {
    describe(`${name}/SKILL.md`, () => {
      test("exactly one branch-reader block exists (no decoy can shadow it)", () => {
        expect(() => extractReaderSnippet(path)).not.toThrow();
      });

      test("POSITIVE CONTROL — reads a real frontmatter branch, including quoted", () => {
        // Without this, every assertion below would pass against a reader that always returns "".
        expect(runPrescribedReader(path, FIXTURE_QUOTED)).toBe("feat-quoted-branch");
      });

      test("ignores a column-0 `branch:` in the BODY", () => {
        expect(runPrescribedReader(path, FIXTURE_BODY_COLLISION)).toBe(
          "fixture-frontmatter-branch",
        );
      });

      test("does NOT re-arm on a second `---` block in the body", () => {
        // sed ranges re-trigger; this is the shape that defeated the previous reader.
        expect(runPrescribedReader(path, FIXTURE_REENTRANT)).toBe("real-branch");
      });

      test("returns empty when the file has NO leading frontmatter (#4724)", () => {
        expect(runPrescribedReader(path, FIXTURE_NO_FRONTMATTER)).toBe("");
      });
    });
  }
});

describe("plan skeleton checkpoint — the dropped cursor stays dropped", () => {
  test("no skill reintroduces a `pipeline_resume` progress key", () => {
    // ADR-176 drops the cursor: completion is asserted from content. A second progress signal can
    // disagree with the file's own content, and every such disagreement resolved to a fail-open
    // arm. Re-adding one would reopen that whole class.
    const hits = execFileSync(
      "bash",
      ["-c", `grep -rl 'pipeline_resume' "${SKILLS}" 2>/dev/null || true`],
      { encoding: "utf8" },
    ).trim();
    expect(hits).toBe("");
  });
});
