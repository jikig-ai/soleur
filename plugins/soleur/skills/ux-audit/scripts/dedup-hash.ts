/**
 * dedup-hash.ts — canonical finding-hash computation.
 *
 * Hash format: sha256(utf8("{route}|{selector}|{category}")).
 * Embedded in issue bodies as `<!-- ux-audit-hash: <64-hex> -->` so the skill
 * can dedupe via a single `gh issue list --search "ux-audit-hash: <hash>"` call
 * (TR3 in the plan).
 */

import { createHash } from "node:crypto";

/**
 * Canonical category list. Drift-guarded by `category-drift.test.ts`
 * (see `plugins/soleur/test/ux-audit/category-drift.test.ts`). Any
 * edit here requires updating SKILL.md §"Constants", ux-design-lead.md
 * §"5-category rubric" + `category` field rule, and the
 * `properties.category.enum` in
 * `plugins/soleur/skills/ux-audit/references/finding.schema.json`.
 */
export const FINDING_CATEGORIES = [
  "real-estate",
  "ia",
  "consistency",
  "responsive",
  "comprehension",
] as const;

export type FindingCategory = (typeof FINDING_CATEGORIES)[number];

export interface Finding {
  route: string;
  selector: string;
  category: FindingCategory;
}

export function computeFindingHash(f: Finding): string {
  if (!FINDING_CATEGORIES.includes(f.category as FindingCategory)) {
    throw new Error(
      `invalid category "${f.category}" — expected one of: ${FINDING_CATEGORIES.join(", ")}`,
    );
  }
  const selector = f.selector === "" ? "*" : f.selector;
  const canonical = `${f.route}|${selector}|${f.category}`;
  return createHash("sha256").update(canonical, "utf8").digest("hex");
}
