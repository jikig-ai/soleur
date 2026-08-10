/**
 * Contract test for the plan skeleton checkpoint (#7418, ADR-174).
 *
 * `soleur:plan` writes a skeleton plan file BEFORE the Phase 1 research fan-out and
 * carries a machine-owned cursor key, `pipeline_resume:`, that `soleur:one-shot` reads to
 * decide resume-vs-advance. This test pins the three properties that can silently drift:
 *
 *   A. Phase 0.7 stays positioned between Phase 0.6 and Phase 1 (write-before-research).
 *   B. The cursor's phase vocabulary stays owned by `plan` — `one-shot` reads presence plus
 *      the single token `deepening`, and never learns plan's internal phase names.
 *   C. Every prescribed read of the cursor is FRONTMATTER-BOUNDED.
 *
 * (C) is a regression test, not a hypothetical. v1 of the #7418 plan prescribed the repo's
 * line-anchored `gsub` awk reader; run against the plan document itself it returned a cursor
 * value harvested from a fenced YAML example in the BODY while the frontmatter carried no
 * such key. Any document that *documents* the key contains the key. The fixture reproduces
 * that exact shape, and the bounded/unbounded pair below is the positive control: the
 * unbounded assertion proves the fixture is a real trap, so the bounded assertion cannot
 * pass vacuously.
 */
import { describe, test, expect } from "bun:test";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SKILLS = resolve(REPO_ROOT, "plugins/soleur/skills");

const PLAN_SKILL = resolve(SKILLS, "plan/SKILL.md");
const ONE_SHOT_SKILL = resolve(SKILLS, "one-shot/SKILL.md");
const DEEPEN_PLAN_SKILL = resolve(SKILLS, "deepen-plan/SKILL.md");
const FIXTURE = resolve(import.meta.dir, "fixtures/plan-cursor-body-collision.md");
/** Positive control: the cursor really is in the frontmatter. */
const FIXTURE_WITH_CURSOR = resolve(import.meta.dir, "fixtures/plan-cursor-frontmatter-set.md");
/** No leading `---` at all, but a fenced example containing one (#4724). */
const FIXTURE_NO_FRONTMATTER = resolve(import.meta.dir, "fixtures/plan-cursor-no-frontmatter.md");

const read = (p: string) => readFileSync(p, "utf8");

/**
 * Assert containment WITHOUT letting the haystack reach the failure message. `toContain`
 * on a 50 KB SKILL.md prints the entire file, which blows the response budget and buries
 * the actual failure (AGENTS.md `hr-never-run-commands-with-unbounded-output` applied to
 * the harness's own output). The test name carries the context instead.
 */
function has(haystack: string, needle: string | RegExp): boolean {
  return typeof needle === "string" ? haystack.includes(needle) : needle.test(haystack);
}

/** The cursor key. Presence is the boolean: present => unfinished, absent => finished. */
const CURSOR_KEY = "pipeline_resume:";

/**
 * `plan`'s internal phase vocabulary. `one-shot` must never name these — it reads presence
 * plus `deepening` (which skill to re-invoke) and nothing else. Anchored on the BACKTICKED
 * form: `research` and `gates` are ordinary English words that appear in all three files as
 * prose, so a bare-token grep would be a false positive generator
 * (AGENTS.md `cq-assert-anchor-not-bare-token`).
 */
const PLAN_OWNED_TOKENS = ["research", "drafting", "gates", "finalize"] as const;

/** The one cursor token `one-shot` and `deepen-plan` are allowed to name. */
const SHARED_TOKEN = "deepening";

/**
 * The canonical frontmatter-bounded reader, adopted verbatim from
 * `.github/workflows/review-reminder.yml` (the in-repo precedent) rather than invented —
 * see `plan/SKILL.md` Sharp Edges on adopting a parsing precedent verbatim.
 *
 * The `head -n 1` guard is load-bearing and part of the precedent: the sed range
 * `/^---$/,/^---$/` matches the FIRST `---` anywhere in the file, so a document with no
 * leading frontmatter but an embedded ```yaml block would have that block mis-parsed as
 * metadata (#4724).
 */
const BOUNDED_READ_IDIOM = "sed -n '/^---$/,/^---$/{";
const LEADING_FRONTMATTER_GUARD = 'head -n 1';

function boundedRead(file: string, key: string): string {
  const script = `
    [[ "$(head -n 1 "$1")" == "---" ]] || exit 0
    sed -n '/^---$/,/^---$/{ /^${key}:/{ s/.*: *//; p; q; } }' "$1"
  `;
  return execFileSync("bash", ["-c", script, "bash", file], { encoding: "utf8" }).trim();
}

