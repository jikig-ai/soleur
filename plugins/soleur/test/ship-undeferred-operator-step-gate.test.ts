// Undeferred Operator-Step Gate (#4117) — verifies plugins/soleur/skills/ship/SKILL.md
// Phase 5.5 contains the canonical gate definition that enforces hard rule
// `hr-never-label-any-step-as-manual-without` at the `gh pr ready` boundary.
//
// The gate is documentation that an LLM agent reads at /ship time; the only
// safety net against drift between the gate's bash regex and the AGENTS.rules.md
// rule cross-reference is this test file.
//
// Test harness: bun:test (matches sibling tests in plugins/soleur/test/*.ts).

import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { resolve, join } from "path";
import { tmpdir } from "os";
import {
  readFileSync,
  existsSync,
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  chmodSync,
  rmSync,
} from "fs";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SHIP_SKILL = resolve(REPO_ROOT, "plugins/soleur/skills/ship/SKILL.md");
const AGENTS_CORPUS = resolve(REPO_ROOT, "AGENTS.rules.md");
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
let CORPUS_TEXT: string;
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
  CORPUS_TEXT = readFileSync(AGENTS_CORPUS, "utf8");
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
    // ADR-179 decision 9 (#7450): the gate no longer sources incidents.sh from the git
    // root and calls emit_incident — on the review path that root is the contributor's
    // tree, and `source` executes into the current shell. It now prints an INERT marker
    // that a monorepo-only PostToolUse hook validates and records. The property this
    // guard was written for is unchanged: the gate must still name the canonical rule
    // it enforces, in a form the capture hook actually accepts.
    expect(GATE_SECTION).toMatch(
      new RegExp(`SOLEUR_RULE_APPLIED\\s+rule=${GATE_ID}\\s+note=`),
    );
    // And it must NOT have kept the retired construct.
    expect(GATE_SECTION).not.toMatch(/source .*git rev-parse --show-toplevel.*incidents\.sh/);
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

