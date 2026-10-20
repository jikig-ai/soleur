/**
 * ADR-110 — semantic model-tier map (Claude Code + Grok Build + OpenCode).
 *
 * Workflow pins and advisor-gate spawns name cost/role (`cheap`, `standard`,
 * `strong`, `advisor`, `inherit`), never a vendor SKU. This module is the
 * single table to bump when Anthropic, xAI or OpenCode rename a generation.
 *
 * Grok SKUs confirmed 2026-09-23 (docs.x.ai + `grok models` on CLI 1.0.40).
 * Slug choice and prices: ADR-110 addendum 2026-09-23. grok-build-0.1 is an
 * API SKU, not a CLI slug — never pin it.
 *
 * OpenCode SKUs measured 2026-10-19 on CLI 2.0.32 (measurement §12.7). Two facts
 * set the rule. (1) A keyless install advertises exactly ONE provider — OpenCode's
 * own `opencode` Zen provider — so a keyless map must name `opencode/...` slugs; the
 * Anthropic/OpenAI/xAI entries the catalog also carries need a Console API key. An
 * absolute pin is only correct where its SKU is always available (ADR-053 tier 2),
 * and the keyless set is the only always-available set here. (2) `GET /api/provider`
 * hands back `models: 0`, so there is no capability or price METADATA to order the
 * free slugs by; the order below follows the Zen catalog's published prices where the
 * slugs name a lineage with a paid sibling (GLM 5.3 Flash $0.15/$0.50 — the catalog's
 * cheap band), and collapses the upper three onto the provider's own default exactly
 * as the Grok map does. `opencode/big-pickle` is the id this harness session itself
 * runs on.
 *
 * Rejected, with reasons, so they are not reintroduced: the `nemotron-*` free slugs
 * (NVIDIA trial terms — "do not submit personal or confidential data", and logged);
 * the paid Zen Claude/OpenAI rows (not always-available, so a violation of the
 * absolute-pin rule rather than a tiering judgment); `opencode/big-pickle` for
 * `cheap` (it is the flagship, and a `cheap` pin must not silently upgrade a session
 * on a mechanical step). Every free slug is vendor-declared "for a limited time", so
 * this row is EXPECTED to need bumping — which is the table's stated purpose.
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
  opencode: {
    cheap: "opencode/glm-5.3-flash-free",
    standard: "opencode/big-pickle",
    strong: "opencode/big-pickle",
    advisor: "opencode/big-pickle",
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