/** The BROKEN reader v1 shipped — line-anchored, unbounded. Used only as a positive control. */
function unboundedRead(file: string, key: string): string {
  const script = `awk '/^${key}:/ { gsub(/^${key}:[[:space:]]*"?|"?$/, ""); print; exit }' "$1"`;
  return execFileSync("bash", ["-c", script, "bash", file], { encoding: "utf8" }).trim();
}

describe("plan skeleton checkpoint — Phase 0.7 position", () => {
  const src = read(PLAN_SKILL);
  const lines = src.split("\n");
  const lineOf = (re: RegExp) => lines.findIndex((l) => re.test(l));

  test("all three anchors exist in plan/SKILL.md", () => {
    expect(lineOf(/^### 0\.6\./)).toBeGreaterThan(-1);
    expect(lineOf(/^### 0\.7\./)).toBeGreaterThan(-1);
    expect(lineOf(/^### 1\. Local Research/)).toBeGreaterThan(-1);
  });

  test("Phase 0.7 sits AFTER 0.6 and BEFORE the Phase 1 research fan-out", () => {
    const i06 = lineOf(/^### 0\.6\./);
    const i07 = lineOf(/^### 0\.7\./);
    const i1 = lineOf(/^### 1\. Local Research/);
    // The whole point of the change: the skeleton is written before anything expensive.
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

  test("Phase 1.7 persists research to the plan file", () => {
    // Without this the checkpoint buys a filename and nothing else for a stall INSIDE the
    // fan-out — which is the modal case and the shape of the incident that motivated #7418.
    const i17 = lineOf(/^### 1\.7\. Consolidate Research/);
    const iInsights = lines.findIndex(
      (l, n) => n > i17 && /## Research Insights/.test(l),
    );
    expect(i17).toBeGreaterThan(-1);
    expect(iInsights).toBeGreaterThan(i17);
  });
});

describe("plan skeleton checkpoint — cursor vocabulary ownership", () => {
  const plan = read(PLAN_SKILL);
  const oneShot = read(ONE_SHOT_SKILL);
  const deepen = read(DEEPEN_PLAN_SKILL);

  test("all three skills name the cursor key", () => {
    expect(has(plan, CURSOR_KEY)).toBe(true);
    expect(has(oneShot, CURSOR_KEY)).toBe(true);
    expect(has(deepen, CURSOR_KEY)).toBe(true);
  });

  test("plan/SKILL.md owns the full phase vocabulary", () => {
    for (const token of PLAN_OWNED_TOKENS) {
      expect(has(plan, new RegExp("`" + token + "`"))).toBe(true);
    }
  });

  test("one-shot never learns plan's internal phase names", () => {
    for (const token of PLAN_OWNED_TOKENS) {
      expect(has(oneShot, new RegExp("`" + token + "`"))).toBe(false);
    }
    // It may name exactly one token: which skill to re-invoke.
    expect(has(oneShot, new RegExp("`" + SHARED_TOKEN + "`"))).toBe(true);
  });

  test("deepen-plan names only its own token", () => {
    for (const token of PLAN_OWNED_TOKENS) {
      expect(has(deepen, new RegExp("`" + token + "`"))).toBe(false);
    }
    expect(has(deepen, new RegExp("`" + SHARED_TOKEN + "`"))).toBe(true);
  });

  test("one-shot's completeness test is conjunctive, not a bare presence check", () => {
    // "cursor absent => complete" is a negative assertion; absence has causes other than
    // completion. The existing positive section assertion must survive as a conjunct.
    expect(has(oneShot, "frontmatter + Overview + Acceptance Criteria")).toBe(true);
    expect(has(oneShot, "Undetermined")).toBe(true);
  });

  test("resume is bounded", () => {
    expect(has(plan, "resume_attempts")).toBe(true);
    // A designed deepen-plan HALT is a terminal correct outcome, not a crash to replay.
    expect(has(deepen, "resume_attempts")).toBe(true);
  });
});

describe("plan skeleton checkpoint — frontmatter-bounded parsing (regression)", () => {
  for (const [name, path] of [
    ["plan", PLAN_SKILL],
    ["one-shot", ONE_SHOT_SKILL],
    ["deepen-plan", DEEPEN_PLAN_SKILL],
  ] as const) {
    test(`${name}/SKILL.md prescribes the bounded reader, with the leading-frontmatter guard`, () => {
      const src = read(path);
      expect(has(src, BOUNDED_READ_IDIOM)).toBe(true);
      expect(has(src, LEADING_FRONTMATTER_GUARD)).toBe(true);
      // The line-anchored gsub form is correct for a key that cannot appear in a body.
      // The cursor key is not such a key, so prescribing that form for it is the bug.
      expect(has(src, /awk '\/\^pipeline_resume:/)).toBe(false);
    });
  }

  test("POSITIVE CONTROL — the fixture really does trap an unbounded reader", () => {
    // If this ever returns empty the fixture has been defanged and the assertion below
    // would pass for the wrong reason.
    expect(unboundedRead(FIXTURE, "pipeline_resume")).toBe("research");
    expect(unboundedRead(FIXTURE, "branch")).toBe("fixture-frontmatter-branch");
  });

  test("the bounded reader ignores a column-0 body occurrence of the cursor key", () => {
    // The fixture's frontmatter has NO pipeline_resume; its body has one at column 0.
    expect(boundedRead(FIXTURE, "pipeline_resume")).toBe("");
  });

  test("the bounded reader takes branch: from the frontmatter, never the body", () => {
    expect(boundedRead(FIXTURE, "branch")).toBe("fixture-frontmatter-branch");
  });

  test("the bounded reader returns empty on a file with no leading frontmatter", () => {
    // one-shot/SKILL.md opens with prose, not `---`. Without the head -n 1 guard the sed
    // range would latch onto the first `---` anywhere in the document (#4724).
    expect(boundedRead(ONE_SHOT_SKILL, "pipeline_resume")).toBe("");
  });
});

/**
 * Grepping for the reader's SHAPE is not enough, and this suite exists because that gap shipped:
 * the first version of these skills prescribed
 *
 *     [[ -f "$PLAN" && "$(head -n 1 "$PLAN")" == "---" ]] || CURSOR=""
 *     CURSOR=$(sed -n ... "$PLAN")
 *
 * where the guard assigns `CURSOR=""` and the very next line unconditionally overwrites it. The
 * guard could never change the outcome, so #4724 was reintroduced verbatim — and every
 * shape-matching assertion above passed, because both `head -n 1` and the sed range were present.
 *
 * So EXECUTE the snippet the skills actually prescribe, against inputs whose correct answers
 * differ. A drift guard has to mirror what the prescribed code does, not what it looks like.
 */
describe("plan skeleton checkpoint — the PRESCRIBED reader is executed, not just matched", () => {
  /** Pull the fenced bash block that reads the cursor out of a SKILL.md. */
  function extractReaderSnippet(skillPath: string): string {
    const blocks = read(skillPath).match(/```bash\n([\s\S]*?)```/g) ?? [];
    const block = blocks.find(
      (b) => b.includes("pipeline_resume:") && b.includes("sed -n"),
    );
    if (!block) throw new Error(`no cursor-reader bash block found in ${skillPath}`);
    return block
      .replace(/^```bash\n/, "")
      .replace(/```$/, "")
      // The skills open the block with a placeholder assignment for the operator to fill in.
      .replace(/^\s*PLAN=.*$/m, "");
  }

  /** Run the extracted snippet against a plan file and report what it read. */
  function runPrescribedReader(skillPath: string, planFile: string): string {
    const script = `set -uo pipefail\nPLAN="$1"\n${extractReaderSnippet(skillPath)}\nprintf '%s' "\${CURSOR-}"`;
    return execFileSync("bash", ["-c", script, "bash", planFile], { encoding: "utf8" }).trim();
  }

  for (const [name, path] of [
    ["plan", PLAN_SKILL],
    ["one-shot", ONE_SHOT_SKILL],
    ["deepen-plan", DEEPEN_PLAN_SKILL],
  ] as const) {
    describe(`${name}/SKILL.md`, () => {
      test("reads a real frontmatter cursor (positive control — the reader works at all)", () => {
        // Without this, every assertion below could pass against a reader that always returns "".
        expect(runPrescribedReader(path, FIXTURE_WITH_CURSOR)).toBe("gates");
      });

      test("ignores a column-0 cursor in the BODY of a document that has frontmatter", () => {
        expect(runPrescribedReader(path, FIXTURE)).toBe("");
      });

      test("ignores an embedded fenced cursor when the file has NO leading frontmatter (#4724)", () => {
        // This is the case the inert guard broke: the sed range latches onto the first `---`
        // anywhere in the file, so a doc with no frontmatter mis-parses its own example.
        expect(runPrescribedReader(path, FIXTURE_NO_FRONTMATTER)).toBe("");
      });
    });
  }
});
