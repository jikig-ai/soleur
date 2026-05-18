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
} as const;

export type TrustTier = keyof typeof TRUST_TIER_COPY;
