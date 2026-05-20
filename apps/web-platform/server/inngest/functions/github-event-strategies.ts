// PR-H (#3244) Phase 4 — per-event-class strategy table for the single
// github-on-event Inngest function. Plan-review consensus (DHH + Kieran
// + code-simplicity): the 4 event classes share ~90% of the
// schema-gate → verify-state → BYOK lease → redact → persist-draft
// pipeline. Per-class deltas are encoded here so the dispatcher is
// pattern-matched, not branched.

import type { RedactionSource } from "@/lib/safety/redaction-allowlist";

export type GitHubActionClass =
  | "engineering.pr_review_pending"
  | "engineering.ci_failed"
  | "triage.p0p1_issue"
  | "security.cve_alert";

export type OwningDomain = "engineering" | "product" | "security" | "triage";

export type Urgency = "critical" | "high" | "normal" | "low";

export interface GitHubEventStrategy {
  /** Domain that owns the draft (engineering / product / security / triage). */
  owningDomain: OwningDomain | ((body: unknown) => OwningDomain);
  /** Prefix used to build messages.source_ref for dedup at the partial-unique index. */
  sourceRefPrefix: string;
  /** Card urgency at write time (post-ranking sort key, Phase 6 inline ranking). */
  urgency: Urgency;
  /** Source variant for redactGithubSourcedText — selects the right golden-fixture profile. */
  redactSource: RedactionSource;
}

// Type-narrowing helper for the issue-label routing: `triage.p0p1_issue`
// → product if label is `type/feature`; engineering otherwise. The
// label list is inside the webhook body (`issue.labels[].name`).
function isIssueBodyWithFeatureLabel(body: unknown): boolean {
  if (typeof body !== "object" || body === null) return false;
  const issue = (body as { issue?: { labels?: Array<{ name?: string }> } }).issue;
  if (!issue || !Array.isArray(issue.labels)) return false;
  return issue.labels.some((l) => l?.name === "type/feature");
}

export const GITHUB_EVENT_STRATEGIES: Record<GitHubActionClass, GitHubEventStrategy> = {
  "engineering.pr_review_pending": {
    owningDomain: "engineering",
    sourceRefPrefix: "pr-",
    urgency: "normal",
    redactSource: "pr_title",
  },
  "engineering.ci_failed": {
    owningDomain: "engineering",
    sourceRefPrefix: "ci-",
    urgency: "high",
    redactSource: "pr_title",
  },
  "triage.p0p1_issue": {
    owningDomain: (body) => (isIssueBodyWithFeatureLabel(body) ? "product" : "engineering"),
    sourceRefPrefix: "issue-",
    urgency: "critical",
    redactSource: "issue_body",
  },
  "security.cve_alert": {
    owningDomain: "security",
    sourceRefPrefix: "cve-",
    urgency: "critical",
    redactSource: "cve_description",
  },
};

/**
 * Resolve owningDomain for an action class given the raw event body.
 * Centralizes the label-routing branch so the dispatcher stays
 * pattern-matched.
 */
export function resolveOwningDomain(
  actionClass: GitHubActionClass,
  body: unknown,
): OwningDomain {
  const strategy = GITHUB_EVENT_STRATEGIES[actionClass];
  return typeof strategy.owningDomain === "function"
    ? strategy.owningDomain(body)
    : strategy.owningDomain;
}

export function isKnownGitHubActionClass(s: string): s is GitHubActionClass {
  return s in GITHUB_EVENT_STRATEGIES;
}
