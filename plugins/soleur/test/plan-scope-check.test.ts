// `## Scope Check` contract/parity guard (#9398, origin incident PR #9339).
//
// The `## Scope Check` plan section — `### Ask Mapping`, `### Plan-Item
// Provenance`, `### Split Assessment` — is emitted by soleur:plan (Phase 2.4)
// and halted on by soleur:deepen-plan (§4.12). Its schema lives on six
// surfaces with no compile-time or commit-time guard:
//
//   1 (canonical spec) plugins/soleur/skills/plan/references/plan-scope-check.md
//   2                plugins/soleur/skills/plan/SKILL.md           — §2.4 pointer
//   3                plugins/soleur/skills/plan/references/plan-issue-templates.md
//                                                               — 3 blocks (one per tier)
//   4                plugins/soleur/skills/deepen-plan/SKILL.md   — §4.12 halt
//   5                plugins/soleur/skills/plan-review/SKILL.md   — consumer feed
//   6                plugins/soleur/skills/plan-review/workflows/plan-review.workflow.js
//                                                               — consumer lens string
//
// A rename, deletion, or per-surface subset silently desyncs the emit contract
// from its enforcement halt — exactly the drift class
// observability-schema-parity.test.ts guards for `## Observability` (#4133).
// The mutation matrix for this guard lives in the Guard Contract of
// knowledge-base/project/plans/2026-10-01-chore-plan-time-scope-check-plan.md.

import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const read = (p: string) => readFileSync(resolve(REPO_ROOT, p), "utf8");

const REFERENCE = "plugins/soleur/skills/plan/references/plan-scope-check.md";
const PLAN_SKILL = "plugins/soleur/skills/plan/SKILL.md";
const TEMPLATES = "plugins/soleur/skills/plan/references/plan-issue-templates.md";
const DEEPEN = "plugins/soleur/skills/deepen-plan/SKILL.md";
const PLAN_REVIEW = "plugins/soleur/skills/plan-review/SKILL.md";
const PLAN_REVIEW_WORKFLOW =
  "plugins/soleur/skills/plan-review/workflows/plan-review.workflow.js";

// The emit contract: the section heading plus its three required subsections.
// Section-anchored tokens (`^##` / `^###`), never bare substrings — a prose
// mention of "scope check" must not satisfy the contract.
const SECTION = "## Scope Check";
const SUBSECTIONS = [
  "### Ask Mapping",
  "### Plan-Item Provenance",
  "### Split Assessment",
] as const;

// Extract the body of every `^## Scope Check` block — from the heading line to
// the next column-0 `##`-prefixed heading (or EOF). A `###` subsection does
// NOT end the block. Deliberately fence-blind: the canonical schema copy and
// all three template copies live inside ```markdown fences by design.
function scopeCheckBlocks(text: string): string[] {
  const lines = text.split(/\r?\n/);
  const blocks: string[] = [];
  let cur: string[] | null = null;
  for (const line of lines) {
    if (line === SECTION) {
      if (cur) blocks.push(cur.join("\n"));
      cur = [];
      continue;
    }
    if (cur && /^## /.test(line)) {
      blocks.push(cur.join("\n"));
      cur = null;
      continue;
    }
    if (cur) cur.push(line);
  }
  if (cur) blocks.push(cur.join("\n"));
  return blocks;
}

