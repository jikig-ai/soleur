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
  isKnownActionClass,
  type ActionClass,
} from "@/server/scope-grants/action-class-map";
import { warnSilentFallback } from "@/lib/client-observability";

// Editorial category labels (Title Case, user-visible). Distinct from
// `ActionClassCategory` in `server/scope-grants/action-class-map.ts:61`,
// which is the structural taxonomy (snake_case: `finance|engineering|…`)
// used for audit-row tier labelling. Two-vocabulary design is intentional
// — structural is a code/security primitive, editorial is UI copy.
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

export type ActionClassCategoryLabel = (typeof CATEGORY_ORDER)[number];

export interface ActionClassCopy {
  title: string;
  description: string;
  category: ActionClassCategoryLabel;
}

// Re-export for ergonomic single-import consumers (audit-sections,
// today-card use both `humanTitle` and `isKnownActionClass`).
export { isKnownActionClass };

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

// Memoized category → action-classes index. Module-scope const — built
// once at import, reused by every consumer (runtime-explainer-banner,
// scope-grants/page). Shape: Map<categoryLabel, ActionClass[]> with
// CATEGORY_ORDER iteration order preserved.
export const ACTION_CLASSES_BY_CATEGORY: ReadonlyMap<
  ActionClassCategoryLabel,
  readonly ActionClass[]
> = new Map(
  CATEGORY_ORDER.map((category) => [
    category,
    ACTION_CLASSES.filter((ac) => ACTION_CLASS_COPY[ac].category === category),
  ]),
);

// Fall back to the raw value when an unknown class arrives (e.g., during
// a partial deploy where the DB CHECK enum has been widened but the web
// bundle has not). Mirrors per `cq-silent-fallback-must-mirror-to-sentry`
// so an unmapped class surfaces in Sentry instead of silently rendering
// the dotted ID to founders.
export function humanTitle(s: string): string {
  if (isKnownActionClass(s)) return ACTION_CLASS_COPY[s].title;
  warnSilentFallback(null, {
    feature: "action-class-copy",
    op: "humanTitle",
    message: "action-class-copy:unknown-class — partial deploy or registry drift",
    extra: { actionClass: s },
  });
  return s;
}
