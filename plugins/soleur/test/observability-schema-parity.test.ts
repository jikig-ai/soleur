// `## Observability` schema parity guard (#4133, follow-through of #4116 / PR #4123).
//
// The `## Observability` plan block — 5 top-level fields (liveness_signal,
// error_reporting, failure_modes, logs, discoverability_test) — is replicated
// verbatim across 4 doc surfaces with no compile-time or commit-time guard.
// Phase 4.7 of deepen-plan enforces the schema at plan-AUTHORING time (against a
// plan file), but nothing guards the canonical schema DEFINITIONS themselves
// against drifting apart. A rename or field add/remove in any single surface
// silently desyncs the gate from its own template.
//
// This test treats `plan/SKILL.md §2.9` as canonical and asserts the other
// surfaces agree:
//   1 (canonical) plan/SKILL.md            — yaml block after "**Required schema (verbatim"
//   2             plan-issue-templates.md   — 3 `## Observability` yaml blocks (one per tier)
//   3             deepen-plan/SKILL.md §4.7 — prose enumeration of the 5 backticked names
//   4             AGENTS.core.md rule       — count-parity only: `(5 fields)` + no-SSH invariant
//                 (the 5 names are intentionally NOT enumerated there — the always-loaded
//                  rule budget is byte-capped, so this surface asserts the COUNT, not the names)
//
// Surface 2's block walk reuses `extractAllObservabilityBlocks` from the shared
// discoverability-test-parser so we do not fork a third `## Observability` parser
// (a forked parser is itself a drift surface — exactly the failure class this
// test guards against).

import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { extractAllObservabilityBlocks } from "./lib/discoverability-test-parser";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const read = (p: string) => readFileSync(resolve(REPO_ROOT, p), "utf8");

const PLAN_SKILL = "plugins/soleur/skills/plan/SKILL.md";
const TEMPLATES = "plugins/soleur/skills/plan/references/plan-issue-templates.md";
const DEEPEN = "plugins/soleur/skills/deepen-plan/SKILL.md";
const AGENTS_CORE = "AGENTS.core.md";

const EXPECTED = [
  "liveness_signal",
  "error_reporting",
  "failure_modes",
  "logs",
  "discoverability_test",
] as const;

// Column-0 `key:` names inside a fenced yaml block body. Indented sub-fields
// (any leading whitespace) are excluded — only top-level keys count.
function topLevelKeys(blockBody: string): string[] {
  return blockBody
    .split(/\r?\n/)
    .map((l) => l.match(/^([a-z_]+):/)?.[1])
    .filter((k): k is string => Boolean(k));
}

// Body of the first ```yaml fence appearing in `text`. `label` identifies the
// surface/block in the throw so a real drift points at the offending source.
// The `[^\n]*` after the language token tolerates a trailing info-string
// (e.g. ```yaml title=…) so a benign fence edit does not false-fail.
function firstYamlBlock(text: string, label: string): string {
  const m = text.match(/```ya?ml[^\n]*\r?\n([\s\S]*?)\r?\n```/);
  if (!m) throw new Error(`no \`\`\`yaml fence found in ${label}`);
  return m[1];
}

// Canonical: the yaml block immediately after the "**Required schema (verbatim" marker.
const canonicalSrc = read(PLAN_SKILL);
const markerIdx = canonicalSrc.indexOf("**Required schema (verbatim");
if (markerIdx === -1) throw new Error(`canonical marker not found in ${PLAN_SKILL}`);
const CANONICAL = topLevelKeys(
  firstYamlBlock(canonicalSrc.slice(markerIdx), "plan/SKILL.md §2.9 canonical block"),
);

const asSet = (xs: readonly string[]) => new Set(xs);

describe("## Observability schema parity across the 4 surfaces", () => {
  test("surface 1 (canonical, plan/SKILL.md §2.9) — exactly the 5 expected fields", () => {
    // Sanity anchor: a 6th field added ONLY to canonical is caught here.
    expect(CANONICAL.length).toBe(5);
    expect(asSet(CANONICAL)).toEqual(asSet(EXPECTED));
  });

  test("surface 2 (plan-issue-templates.md) — exactly 3 blocks, each set-equal to canonical", () => {
    const sections = extractAllObservabilityBlocks(read(TEMPLATES));
    // Exactly 3 `## Observability` template blocks (MINIMAL / MORE / A LOT).
    // A dropped or added template is drift and must fail here.
    expect(sections.length).toBe(3);
    sections.forEach((section, i) => {
      const keys = topLevelKeys(firstYamlBlock(section, `plan-issue-templates.md block #${i + 1}`));
      expect(asSet(keys), `template block #${i + 1} top-level keys must equal canonical`).toEqual(
        asSet(CANONICAL),
      );
    });
  });

  test("surface 3 (deepen-plan/SKILL.md §4.7) — field enumeration set-equals canonical", () => {
    const matches = read(DEEPEN)
      .split(/\r?\n/)
      .filter((l) => l.includes("required top-level fields"));
    // Exactly one enumeration line — a second copy would let drift in it go unseen.
    expect(matches.length, "expected exactly one deepen-plan §4.7 enumeration line").toBe(1);
    const line = matches[0];
    // The count word ("the 5 required top-level fields") must match canonical length.
    const countMatch = line.match(/the (\d+) required top-level fields/);
    expect(countMatch, "expected 'the N required top-level fields'").not.toBeNull();
    expect(Number(countMatch![1])).toBe(CANONICAL.length);
    // Extract names from the parenthetical list ONLY, so an unrelated backticked
    // lowercase word elsewhere on the line cannot pollute the set.
    const paren = line.match(/required top-level fields \(([^)]*)\)/);
    expect(paren, "expected a parenthetical field list after the count").not.toBeNull();
    const names = [...paren![1].matchAll(/`([a-z_]+)`/g)].map((m) => m[1]);
    expect(asSet(names)).toEqual(asSet(CANONICAL));
  });

  test("surface 4 (AGENTS.core.md rule) — count parity + no-SSH invariant (names intentionally absent)", () => {
    const rule = read(AGENTS_CORE)
      .split(/\r?\n/)
      .find((l) => l.includes("hr-observability-as-plan-quality-gate"));
    expect(rule, "hr-observability-as-plan-quality-gate rule line must exist").toBeDefined();
    // Count derived from canonical length — stays correct if the schema legitimately grows.
    expect(rule, "AGENTS.core.md rule must state count parity `(N fields)`").toContain(
      `(${CANONICAL.length} fields)`,
    );
    expect(rule, "AGENTS.core.md rule must reference discoverability_test").toContain(
      "discoverability_test",
    );
    expect(rule, "AGENTS.core.md rule must state the WITHOUT SSH invariant").toContain("WITHOUT SSH");
  });
});
