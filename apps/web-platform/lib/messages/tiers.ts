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

// PR-H (#3244) — multi-source dedup constants. Used by the GitHub
// webhook + Inngest dispatcher (Phase 3-4) and the KB-drift ingest
// route (Phase 5). The `source` column in messages is a free-form
// text today; constraining via these constants keeps every TS
// consumer aligned without DB-level enum churn.
export const MESSAGE_SOURCE_STRIPE = "stripe" as const;
export const MESSAGE_SOURCE_GITHUB = "github" as const;
export const MESSAGE_SOURCE_KB_DRIFT = "kb-drift" as const;

export const MESSAGE_SOURCES = [
  MESSAGE_SOURCE_STRIPE,
  MESSAGE_SOURCE_GITHUB,
  MESSAGE_SOURCE_KB_DRIFT,
] as const;

export type MessageSource = (typeof MESSAGE_SOURCES)[number];

// PR-H — owning_domain widened to admit the KB-drift "direct-action"
// surface. The existing values ('finance', 'engineering', 'product',
// 'triage', 'security') are unchanged at the consumer level.
export const MESSAGE_OWNING_DOMAIN_KNOWLEDGE = "knowledge" as const;