// The subsection heading set inside a block (canonical shape): `^###` lines.
function subsectionsOf(block: string): string[] {
  return block
    .split(/\r?\n/)
    .filter((l) => /^### \S/.test(l));
}

// The §4.12 halt body — from its heading to the next `##`/`###`-level heading.
// Assertions on the halt must be scoped to this slice: `HALT`, subsection
// names, and `^## Scope Check` all occur elsewhere in the file, so a
// whole-file match is vacuous.
function haltBody(src: string): string {
  const idx = src.indexOf("### 4.12. Scope Check Halt");
  if (idx === -1) return "";
  const rest = src.slice(idx);
  const nl = rest.indexOf("\n");
  if (nl === -1) return rest;
  const next = rest.slice(nl + 1).search(/^#{2,3} /m);
  return next === -1 ? rest : rest.slice(0, nl + 1 + next);
}

// True when `text` carries the full emit contract: the section heading plus
// every required subsection, each at line start.
function carriesContract(text: string): boolean {
  const lines = text.split(/\r?\n/);
  return (
    lines.includes(SECTION) &&
    SUBSECTIONS.every((s) => lines.some((l) => l === s || l.startsWith(s + " ")))
  );
}

describe("## Scope Check emit contract — surface parity", () => {
  test("canonical spec exists and carries the full contract + operational rules", () => {
    const src = read(REFERENCE);
    expect(
      carriesContract(src),
      `${REFERENCE} must carry ${SECTION} + ${SUBSECTIONS.join(", ")}`,
    ).toBe(true);
    // The contract's operational anchors — the halt reads these tokens, and
    // the fenced-vs-unfenced split is load-bearing (schema examples live
    // inside ```markdown fences and must not count as the section).
    for (const token of [
      "Recommendation:",
      "unmapped",
      "inferred",
      "verbatim",
      "unfenced",
      "status: BLOCKED",
    ]) {
      expect(src, `${REFERENCE} must define ${token}`).toContain(token);
    }
  });

  test("canonical schema derives the expected subsection set", () => {
    // The reference's fenced schema block is the canonical shape; every other
    // surface is compared against it below. This test is the sanity anchor on
    // the derivation itself.
    const canonical = scopeCheckBlocks(read(REFERENCE))[0];
    expect(canonical, `${REFERENCE} must carry a schema block`).toBeTruthy();
    expect(subsectionsOf(canonical)).toEqual([...SUBSECTIONS]);
  });

  test("plan/SKILL.md §2.4 pointer exists and names the canonical file", () => {
    const src = read(PLAN_SKILL);
    // The pointer is what makes the canonical spec reachable from the skill;
    // deleting it orphans the spec while every surface still greps green.
    expect(src, `${PLAN_SKILL} must carry the §2.4 Scope Check gate heading`).toMatch(
      /^### 2\.4\. Scope Check/m,
    );
    expect(src, `${PLAN_SKILL} §2.4 must reference ${REFERENCE}`).toContain(
      "references/plan-scope-check.md",
    );
  });

  test("plan-issue-templates.md carries exactly 3 `## Scope Check` blocks matching canonical", () => {
    const canonical = subsectionsOf(scopeCheckBlocks(read(REFERENCE))[0]);
    const blocks = scopeCheckBlocks(read(TEMPLATES));
    expect(
      blocks.length,
      `${TEMPLATES} must carry exactly 3 ${SECTION} blocks (MINIMAL/MORE/A LOT)`,
    ).toBe(3);
    blocks.forEach((block, i) => {
      // Set-equal against canonical — a fourth subsection added only to the
      // canonical spec is a superset drift this must catch.
      expect(
        subsectionsOf(block),
        `template block #${i + 1} must carry exactly the canonical subsections`,
      ).toEqual(canonical);
      // The body contract the halt enforces, not just the headings.
      expect(
        block,
        `template block #${i + 1} must carry a Recommendation: line`,
      ).toContain("Recommendation:");
    });
  });

  test("deepen-plan/SKILL.md §4.12 halt exists and carries the mechanical verify", () => {
    const src = read(DEEPEN);
    expect(src, `${DEEPEN} must carry the §4.12 Scope Check halt`).toMatch(
      /^### 4\.12\. Scope Check Halt/m,
    );
    const body = haltBody(src);
    expect(body, "§4.12 body must be present").not.toBe("");
    // Every condition the halt enforces must be asserted on the §4.12 slice —
    // whole-file matches stay green even with the reject list gutted.
    for (const token of [
      "^## Scope Check$", // locate anchor (line-exact)
      "unfenced", // fenced schema examples are not the section
      "unmapped",
      "descoped",
      "inferred",
      "Recommendation:",
      "status: BLOCKED",
      "HALT",
    ]) {
      expect(body, "§4.12 must enforce via " + token).toContain(token);
    }
    // The halt must name every canonical subsection it verifies.
    for (const sub of SUBSECTIONS) {
      expect(body, "§4.12 must verify " + sub).toContain(sub);
    }
  });

  test("plan-review/SKILL.md feeds the section to code-simplicity-reviewer", () => {
    const src = read(PLAN_REVIEW);
    // Phrase-anchored: a passing mention is not a feed instruction — the
    // code-simplicity feed sentence itself must name the artifact.
    expect(
      src,
      `${PLAN_REVIEW} must instruct feeding ${SECTION} to code-simplicity-reviewer`,
    ).toContain("feed it the `## Scope Check`");
  });

  test("plan-review.workflow.js lens names the same contract", () => {
    // Sixth surface: the workflow port's code-simplicity lens restates the
    // contract inside a JS string — it cannot satisfy carriesContract but a
    // subsection rename would leave it stale-and-green without this pin.
    const src = read(PLAN_REVIEW_WORKFLOW);
    for (const token of ["## Scope Check", "Ask Mapping", "Plan-Item Provenance"]) {
      expect(src, `${PLAN_REVIEW_WORKFLOW} lens must name ${token}`).toContain(token);
    }
  });
});
