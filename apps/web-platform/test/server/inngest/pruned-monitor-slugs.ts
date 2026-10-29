// 2026-10-29 — #6590 silence-doctrine prune (feat-observability-vendor-eval
// PR-B): the 43 sentry_cron_monitor resources this set names were DESTROYED,
// but their producers were deliberately NOT stripped (archived spec
// feat-observability-vendor-eval NG4 — "re-pointing or rewriting any emit
// path" is out of scope). Sentry drops check-ins posted to unknown slugs, so
// the 35 Inngest `SENTRY_MONITOR_SLUG` consts + 8 workflow `monitor-slug:`
// params below keep posting into the void BY DESIGN — the deliberate
// void-post posture, not the #6374 gap the strict guards exist to catch.
//
// This is the single shared exemption for FIVE consumers: the three strict
// vitest guards (sentry-monitor-iac-parity.test.ts code→IaC + workflow→IaC,
// and function-registry-count.test.ts guard (c)) plus two shell suites that
// regex the file bytes — prod-version-drift-check.test.sh B10g and
// token-drift-workflow-causes.test.sh R10. FORMAT CONTRACT (load-bearing for
// the shell consumers): entries are one `"kebab-slug"` literal per line
// inside `new Set([…])`, and a quoted kebab token must NEVER appear in a
// comment — the shell parses anchor on `^\s*"slug",?\s*$` but a slug quoted
// inside comment prose is still one careless edit away from silently
// exempting a live monitor. It can never rot while the stale-set assertions
// hold: an entry naming a monitor that still exists is caught by `PRUNED ∩
// declared = ∅`, and an entry naming no live producer (typo, retired
// emitter, re-added monitor) is caught by `PRUNED ⊆ producers`.
//
// Vendor dependency the void-post rests on (recorded, not enforced):
// Sentry's check-in ingest must keep answering 2xx for unknown slugs —
// ~29 void-posts/day across the 43 emitters would become `op:fetch` error
// events if the vendor ever flipped to 4xx (≈870/mo against a 50K reserved
// error quota — cheap, but noisy).
//
// Re-monitoring a slug = delete its entry here, re-declare the
// sentry_cron_monitor block, and re-route it per the two-PR rule in
// apps/web-platform/infra/sentry/README.md.
export const PRUNED_MONITOR_SLUGS = new Set([
  "cron-action-required-sla",
  "cron-github-cidr-refresh",
  "cron-weekly-release-digest",
  "scheduled-actions-queue-health",
  "scheduled-agent-native-audit",
  "scheduled-anthropic-cost-report",
  "scheduled-architecture-diagram-sync",
  "scheduled-bot-pr-reaper",
  "scheduled-bug-fixer",
  "scheduled-campaign-calendar",
  "scheduled-cloud-task-heartbeat",
  "scheduled-community-monitor",
  "scheduled-competitive-analysis",
  "scheduled-compound-promote",
  "scheduled-content-generator",
  "scheduled-content-publisher",
  "scheduled-content-vendor-drift",
  "scheduled-daily-triage",
  "scheduled-devin-docs-drift",
  "scheduled-domain-model-drift",
  "scheduled-follow-through",
  "scheduled-growth-audit",
  "scheduled-growth-execution",
  "scheduled-integration-suites",
  "scheduled-legal-audit",
  "scheduled-linkedin-token-check",
  "scheduled-machinery-drain",
  "scheduled-nag-4216-readiness",
  "scheduled-orphan-sweeps",
  "scheduled-plausible-goals",
  "scheduled-prod-version-drift",
  "scheduled-roadmap-review",
  "scheduled-rule-prune",
  "scheduled-ruleset-bypass-audit",
  "scheduled-seo-aeo-audit",
  "scheduled-skill-freshness",
  "scheduled-stale-deferred-scope-outs",
  "scheduled-strategy-review",
  "scheduled-supabase-advisor-scan",
  "scheduled-supabase-disk-io",
  "scheduled-ux-audit",
  "scheduled-weekly-analytics",
  "scheduled-workspace-gc",
]);
