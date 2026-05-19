// PR-G (#3947) — Canonical action-class map. Lifts PR-F's inlined
// `TIER` constant (cfo-on-payment-failed.ts RV4 named PR-G as the
// 2nd-consumer trigger for this extraction). Used by:
//   - server/inngest/functions/cfo-on-payment-failed.ts (fallback tier)
//   - app/api/webhooks/stripe/route.ts (action-class identifier)
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
] as const;
export type ActionClass = (typeof ACTION_CLASSES)[number];

export type ActionClassTier = "auto" | "draft_one_click" | "approve_every_time";

// Most-restrictive default per action class. Unreachable in production
// when the webhook predicate passes `tier: grant.tier` in inngest.send
// data (Phase 2.1) — the CFO function reads event.data.tier first and
// only falls back to this default when an event arrives without a tier
// (test fixtures, replay of pre-PR-G events).
//
// PR-H rationale: GitHub-sourced classes default to `draft_one_click`
// (highest-friction tier short of "approve each one"). KB-drift is the
// single exception: it carries no founder-routed PII at all (internal
// link health) and defaults to `auto`.
export const ACTION_CLASS_DEFAULTS: Record<ActionClass, ActionClassTier> = {
  "finance.payment_failed": "approve_every_time",
  "engineering.pr_review_pending": "draft_one_click",
  "engineering.ci_failed": "draft_one_click",
  "triage.p0p1_issue": "draft_one_click",
  "security.cve_alert": "approve_every_time",
  "knowledge.kb_drift": "auto",
};

export function isKnownActionClass(s: string): s is ActionClass {
  return (ACTION_CLASSES as readonly string[]).includes(s);
}
