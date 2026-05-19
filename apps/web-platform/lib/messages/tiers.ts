// PR-F (#3244, #3940) — single source of truth for messages.tier and
// messages.status string literals used across the CFO write path, the
// /api/dashboard/today read path, and their tests.
//
// Review P2-6 (pattern-recognition + code-quality multi-agent finding):
// 6 in-repo sites previously repeated these literals; a typo at any
// consumer silently filtered the dashboard to empty. Migration SQL
// keeps the literal (migrations are frozen text) but every TS consumer
// imports from here.

export const MESSAGE_TIER_EXTERNAL_BRAND_CRITICAL =
  "external_brand_critical" as const;
export const MESSAGE_TIER_EXTERNAL_LOW_STAKES =
  "external_low_stakes" as const;

export const EXTERNAL_TIERS = [
  MESSAGE_TIER_EXTERNAL_BRAND_CRITICAL,
  MESSAGE_TIER_EXTERNAL_LOW_STAKES,
] as const;

export const MESSAGE_STATUS_DRAFT = "draft" as const;
export const MESSAGE_STATUS_ARCHIVED = "archived" as const;
