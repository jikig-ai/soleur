// `## Scope Check` contract/parity guard (#9398, origin incident PR #9339).
//
// The `## Scope Check` plan section — `### Ask Mapping`, `### Plan-Item
// Provenance`, `### Split Assessment` — is emitted by soleur:plan (Phase 2.4)
// and halted on by soleur:deepen-plan (§4.12). Its schema lives on five
// surfaces with no compile-time or commit-time guard:
//
//   1 (canonical spec) plugins/soleur/skills/plan/references/plan-scope-check.md
//   2                plugins/soleur/skills/plan/SKILL.md           — §2.4 pointer
//   3                plugins/soleur/skills/plan/references/plan-issue-templates.md
//                                                               — 3 blocks (one per tier)
//   4                plugins/soleur/skills/deepen-plan/SKILL.md   — §4.12 halt
//   5                plugins/soleur/skills/plan-review/SKILL.md   — consumer feed
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
// NOT end the block.
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

// True when `text` carries the full emit contract: the section heading plus
// every required subsection, each at line start.
function carriesContract(text: string): boolean {
  return (
    text.split(/\r?\n/).includes(SECTION) &&
    SUBSECTIONS.every((s) => text.split(/\r?\n/).some((l) => l === s || l.startsWith(s + " ")))
  );
}

describe("## Scope Check emit contract — surface parity", () => {
  test("canonical spec exists and carries the full contract + operational rules", () => {
    const src = read(REFERENCE);
    expect(
      carriesContract(src),
      `${REFERENCE} must carry ${SECTION} + ${SUBSECTIONS.join(", ")}`,
    ).toBe(true);
    // The contract's operational anchors — the halt reads these tokens.
    for (const token of ["Recommendation:", "unmapped", "inferred", "verbatim"]) {
      expect(src, `${REFERENCE} must define ${token}`).toContain(token);
    }
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

  test("plan-issue-templates.md carries exactly 3 `## Scope Check` blocks, each with all subsections", () => {
    const blocks = scopeCheckBlocks(read(TEMPLATES));
    expect(
      blocks.length,
      `${TEMPLATES} must carry exactly 3 ${SECTION} blocks (MINIMAL/MORE/A LOT)`,
    ).toBe(3);
    blocks.forEach((block, i) => {
      for (const sub of SUBSECTIONS) {
        expect(
          block.split(/\r?\n/).some((l) => l === sub || l.startsWith(sub + " ")),
          `template block #${i + 1} must contain ${sub}`,
        ).toBe(true);
      }
    });
  });

  test("deepen-plan/SKILL.md §4.12 halt exists and carries the mechanical verify", () => {
    const src = read(DEEPEN);
    expect(src, `${DEEPEN} must carry the §4.12 Scope Check halt`).toMatch(
      /^### 4\.12\. Scope Check Halt/m,
    );
    // The halt is enforcement, not prose: it must carry the locate-grep on the
    // section heading AND halt semantics — a heading alone is a vacuous gate.
    expect(src, "§4.12 must locate the section via `^## Scope Check`").toContain(
      "^## Scope Check",
    );
    expect(src, "§4.12 must HALT on a non-compliant plan").toMatch(/HALT/);
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

  test("parity: deepen-plan §4.12 names the same subsections the emit contract requires", () => {
    // The halt's mechanical-verify list must enumerate every required
    // subsection — a subsection the halt never checks can drift silently.
    const src = read(DEEPEN);
    const haltIdx = src.indexOf("### 4.12. Scope Check Halt");
    expect(haltIdx, "§4.12 heading must exist").toBeGreaterThan(-1);
    const haltBody = src.slice(haltIdx);
    for (const sub of SUBSECTIONS) {
      expect(haltBody, `§4.12 must verify ${sub}`).toContain(sub);
    }
  });
});
