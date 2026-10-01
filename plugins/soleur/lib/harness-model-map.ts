/**
 * ADR-110 — semantic model-tier map (Claude Code + Grok Build).
 *
 * Workflow pins and advisor-gate spawns name cost/role (`cheap`, `standard`,
 * `strong`, `advisor`, `inherit`), never a vendor SKU. This module is the
 * single table to bump when Anthropic or xAI rename a generation.
 *
 * Grok SKUs confirmed 2026-09-23 (docs.x.ai + `grok models` on CLI 1.0.40).
 * Slug choice and prices: ADR-110 addendum 2026-09-23. grok-build-0.1 is an
 * API SKU, not a CLI slug — never pin it.
 *
 * Workflow runtime has no import/filesystem. Each pinned `*.workflow.js` inlines
 * a copy of TIER_MAPS behind `<!-- harness-model-map:start/end -->`; 
 * test/harness-model-map.test.ts asserts those copies match this file.
 */

import { type Harness } from "./harness";

export type { Harness };
export type SemanticTier = "cheap" | "standard" | "strong" | "advisor" | "inherit";

export const SEMANTIC_TIERS: readonly SemanticTier[] = [
  "cheap",
  "standard",
  "strong",
  "advisor",
  "inherit",
] as const;

const SEMANTIC_TIER_SET: ReadonlySet<string> = new Set(SEMANTIC_TIERS);

export const TIER_MAPS = {
  claude: {
    cheap: "haiku",
    standard: "sonnet",
    strong: "opus",
    advisor: "fable",
    inherit: "inherit",
  },
  grok: {
    cheap: "grok-4.5",
    standard: "grok-4.7",
    strong: "grok-4.7",
    advisor: "grok-4.7",
    inherit: "inherit",
  },
} as const;

export function resolveModelTier(tier: SemanticTier, harness: Harness): string {
  if (!SEMANTIC_TIER_SET.has(tier)) {
    throw new Error(`unknown semantic tier: ${String(tier)}`);
  }
  if (tier === "inherit") {
    return "inherit";
  }
  if (harness === "unknown" || !(harness in TIER_MAPS)) {
    console.warn(
      `resolveModelTier: unmapped harness ${harness}, passing inherit for tier ${tier}`,
    );
    return "inherit";
  }
  return TIER_MAPS[harness][tier];
}

/** ADR-083 primary advisor SKU (Claude: fable; Grok: strong-map). */
export function resolveAdvisorTier(harness: Harness): string {
  return resolveModelTier("advisor", harness);
}

/** ADR-083 fallback when the primary advisor spawn is rejected (Claude: opus). */
export function resolveAdvisorFallback(harness: Harness): string {
  return resolveModelTier("strong", harness);
}
