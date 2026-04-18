import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

// skill-summary.test.ts — contract test for the stdout JSON summary
// documented in SKILL.md §7.5 (#2357). The helper below mirrors what
// the skill's instruction text tells the orchestrator to emit.
//
// Consumer-boundary assertion (per
// 2026-04-18-schema-version-must-be-asserted-at-consumer-boundary.md):
// this test actively reads SKILL.md §7.5 and asserts the documented
// field list matches the helper's output. A rename in SKILL.md fails
// the test loudly — the test is not self-referential.

export interface SummaryInput {
  filed: number;
  suppressed: number;
  skipped: number;
  hashes: string[];
}

export function formatSummary(input: SummaryInput): string {
  const out = {
    filed: input.filed,
    suppressed: input.suppressed,
    skipped: input.skipped,
    hashes: [...input.hashes].sort(),
  };
  return JSON.stringify(out);
}

const SKILL_MD = readFileSync(
  resolve(import.meta.dir, "../../skills/ux-audit/SKILL.md"),
  "utf8",
);

// Regex anchored to §7.5 so renaming/moving the section fails loudly.
const SUMMARY_SECTION = SKILL_MD.match(
  /### 7\.5 Stdout summary[\s\S]*?(?=\n### |\n## |$)/,
)?.[0];

const REQUIRED_FIELDS = ["filed", "suppressed", "skipped", "hashes"] as const;

describe("SKILL.md §7.5 stdout summary contract (#2357)", () => {
  test("SKILL.md contains §7.5 Stdout summary", () => {
    expect(SUMMARY_SECTION).toBeDefined();
  });

  test("§7.5 documents all four required fields", () => {
    for (const field of REQUIRED_FIELDS) {
      expect(SUMMARY_SECTION).toContain(field);
    }
  });

  test("formatSummary output matches the §7.5 shape", () => {
    const out = formatSummary({
      filed: 2,
      suppressed: 1,
      skipped: 0,
      hashes: ["b", "a"],
    });
    const parsed = JSON.parse(out);
    expect(Object.keys(parsed)).toEqual([...REQUIRED_FIELDS]);
    expect(parsed.filed).toBe(2);
    expect(parsed.suppressed).toBe(1);
    expect(parsed.skipped).toBe(0);
    expect(parsed.hashes).toEqual(["a", "b"]);
  });

  test("formatSummary emits a single-line JSON string", () => {
    const out = formatSummary({
      filed: 0,
      suppressed: 0,
      skipped: 0,
      hashes: [],
    });
    expect(out).not.toContain("\n");
    expect(() => JSON.parse(out)).not.toThrow();
  });

  test("early-exit shape is parseable (all zeros + empty hashes)", () => {
    const out = formatSummary({
      filed: 0,
      suppressed: 0,
      skipped: 0,
      hashes: [],
    });
    expect(JSON.parse(out)).toEqual({
      filed: 0,
      suppressed: 0,
      skipped: 0,
      hashes: [],
    });
  });
});
