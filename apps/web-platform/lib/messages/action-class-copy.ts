// #4067-followup — Single source of truth for human-readable action-class
// titles + descriptions + category labels. Mirrors the PR-G `trust-tier-copy.ts`
// pattern (see lib/messages/trust-tier-copy.ts:1).
//
// The `ACTION_CLASSES` literal union in `server/scope-grants/action-class-map.ts`
// is the technical-identity source-of-truth (DB CHECK constraints, Inngest
// function names, webhook routers depend on those exact strings). This file
// adds an editorial layer on top: every consumer that wants to RENDER an
// action class to a founder reads `ACTION_CLASS_COPY[ac].title` instead of
// the dotted ID.
//
// Adding an entry: extend `ACTION_CLASSES` per the checklist in
// `server/scope-grants/action-class-map.ts`, then add one entry here with:
//   - title:       ≤ 60 chars, active voice, no dotted IDs, no jargon
//   - description: ≤ 200 chars, one sentence
//   - category:    one of the 8 values in `CATEGORY_ORDER` below
// The `satisfies` rail below + `test/messages/action-class-copy.test.ts`
// enforce both shape and parity.
//
// Consumers:
//   - components/scope-grants/scope-grant-row.tsx           (row heading)
//   - app/(dashboard)/dashboard/settings/scope-grants/page.tsx  (category grouping)
//   - components/audit/audit-sections.tsx                    (mailto + summary)
//   - components/audit/redacted-event-summary.tsx            (masked summary)
//   - components/dashboard/runtime-explainer-banner.tsx      (first-run banner)
//   - components/dashboard/today-card.tsx                    (typed-confirm modal)

import {
  ACTION_CLASSES,
  type ActionClass,
} from "@/server/scope-grants/action-class-map";

export interface ActionClassCopy {
  title: string;
  description: string;
  category: string;
}

// Stable display order for category-grouped UIs (Scope Grants page,
// runtime explainer banner). Matches the operator mental model: money
// first (highest-stakes), then internal engineering, then external
// surfaces, then infrastructure (lowest-stakes).
export const CATEGORY_ORDER = [
  "Money",
  "Engineering",
  "Triage",
  "Security",
  "Knowledge",
  "Customer replies",
  "Brand-critical sends",
  "Infrastructure",
] as const;

export type ActionClassCategory = (typeof CATEGORY_ORDER)[number];

export const ACTION_CLASS_COPY = {
  "finance.payment_failed": {
    title: "Stripe payment failed",
    description:
      "A customer's card declined. Soleur can draft a dunning email, retry the charge, or pause access.",
    category: "Money",
  },
  "engineering.pr_review_pending": {
    title: "Pull request awaiting review",
    description:
      "A PR has been open without review activity. Soleur can draft a review, summarize the diff, or ping the author.",
    category: "Engineering",
  },
  "engineering.ci_failed": {
    title: "CI build failed",
    description:
      "A CI run on main or a PR went red. Soleur can triage the failure, attempt a fix, or comment with the likely cause.",
    category: "Engineering",
  },
  "triage.p0p1_issue": {
    title: "High-priority issue filed",
    description:
      "A P0 or P1 GitHub issue was opened. Soleur can classify, draft a first response, or attempt an automated fix.",
    category: "Triage",
  },
  "security.cve_alert": {
    title: "CVE security alert",
    description:
      "A dependency CVE was published. Soleur can assess exposure, draft an upgrade PR, or schedule a rotation.",
    category: "Security",
  },
  "knowledge.kb_drift": {
    title: "Knowledge base drift detected",
    description:
      "Internal documentation contradicts current code or behavior. Soleur can refresh the affected pages.",
    category: "Knowledge",
  },
  "external.low_stakes.customer_status_update": {
    title: "Customer status update reply",
    description:
      "Routine reply to an existing customer thread — ETAs, confirmations, acknowledgements.",
    category: "Customer replies",
  },
  "external.low_stakes.vendor_support_ticket": {
    title: "Vendor support ticket reply",
    description:
      "Follow-up on an open ticket with a vendor's support team. No new commitments or contract changes.",
    category: "Customer replies",
  },
  "external.low_stakes.bluesky_reply_personal": {
    title: "Bluesky reply (personal handle)",
    description:
      "Reply on your personal Bluesky account. Not posted from the Soleur brand handle.",
    category: "Customer replies",
  },
  "external.low_stakes.slack_dm_standard": {
    title: "Slack DM (standard contact)",
    description:
      "Direct message to a standard contact in Slack — no enterprise tier, no public channel exposure.",
    category: "Customer replies",
  },
  "external.brand_critical.marketing_email_blast": {
    title: "Marketing email blast",
    description:
      "Outbound campaign to a marketing list. High brand exposure and irreversible once delivered.",
    category: "Brand-critical sends",
  },
  "external.brand_critical.public_x_thread": {
    title: "Public post on X (Twitter)",
    description:
      "Public-facing post or thread on X under the Soleur brand handle. Indexed and quotable.",
    category: "Brand-critical sends",
  },
  "external.brand_critical.bluesky_reply_soleur_handle": {
    title: "Bluesky reply (Soleur handle)",
    description:
      "Reply or post from the Soleur brand account on Bluesky. Public and quotable.",
    category: "Brand-critical sends",
  },
  "external.brand_critical.slack_dm_enterprise_tier1": {
    title: "Slack DM (tier-1 enterprise contact)",
    description:
      "Direct message to a tier-1 enterprise stakeholder in Slack. Relationship-defining; treat as on-the-record.",
    category: "Brand-critical sends",
  },
  "infra.dependency_bump": {
    title: "Dependency version bump",
    description:
      "Routine dependency upgrade with passing tests. Surfaced in the next daily digest.",
    category: "Infrastructure",
  },
  "infra.log_rotate": {
    title: "Log rotation",
    description:
      "Routine log rotation and archival. Surfaced in the next daily digest.",
    category: "Infrastructure",
  },
} as const satisfies Record<ActionClass, ActionClassCopy>;

// Runtime guard for consumers that receive `actionClass` as untyped
// `string` from the Inngest/webhook surface — falls back to the raw
// value when an unknown class arrives (e.g., during a partial deploy).
export function isKnownActionClass(s: string): s is ActionClass {
  return (ACTION_CLASSES as readonly string[]).includes(s);
}

export function humanTitle(s: string): string {
  return isKnownActionClass(s) ? ACTION_CLASS_COPY[s].title : s;
}
