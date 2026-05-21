// PR-G (#3947) — Single source of truth for trust-tier human-readable
// labels + descriptions. Per messages/tiers.ts:5-8 pattern: a typo at
// any consumer silently propagates to the UI. Every consumer (scope-grant
// page, audit viewer, onboarding banner) imports from here.

export const TRUST_TIER_COPY = {
  auto: {
    label: "Auto",
    badge: "Consequential",
    description:
      "Soleur executes this action without your review. Use only for actions you want fully automated.",
    confirmText:
      "Confirm: Soleur will execute this action without your review. You can revoke at any time, but revoking will not stop runs already in progress.",
  },
  draft_one_click: {
    label: "Draft, one click",
    badge: "Standard",
    description:
      "Soleur prepares a draft; you approve with one click. Recommended for most actions.",
    confirmText: null,
  },
  approve_every_time: {
    label: "Approve every time",
    badge: "Safest",
    description:
      "Soleur proposes; you authorize each time. Highest oversight.",
    confirmText: null,
  },
  // PR-H (#4077) — 4th tier; infra.* default. The daily digest emitter
  // itself defers to PR-I (#4078); PR-H ships the tier value + label so
  // the Scope Grants UI can surface the choice and producer writes can
  // record `tier_at_send='auto_with_digest'`. Per Privacy §8.3 Art. 22(3),
  // the next-business-day digest review window IS the human-review path.
  auto_with_digest: {
    label: "Auto with daily digest",
    badge: "Bundled",
    description:
      "Soleur executes infrastructure actions without per-action review; a daily digest summarizes what shipped. Designed for infra.* classes where per-action oversight is uneconomic.",
    confirmText:
      "Confirm: Soleur will execute these actions and email you a daily digest. You can revoke or re-classify at any time; revoking will not stop runs already in progress.",
  },
} as const;

export type TrustTier = keyof typeof TRUST_TIER_COPY;

// PR-I (#4078) — Founder-facing copy for the 8-value
// template_authorizations.revocation_reason enum. Surfaced on the
// scope-grants settings page (Phase 7) when a template authorization
// is revoked. Three reasons (regulator_ordered, vendor_tos_revoked,
// policy_violation) have no v1 producer but are pre-provisioned per
// plan §Sharp Edges (Art. 5(2) attribution; cheaper than ALTER later).
// quarantine_retroactive is reserved for PR-I+1 (#4216) — keep the
// copy stable to avoid a parity test churn when classifier-feedback
// retroactive UI ships.
export const REVOCATION_REASON_COPY = {
  founder_revoked: {
    label: "Revoked by you",
    description: "You revoked this template authorization from Settings.",
  },
  quota_exhausted: {
    label: "Quota exhausted",
    description:
      "Reached the 100-send limit for this template. Click Send again to re-authorize for another 100.",
  },
  expired: {
    label: "Expired",
    description:
      "The 90-day authorization window closed. Click Send again to re-authorize.",
  },
  dsr_erasure: {
    label: "Erased (DSAR)",
    description:
      "Your account or this row was anonymised under a data-subject erasure request (GDPR Art. 17).",
  },
  regulator_ordered: {
    label: "Revoked by regulator order",
    description:
      "A regulator-mandated takedown applies to this template. Contact support to reauthorize.",
  },
  vendor_tos_revoked: {
    label: "Revoked by vendor policy",
    description:
      "The downstream vendor's terms of service no longer permit this template.",
  },
  policy_violation: {
    label: "Revoked for policy violation",
    description:
      "Soleur's acceptable use policy was violated. See the policy at /docs/legal/acceptable-use-policy.",
  },
  quarantine_retroactive: {
    label: "Quarantined retroactively",
    description:
      "A misclassified send was reclassified by the classifier-feedback flow (PR-I+1).",
  },
} as const;

export type RevocationReason = keyof typeof REVOCATION_REASON_COPY;
