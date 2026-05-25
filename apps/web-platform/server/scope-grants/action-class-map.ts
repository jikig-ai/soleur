// PR-G (#3947) / PR-H (#4077, #3244) — Canonical action-class registry.
//
// Code-static literal union — producers declare the literal at the
// `isGranted` / `inngest.send` boundary; no runtime classifier (ADR-034 §1).
// 5th class (money/legal/credentials) enforced by ABSENCE from this
// registry PLUS DB CHECK regex (ADR-034 §2 / hr-menu-option-ack-not-prod-write-auth).
//
// Adding an entry: extend ACTION_CLASSES, add to ACTION_CLASS_DEFAULTS
// AND ACTION_CLASS_CATEGORY, extend the switch in
// `test/server/scope-grants/action-class-exhaustive.test.ts`. Bump
// `expect(ACTION_CLASSES.length).toBe(...)` in the same test. Extend
// `lib/messages/action-class-copy.ts` with `{title, description, category}`
// per `test/messages/action-class-copy.test.ts` content rules
// (≤60-char title, ≤200-char description, category ∈ CATEGORY_ORDER).
//
// Consumers:
//   - server/inngest/functions/cfo-on-payment-failed.ts
//   - server/inngest/functions/github-on-event.ts (PR-H #3244)
//   - app/api/webhooks/stripe/route.ts
//   - app/api/webhooks/github/route.ts (PR-H #3244)
//   - app/api/dashboard/today/[id]/{send,edit,discard}/route.ts (PR-H #4077)
//   - server/action-sends/write-action-send.ts (PR-H #4077)
//   - app/(dashboard)/dashboard/settings/scope-grants/page.tsx (UI list)
//   - app/(dashboard)/dashboard/audit/page.tsx (audit row tier label)

export const ACTION_CLASSES = [
  "finance.payment_failed",
  // PR-H (#3244) — GitHub-sourced action classes (Phase 3).
  "engineering.pr_review_pending",
  "engineering.ci_failed",
  "triage.p0p1_issue",
  "security.cve_alert",
  // KB-drift is granted-by-default per plan §6.1.1 (internal-only data,
  // no per-founder opt-in needed); included here so isGranted resolves
  // it without a special-case in the webhook predicate.
  "knowledge.kb_drift",
  // PR-H (#4077) — Trust-tier external & infra classes.
  "external.low_stakes.customer_status_update",
  "external.low_stakes.vendor_support_ticket",
  "external.low_stakes.bluesky_reply_personal",
  "external.low_stakes.slack_dm_standard",
  "external.brand_critical.marketing_email_blast",
  "external.brand_critical.public_x_thread",
  "external.brand_critical.bluesky_reply_soleur_handle",
  "external.brand_critical.slack_dm_enterprise_tier1",
  "infra.dependency_bump",
  "infra.log_rotate",
] as const;
export type ActionClass = (typeof ACTION_CLASSES)[number];

// PR-H widens to 4 tiers — `auto_with_digest` is the 4th value backing
// the daily-digest substrate (`infra.*` classes default here). The digest
// emitter itself defers to PR-I (#4078); PR-H ships the tier value +
// substrate so producer-side writes land `tier_at_send='auto_with_digest'`.
export type ActionClassTier =
  | "auto"
  | "draft_one_click"
  | "approve_every_time"
  | "auto_with_digest";

export type ActionClassCategory =
  | "finance"
  | "engineering"
  | "triage"
  | "security"
  | "knowledge"
  | "external_low_stakes"
  | "external_brand_critical"
  | "infra";

// Most-restrictive sensible default per class. Production reads
// `scope_grants.tier` first; this map is the fallback used when no
// active grant exists for the founder (rare — typically only during
// pre-grant probe windows or in test fixtures).
//
// PR-H #3244 rationale: GitHub-sourced classes default to
// `draft_one_click` (highest-friction tier short of "approve each one").
//
// PR-A #4124 bump: knowledge.kb_drift bumped from `auto` to
// `draft_one_click` so the KbDriftCard "Fix link" / "Update anchor"
// click reaches the /send route's non-400 path (the spawn-agent
// Inngest function then emits a deterministic GitHub label
// acknowledgment per ADR-039 §PR-A). The producer-side digest emitter
// remains deferred to PR-I; no current writer assumed the old `auto`
// value for kb_drift (verified by test/server/scope-grants/
// kb-drift-tier-bump.test.ts producer-side cascade grep).
export const ACTION_CLASS_DEFAULTS: Record<ActionClass, ActionClassTier> = {
  "finance.payment_failed": "approve_every_time",
  "engineering.pr_review_pending": "draft_one_click",
  "engineering.ci_failed": "draft_one_click",
  "triage.p0p1_issue": "draft_one_click",
  "security.cve_alert": "approve_every_time",
  "knowledge.kb_drift": "draft_one_click",
  "external.low_stakes.customer_status_update": "draft_one_click",
  "external.low_stakes.vendor_support_ticket": "draft_one_click",
  "external.low_stakes.bluesky_reply_personal": "draft_one_click",
  "external.low_stakes.slack_dm_standard": "draft_one_click",
  "external.brand_critical.marketing_email_blast": "approve_every_time",
  "external.brand_critical.public_x_thread": "approve_every_time",
  "external.brand_critical.bluesky_reply_soleur_handle": "approve_every_time",
  "external.brand_critical.slack_dm_enterprise_tier1": "approve_every_time",
  "infra.dependency_bump": "auto_with_digest",
  "infra.log_rotate": "auto_with_digest",
};

// Category discriminant — drives Scope Grants UI grouping + audit-row
// tier labelling. The category is editorial (UI text), not a security
// boundary. Security is the per-class tier + DB CHECK enum-absence.
export const ACTION_CLASS_CATEGORY: Record<ActionClass, ActionClassCategory> = {
  "finance.payment_failed": "finance",
  "engineering.pr_review_pending": "engineering",
  "engineering.ci_failed": "engineering",
  "triage.p0p1_issue": "triage",
  "security.cve_alert": "security",
  "knowledge.kb_drift": "knowledge",
  "external.low_stakes.customer_status_update": "external_low_stakes",
  "external.low_stakes.vendor_support_ticket": "external_low_stakes",
  "external.low_stakes.bluesky_reply_personal": "external_low_stakes",
  "external.low_stakes.slack_dm_standard": "external_low_stakes",
  "external.brand_critical.marketing_email_blast": "external_brand_critical",
  "external.brand_critical.public_x_thread": "external_brand_critical",
  "external.brand_critical.bluesky_reply_soleur_handle":
    "external_brand_critical",
  "external.brand_critical.slack_dm_enterprise_tier1": "external_brand_critical",
  "infra.dependency_bump": "infra",
  "infra.log_rotate": "infra",
};

export function isKnownActionClass(s: string): s is ActionClass {
  return (ACTION_CLASSES as readonly string[]).includes(s);
}
