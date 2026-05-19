// PR-G (#3947) — Canonical action-class map. Lifts PR-F's inlined
// `TIER` constant (cfo-on-payment-failed.ts RV4 named PR-G as the
// 2nd-consumer trigger for this extraction). Used by:
//   - server/inngest/functions/cfo-on-payment-failed.ts (fallback tier)
//   - app/api/webhooks/stripe/route.ts (action-class identifier)
//   - app/(dashboard)/dashboard/settings/scope-grants/page.tsx (UI list)
//   - app/(dashboard)/dashboard/audit/page.tsx (audit row tier label)

export const ACTION_CLASSES = ["finance.payment_failed"] as const;
export type ActionClass = (typeof ACTION_CLASSES)[number];

export type ActionClassTier = "auto" | "draft_one_click" | "approve_every_time";

// Most-restrictive default per action class. Unreachable in production
// when the webhook predicate passes `tier: grant.tier` in inngest.send
// data (Phase 2.1) — the CFO function reads event.data.tier first and
// only falls back to this default when an event arrives without a tier
// (test fixtures, replay of pre-PR-G events).
export const ACTION_CLASS_DEFAULTS: Record<ActionClass, ActionClassTier> = {
  "finance.payment_failed": "approve_every_time",
};

export function isKnownActionClass(s: string): s is ActionClass {
  return (ACTION_CLASSES as readonly string[]).includes(s);
}
