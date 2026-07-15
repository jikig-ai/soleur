// Undeferred Operator-Step Gate (#4117) — verifies plugins/soleur/skills/ship/SKILL.md
// Phase 5.5 contains the canonical gate definition that enforces hard rule
// `hr-never-label-any-step-as-manual-without` at the `gh pr ready` boundary.
//
// The gate is documentation that an LLM agent reads at /ship time; the only
// safety net against drift between the gate's bash regex and the AGENTS.core.md
// rule cross-reference is this test file.
//
// Test harness: bun:test (matches sibling tests in plugins/soleur/test/*.ts).

import { describe, test, expect, beforeAll } from "bun:test";
import { resolve } from "path";
import { readFileSync, existsSync } from "fs";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SHIP_SKILL = resolve(REPO_ROOT, "plugins/soleur/skills/ship/SKILL.md");
const AGENTS_CORE = resolve(REPO_ROOT, "AGENTS.core.md");
const AGENTS_REST = resolve(REPO_ROOT, "AGENTS.rest.md");
const AGENTS_INDEX = resolve(REPO_ROOT, "AGENTS.md");
const FIXTURE_DIR = resolve(
  REPO_ROOT,
  "plugins/soleur/test/fixtures/ship-undeferred-operator-step-gate",
);
const FIXTURE_PR_H = resolve(FIXTURE_DIR, "pr-h-counterfactual.md");
const FIXTURE_MIXED = resolve(FIXTURE_DIR, "mixed-tracked-untracked.md");

const GATE_HEADING = "### Undeferred Operator-Step Gate";
const NEXT_HEADING = "## Phase 6.4";
const GATE_ID = "wg-block-pr-ready-on-undeferred-operator-steps";
const RULE_ID = "hr-never-label-any-step-as-manual-without";

// Canonical detection regex — must mirror the bash ERE in ship/SKILL.md.
// JS port: `[[:space:]]` → `\s`; case-insensitive via /i flag.
// Anchored to start-of-line: only DECLARATIVE list-shape entries match.
const DETECT_REGEX =
  /^\s*([-*]|[0-9]+\.)\s+(\[[\sxX]\]\s+)?(\*\*)?(AC-PM[0-9]+|operator\s+(run|create|provision|configure|paste|cop(y|ies))s?|manual\s+gate|post-merge\s+operator)/im;

// Companion regex — previous/same/following line containing Tracks/Refs #NNNN
const COMPANION_REGEX = /(Tracks|Refs)\s+#[0-9]+/i;

function stripFencedCode(body: string): string {
  // Mirrors the bash awk + fail-closed fallback in ship/SKILL.md.
  // awk '/^```/ { in_fence = !in_fence; next } !in_fence { print } END { if (in_fence) exit 2 }'
  // If the END handler would trip (unbalanced fence), fail-closed: return the
  // un-stripped body so detection runs against everything (no silent bypass).
  const lines = body.split("\n");
  let inFence = false;
  const kept: string[] = [];
  for (const line of lines) {
    if (line.startsWith("```")) {
      inFence = !inFence;
      continue;
    }
    if (!inFence) kept.push(line);
  }
  if (inFence) return body; // fail-closed on unbalanced fence
  return kept.join("\n");
}

function detectMatches(body: string): number[] {
  // Returns 1-indexed line numbers that match the detection regex
  // after fenced-code-block strip.
  const stripped = stripFencedCode(body);
  const lines = stripped.split("\n");
  const matches: number[] = [];
  for (let i = 0; i < lines.length; i++) {
    if (DETECT_REGEX.test(lines[i])) matches.push(i + 1);
  }
  return matches;
}

function undeferredCount(body: string): number {
  // Mirrors the gate's rule: for each detection match, check previous, same,
  // OR following line for `(Tracks|Refs) #NNNN`. Count those without companion.
  const stripped = stripFencedCode(body);
  const lines = stripped.split("\n");
  const matches = detectMatches(body);
  let undeferred = 0;
  for (const lineNo of matches) {
    const prevLine = lineNo > 1 ? (lines[lineNo - 2] || "") : "";
    const sameLine = lines[lineNo - 1] || "";
    const nextLine = lines[lineNo] || "";
    const ctx = prevLine + "\n" + sameLine + "\n" + nextLine;
    if (!COMPANION_REGEX.test(ctx)) undeferred++;
  }
  return undeferred;
}

let SHIP_TEXT: string;
let GATE_SECTION: string;
let CORE_TEXT: string;
let REST_TEXT: string;
let INDEX_TEXT: string;
let FIXTURE_PR_H_TEXT: string;
let FIXTURE_MIXED_TEXT: string;