describe("TC-6: cross-reference invariant (both bodies now in one corpus)", () => {
  test("the corpus contains the wg-* gate rule body", () => {
    const line = CORPUS_TEXT.split("\n").find((l) => l.includes(`[id: ${GATE_ID}]`));
    expect(line).toBeDefined();
  });

  test(`hr-never-label rule body references the new wg-* gate ID`, () => {
    // Find the rule body line (single-line rules per cq-agents-md-why-single-line)
    const ruleLine = CORPUS_TEXT.split("\n").find((l) => l.includes(`[id: ${RULE_ID}]`));
    expect(ruleLine).toBeDefined();
    expect(ruleLine!).toContain(GATE_ID);
  });

  // ADR-151 dropped the ` → <class>` suffix from every pointer line, so the
  // assertion is now pointer PRESENCE (still the 1:1 contract lint_union
  // enforces) rather than pointer-plus-residency.
  test("AGENTS.md pointer-index contains the new wg-* gate ID", () => {
    expect(INDEX_TEXT).toContain(`[id: ${GATE_ID}]`);
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

describe("TC-12: delegated-act authoring form (ruling F1 + R4, detection unchanged)", () => {
  const DELEGATION_URL =
    "https://github.com/example-org/example-repo/issues/1#issuecomment-1";
  const ENVELOPE = "example/envelope.md#Example";
  const COMMAND_LINE = "example --flag value";

  // The gate counts phrasing. A CTO-performed act under a recorded Standing
  // Delegation is written in the form below, which does not start with the word
  // Operator, so it is not detected. A bullet that starts with Operator and a
  // verb is still detected whatever URL it cites: there is no URL exemption.
  const DELEGATED_BULLET =
    `- Delegated act (CTO, Standing Delegation ${DELEGATION_URL}, envelope ${ENVELOPE}, command "${COMMAND_LINE}"): flip the link`;
  const OPERATOR_VERB_BULLET =
    `- Operator runs the flip under Standing Delegation ${DELEGATION_URL}`;
  const OPERATOR_COLON_BULLET =
    `- **Operator: flip under Standing Delegation ${DELEGATION_URL}**`;

  // The TS DETECT_REGEX above is a deliberately narrow mirror (it has no
  // `Operator:` arm), so a "0 matches" assertion on it cannot see the hook's wider
  // regex and proves nothing about the form. The allow/deny verdicts below come from
  // the REAL hook: the shipped script, run with a stub gh on a private PATH dir and a
  // PreToolUse JSON on a piped (never inherited) stdin.
  const HOOK = resolve(REPO_ROOT, ".claude/hooks/ship-operator-step-gate.sh");
  let scratch: string;

  beforeAll(() => {
    scratch = mkdtempSync(join(tmpdir(), "ship-gate-realhook-"));
    mkdirSync(join(scratch, "incidents", ".claude"), { recursive: true });
    writeFileSync(
      join(scratch, "gh"),
      [
        "#!/usr/bin/env bash",
        'printf \'%s\\n\' "$*" >> "$GH_STUB_LOG"',
        'case "$*" in',
        '  "pr view 7 --json body --jq .body") cat "$GH_STUB_BODY" ;;',
        '  "issue view 5 --json state --jq .state") echo OPEN ;;',
        '  "issue view 5 --json body --jq .body") echo "deferred-automation backlog item" ;;',
        '  *) printf \'%s\\n\' "$*" >> "$GH_STUB_BAD"; echo "gh stub: unexpected argv: $*" >&2; exit 64 ;;',
        "esac",
        "",
      ].join("\n"),
    );
    chmodSync(join(scratch, "gh"), 0o755);
  });

  afterAll(() => {
    if (scratch) rmSync(scratch, { recursive: true, force: true });
  });

  // Runs the real hook against `gh pr ready 7` with the given PR body. The hook
  // fails OPEN when gh fails, so an allow only counts as evidence when the stub log
  // proves the PR-body call was reached and no unexpected argv was seen.
  function runRealHook(body: string): {
    decision: "allow" | "deny";
    reachedBodyCall: boolean;
    unexpected: string;
    stdout: string;
  } {
    const bodyFile = join(scratch, "body.md");
    const logFile = join(scratch, "calls.log");
    const badFile = join(scratch, "unexpected.log");
    writeFileSync(bodyFile, body + "\n");
    writeFileSync(logFile, "");
    writeFileSync(badFile, "");
    const env: Record<string, string> = {};
    for (const [k, v] of Object.entries(process.env)) {
      if (v !== undefined && k !== "SOLEUR_SKIP_OPERATOR_STEP_GATE") env[k] = v;
    }
    env.PATH = `${scratch}:${process.env.PATH ?? ""}`;
    env.GH_STUB_LOG = logFile;
    env.GH_STUB_BAD = badFile;
    env.GH_STUB_BODY = bodyFile;
    env.INCIDENTS_REPO_ROOT = join(scratch, "incidents");
    const input = JSON.stringify({
      tool_name: "Bash",
      tool_input: { command: "gh pr ready 7" },
      cwd: scratch,
    });
    const r = Bun.spawnSync({
      cmd: ["bash", HOOK],
      stdin: new TextEncoder().encode(input),
      stdout: "pipe",
      stderr: "pipe",
      env,
    });
    const stdout = r.stdout.toString();
    let decision: "allow" | "deny" = "allow";
    try {
      if (JSON.parse(stdout).decision === "deny") decision = "deny";
    } catch {
      // empty stdout (allow) is not JSON
    }
    return {
      decision,
      reachedBodyCall: readFileSync(logFile, "utf8")
        .split("\n")
        .includes("pr view 7 --json body --jq .body"),
      unexpected: readFileSync(badFile, "utf8"),
      stdout,
    };
  }

  test("REAL hook: the Delegated act (CTO, ..., command \"...\") bullet is allowed", () => {
    const r = runRealHook(DELEGATED_BULLET);
    expect(r.unexpected).toBe("");
    expect(r.reachedBodyCall).toBe(true);
    expect(r.decision).toBe("allow");
  });

  test("REAL hook: an Operator-verb bullet citing a delegation URL is denied (no URL exemption)", () => {
    const r = runRealHook(OPERATOR_VERB_BULLET);
    expect(r.unexpected).toBe("");
    expect(r.reachedBodyCall).toBe(true);
    expect(r.decision).toBe("deny");
  });

  test("REAL hook: a bold `Operator:` heading bullet is denied (the arm the TS mirror cannot see)", () => {
    const r = runRealHook(OPERATOR_COLON_BULLET);
    expect(r.unexpected).toBe("");
    expect(r.reachedBodyCall).toBe(true);
    expect(r.decision).toBe("deny");
  });

  test("REAL hook: the Delegated-act bullet does not shield an Operator bullet in the same body", () => {
    const r = runRealHook([DELEGATED_BULLET, "- Operator confirms the dashboard"].join("\n"));
    expect(r.reachedBodyCall).toBe(true);
    expect(r.decision).toBe("deny");
  });

  test("REAL hook: the Operator-verb bullet is cleared only by an OPEN deferred-automation Tracks companion (stub control)", () => {
    const r = runRealHook(`${OPERATOR_VERB_BULLET} Tracks #5`);
    expect(r.unexpected).toBe("");
    expect(r.reachedBodyCall).toBe(true);
    expect(r.decision).toBe("allow");
  });

  test("mirror: an Operator-verb bullet citing a delegation URL is counted undeferred by the TS mirror's own logic", () => {
    expect(detectMatches(OPERATOR_VERB_BULLET).length).toBe(1);
    expect(undeferredCount(OPERATOR_VERB_BULLET)).toBe(1);
  });

  test("the Undeferred section's Delegated-acts paragraph pins whole clauses of the R4 form", () => {
    // Section only: slice at the next gate heading so text in the Soak-Gated or
    // Technical-Ruling sections cannot satisfy these, then slice again at the
    // paragraph's own lead so text elsewhere in the Undeferred section cannot either.
    // Removing or reversing a clause turns this RED.
    const end = GATE_SECTION.indexOf("### Soak-Gated Follow-Through Enrollment Gate");
    expect(end).toBeGreaterThan(0);
    const undeferred = GATE_SECTION.slice(0, end);
    const lead = undeferred.indexOf("**Delegated acts (authoring form).**");
    expect(lead).toBeGreaterThan(0);
    const para = undeferred.slice(lead);

    // The authoring form, with the exact-envelope-line argument.
    expect(para).toContain(
      'Delegated act (CTO, Standing Delegation <comment-url>, envelope <path#title>, command "<exact envelope line>"): <act in words>',
    );
    // The envelope-bound verifier call, including --command.
    expect(para).toContain("delegation-verify.sh");
    expect(para).toContain(
      'verify --delegation <comment-url> --envelope <path#title> --command "<exact envelope line>"',
    );
    // A non-zero exit makes the bullet an operator step.
    expect(para).toContain("a non-zero exit (1 invalid, 2 unverifiable)");
    expect(para).toContain("makes the bullet an operator step");
    // No exemption beyond the form.
    expect(para).toContain("No URL or keyword exempts any other bullet");
    // An act that already ran: receipt URL, the ran row, audit mode with the run time.
    expect(para).toContain("receipt URL");
    expect(para).toContain("`ran` row");
    expect(para).toContain("--audit --at <ISO time the act ran>");
    expect(para).toContain("standing-delegation.md");
    // The exclusions, generic rather than hard-coded ids only, and the owner-human acts.
    expect(para).toContain(
      "Never use the form for any act the envelope or the Standing Delegation Excluded list names",
    );
    expect(para).toContain("any act whose text names an owner-human act");
    expect(para).toContain("SIGNED BY OWNER");
    expect(para).toContain("such a bullet is an operator step whatever its prefix");
    // The reversed clause must not be present.
    expect(para).not.toContain("Always use the form");
    // The detection regex itself stays untouched by the form.
    expect(undeferred).toContain("DETECT_RE=");
  });
});

describe("TC-9: new gate rule body fits within byte cap", () => {
  test("wg-block-pr-ready-on-undeferred-operator-steps body ≤600 B", () => {
    const line = CORPUS_TEXT.split("\n").find((l) => l.includes(`[id: ${GATE_ID}]`));
    expect(line).toBeDefined();
    expect(Buffer.byteLength(line!, "utf8")).toBeLessThanOrEqual(600);
  });
});
