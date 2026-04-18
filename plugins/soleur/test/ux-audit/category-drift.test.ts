import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { FINDING_CATEGORIES } from "../../skills/ux-audit/scripts/dedup-hash";

// EXPECTED is the canonical category list — drift-guard for #2356.
// If you add/remove a category, bump this tuple AND the three
// documentation sites together (SKILL.md, ux-design-lead.md,
// finding.schema.json). The .toEqual() below surfaces any drift
// as a readable diff, not an opaque length mismatch.
const EXPECTED = [
  "real-estate",
  "ia",
  "consistency",
  "responsive",
  "comprehension",
] as const;

const SKILL_MD = readFileSync(
  resolve(import.meta.dir, "../../skills/ux-audit/SKILL.md"),
  "utf8",
);

const AGENT_MD = readFileSync(
  resolve(import.meta.dir, "../../agents/product/design/ux-design-lead.md"),
  "utf8",
);

describe("FINDING_CATEGORIES drift guard (#2356)", () => {
  test("exported list matches the canonical EXPECTED tuple", () => {
    expect([...FINDING_CATEGORIES]).toEqual([...EXPECTED]);
  });

  test("length pin catches a silent category addition", () => {
    // If this pin fails, you added a category. Update EXPECTED above
    // AND update SKILL.md §"Constants", ux-design-lead.md §"5-category
    // rubric" + field rule, AND finding.schema.json enum — then bump
    // this pin. Do not bump in isolation.
    expect(FINDING_CATEGORIES.length).toBe(5);
  });

  test("every category appears in SKILL.md and ux-design-lead.md", () => {
    for (const category of FINDING_CATEGORIES) {
      expect(SKILL_MD).toContain(category);
      expect(AGENT_MD).toContain(category);
    }
  });

  test("agent field rule lists the canonical 5-category phrase", () => {
    expect(AGENT_MD).toContain(
      "real-estate | ia | consistency | responsive | comprehension",
    );
  });
});