function getGateSection(text: string): string {
  const start = text.indexOf(GATE_HEADING);
  const end = text.indexOf(NEXT_HEADING, start);
  if (start === -1 || end === -1 || end <= start) {
    throw new Error(
      `Gate section boundary not found: start=${start} end=${end}. ` +
        `The "${GATE_HEADING}" or "${NEXT_HEADING}" heading was renamed/removed.`,
    );
  }
  return text.slice(start, end);
}

beforeAll(() => {
  if (!existsSync(SHIP_SKILL)) {
    throw new Error(`ship SKILL.md not found at ${SHIP_SKILL}`);
  }
  SHIP_TEXT = readFileSync(SHIP_SKILL, "utf8");
  GATE_SECTION = getGateSection(SHIP_TEXT);
  CORE_TEXT = readFileSync(AGENTS_CORE, "utf8");
  REST_TEXT = readFileSync(AGENTS_REST, "utf8");
  INDEX_TEXT = readFileSync(AGENTS_INDEX, "utf8");
  FIXTURE_PR_H_TEXT = readFileSync(FIXTURE_PR_H, "utf8");
  FIXTURE_MIXED_TEXT = readFileSync(FIXTURE_MIXED, "utf8");
});

describe("TC-1: ship/SKILL.md gate structure", () => {
  test("Phase 5.5 contains the Undeferred Operator-Step Gate subsection", () => {
    expect(SHIP_TEXT).toMatch(/^### Undeferred Operator-Step Gate/m);
  });

  test("gate body references the canonical rule it enforces", () => {
    expect(GATE_SECTION).toContain(RULE_ID);
  });

  test("gate body emits rule-application telemetry with the canonical wg-* ID", () => {
    expect(GATE_SECTION).toMatch(
      new RegExp(`emit_incident\\s+${GATE_ID}\\s+applied`),
    );
  });

  test("gate body contains the 3-option structured prompt", () => {
    expect(GATE_SECTION).toMatch(/1\.\s+\*\*File deferred-automation issues/);
    expect(GATE_SECTION).toMatch(/2\.\s+\*\*Cite an existing/);
    expect(GATE_SECTION).toMatch(/3\.\s+\*\*Override with operator-attestation/);
  });

  test("gate body contains list-anchored DETECT_RE and fenced-code strip", () => {
    expect(GATE_SECTION).toContain("DETECT_RE=");
    // List-anchored: requires bullet/numbered list at start of line
    expect(GATE_SECTION).toContain("^[[:space:]]*([-*]|[0-9]+\\.)");
    // Fenced-code-block strip via awk
    expect(GATE_SECTION).toContain("in_fence = !in_fence");
  });

  test("gate appears in Phase 5 Final Checklist", () => {
    expect(SHIP_TEXT).toMatch(
      /-\s+\[\s+\]\s+Undeferred operator-step gate passed/i,
    );
  });
});

describe("TC-2: detection regex — positive matches against mixed fixture", () => {
  test("flags all 3 list-shape operator/AC-PM lines in mixed fixture", () => {
    // Fixture has 3 list items: AC-PM1+operator runs (tracked), AC-PM2+operator
    // creates (untracked), operator pastes (untracked).
    expect(detectMatches(FIXTURE_MIXED_TEXT).length).toBe(3);
  });
});

describe("TC-3: detection rule — Tracks/Refs companion exempts the line", () => {
  test("undeferred count = 2 (AC-PM1 has Tracks #4115; AC-PM2 + paste lack companions)", () => {
    expect(undeferredCount(FIXTURE_MIXED_TEXT)).toBe(2);
  });
});

describe("TC-4: PR-H counterfactual", () => {
  test("PR-H fixture flags ≥3 matches (issue body's 3 unfiled steps)", () => {
    const flagged = detectMatches(FIXTURE_PR_H_TEXT).length;
    expect(flagged).toBeGreaterThanOrEqual(3);
  });

  test("PR-H fixture: every AC-PM line is undeferred (no Tracks/Refs companion)", () => {
    // The whole point of the counterfactual: had this gate existed when PR-H
    // shipped, all 6 AC-PM rows would have prompted the operator (3 became
    // #4114/#4115 filed-too-late; gate would have caught them pre-merge).
    expect(undeferredCount(FIXTURE_PR_H_TEXT)).toBeGreaterThanOrEqual(3);
  });
});

describe("TC-5: sentinel detection in linked-issue body", () => {
  const sentinelRegex = /deferred-automation|automation gap/i;

  test("body containing 'deferred-automation backlog item' matches sentinel", () => {
    const body = "This is a deferred-automation backlog item per the gate.";
    expect(sentinelRegex.test(body)).toBe(true);
  });

  test("body containing 'automation gap' (alternate sentinel) matches", () => {
    const body = "Tracks the automation gap identified during PR review.";
    expect(sentinelRegex.test(body)).toBe(true);
  });

  test("body without sentinel does not match", () => {
    const body = "Generic feature request with no automation-deferral context.";
    expect(sentinelRegex.test(body)).toBe(false);
  });
});

describe("TC-6: cross-reference invariant (core cross-ref + rest body)", () => {
  test("AGENTS.rest.md contains the wg-* gate rule body", () => {
    const line = REST_TEXT.split("\n").find((l) => l.includes(`[id: ${GATE_ID}]`));
    expect(line).toBeDefined();
  });

  test(`hr-never-label rule body references the new wg-* gate ID`, () => {
    // Find the rule body line (single-line rules per cq-agents-md-why-single-line)
    const ruleLine = CORE_TEXT.split("\n").find((l) => l.includes(`[id: ${RULE_ID}]`));
    expect(ruleLine).toBeDefined();
    expect(ruleLine!).toContain(GATE_ID);
  });

  test("AGENTS.md pointer-index contains the new wg-* gate ID → rest", () => {
    expect(INDEX_TEXT).toContain(`[id: ${GATE_ID}] → rest`);
  });
});

describe("TC-7: list-anchor excludes prose-style mentions (false-positive guard)", () => {
  test("prose mention 'the operator runs a separate audit' does not match", () => {
    const body =
      "The operator runs a separate audit on the side, mid-paragraph reference.";
    expect(detectMatches(body).length).toBe(0);
  });

  test("prose mention 'AC-PM1 is the operator's check' does not match", () => {
    const body = "AC-PM1 is the operator's subjective check per the carve-out.";
    expect(detectMatches(body).length).toBe(0);
  });

  test("blockquote with operator keyword does not match (no list-bullet)", () => {
    const body = "> operator runs the playbook";
    expect(detectMatches(body).length).toBe(0);
  });
});

describe("TC-8: fenced-code-block strip", () => {
  test("operator-runs line inside ```text fence does NOT count as match", () => {
    const body = [
      "Example PR body:",
      "",
      "```text",
      "- **AC-PM1** Operator runs `terraform apply`",
      "```",
      "",
      "End of example.",
    ].join("\n");
    expect(detectMatches(body).length).toBe(0);
  });

  test("operator-runs line OUTSIDE fence (after fence) DOES count", () => {
    const body = [
      "```text",
      "- inside-fence content",
      "```",
      "- **AC-PM2** Operator runs cleanup",
    ].join("\n");
    expect(detectMatches(body).length).toBe(1);
  });

  test("UNBALANCED fence fails closed (gate-bypass guard)", () => {
    // Adversarial pattern: append a single unbalanced ``` and an
    // operator-step line after it. Naive fence-strip would drop the line;
    // fail-closed restoration keeps the line in scope so detection fires.
    const body = [
      "Some prose.",
      "```bash",
      "- **AC-PM1** Operator runs terraform apply",
    ].join("\n");
    expect(detectMatches(body).length).toBeGreaterThanOrEqual(1);
  });
});

describe("TC-10: companion-citation lookup spans prev/same/next line", () => {
  test("Tracks #N on the PREVIOUS line exempts the match (header-above shape)", () => {
    const body = [
      "Tracks #4115",
      "- **AC-PM1** Operator runs terraform apply",
    ].join("\n");
    expect(undeferredCount(body)).toBe(0);
  });

  test("Tracks #N on the NEXT line exempts the match (continuation shape)", () => {
    const body = [
      "- **AC-PM1** Operator runs terraform apply",
      "  Tracks #4115",
    ].join("\n");
    expect(undeferredCount(body)).toBe(0);
  });
});

describe("TC-11: copy/copies verb-morphology", () => {
  test("Operator copies (plural) matches", () => {
    expect(detectMatches("- Operator copies the bootstrap script").length).toBe(1);
  });

  test("Operator copy (singular) matches", () => {
    expect(detectMatches("- Operator copy the bootstrap script").length).toBe(1);
  });
});

describe("TC-9: new gate rule body fits within byte cap", () => {
  test("wg-block-pr-ready-on-undeferred-operator-steps body ≤600 B", () => {
    const line = REST_TEXT.split("\n").find((l) => l.includes(`[id: ${GATE_ID}]`));
    expect(line).toBeDefined();
    expect(Buffer.byteLength(line!, "utf8")).toBeLessThanOrEqual(600);
  });
});
