// Client-free cron manifest leaf (#4734).
//
// Holds the expected-cron manifest + the manual-trigger event-name derivation,
// extracted out of cron-inngest-cron-watchdog.ts so consumers can import them
// WITHOUT transitively loading @/server/inngest/client (which throws at module
// load on missing INNGEST_SIGNING_KEY outside `next build`). The watchdog
// re-exports both symbols from here, so its importers (function-registry-count,
// cron-inngest-cron-watchdog tests, oneshot-4650-monitor-close) keep working
// against the original `@/server/inngest/functions/cron-inngest-cron-watchdog`
// path unchanged.
//
// This module imports NOTHING from @/server/inngest/client — keep it that way.
// The trigger-cron route (app/api/internal/trigger-cron/route.ts) and the
// manual-trigger allowlist (lib/inngest/manual-trigger-allowlist.ts) depend on
// this leaf staying client-free.

// Expected-cron manifest — every cron-*.ts function that MUST have a live
// cron trigger. function-registry-count.test.ts (e) asserts this set equals
// the cron-*.ts file list, so it cannot silently drift. Includes the watchdog
// itself (it is a registered cron; when it runs it is planned → classifies OK;
// its own Sentry monitor is the backstop if it stops).
export const EXPECTED_CRON_FUNCTIONS: string[] = [
  "cron-agent-native-audit",
  "cron-anthropic-cost-report",
  "cron-anthropic-credit-probe",
  "cron-architecture-diagram-sync",
  "cron-bug-fixer",
  "cron-campaign-calendar",
  "cron-cloud-task-heartbeat",
  "cron-community-monitor",
  "cron-competitive-analysis",
  "cron-compound-promote",
  "cron-content-generator",
  "cron-content-publisher",
  "cron-content-vendor-drift",
  "cron-daily-triage",
  "cron-dev-migration-drift",
  "cron-domain-model-drift",
  "cron-email-ingress-probe",
  "cron-expenses-verify-by",
  "cron-follow-through-monitor",
  "cron-gh-pages-cert-state",
  "cron-ghcr-token-minter",
  "cron-github-app-drift-guard",
  "cron-github-cidr-refresh",
  "cron-growth-audit",
  "cron-growth-execution",
  "cron-inngest-cron-watchdog",
  "cron-kb-template-health",
  "cron-legal-audit",
  "cron-linkedin-token-check",
  "cron-main-health-monitor",
  "cron-membership-health",
  "cron-nag-4216-readiness",
  "cron-oauth-probe",
  "cron-plausible-goals",
  "cron-review-reminder",
  "cron-roadmap-review",
  "cron-rule-prune",
  "cron-ruleset-bypass-audit",
  "cron-seo-aeo-audit",
  "cron-skill-freshness",
  "cron-stale-deferred-scope-outs",
  "cron-strategy-review",
  "cron-supabase-advisor-scan",
  "cron-supabase-disk-io",
  "cron-terraform-drift",
  "cron-ux-audit",
  "cron-weekly-analytics",
  "cron-weekly-release-digest",
  "cron-workspace-gc",
  "cron-workspace-sync-health",
];

// fnId "cron-community-monitor" → event "cron/community-monitor.manual-trigger".
// Uniform across all cron-*.ts functions.
export function manualTriggerEventFor(fnId: string): string {
  return `cron/${fnId.replace(/^cron-/, "")}.manual-trigger`;
}
