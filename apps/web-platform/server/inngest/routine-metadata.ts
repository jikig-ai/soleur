// Client-free routine-metadata sidecar (#5345 PR-1).
//
// Display + policy metadata for each EXPECTED_CRON_FUNCTIONS cron, kept OUT of
// cron-manifest.ts so that leaf stays a bare string[] (the registry-count +
// set-equality drift guards depend on its element type — #4734). This module
// imports NOTHING from @/server/inngest/client — keep it that way so the
// dashboard routes + the manual-trigger allowlist can import it without
// triggering the INNGEST_SIGNING_KEY module-load throw outside `next build`.
//
// `routine-metadata-parity.test.ts` asserts keys === EXPECTED_CRON_FUNCTIONS,
// so adding/removing a cron forces a sidecar edit (the metadata drift guard).
//
// NO raw cron field: the cron expression's single source of truth is the
// { cron: "..." } literal inside each cron-*.ts. scheduleLabel is a
// human-readable display string only.

export interface RoutineMeta {
  /** Business domain badge, e.g. "Engineering", "Marketing". */
  domain: string;
  /** Owner-role chip, e.g. "CTO", "CMO", "COO", "CLO". */
  ownerRole: string;
  /** Human-readable schedule, e.g. "Daily 04:00 UTC". Display only. */
  scheduleLabel: string;
  /**
   * Manual-trigger policy (deny-by-default for protected routines):
   * - "allowed": fires immediately on Run-now.
   * - "confirm": protected (financial / external-egress / deletion) — requires
   *   explicit confirmation (UI modal) or `confirmed:true` from runRoutine.
   * (No "denied" level in v1 — event-driven fns are excluded by the
   * fnId ∈ EXPECTED_CRON_FUNCTIONS membership check, not a policy level.)
   */
  manualTrigger: "allowed" | "confirm";
}

export const ROUTINE_METADATA: Record<string, RoutineMeta> = {
  "cron-agent-native-audit": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Monthly · 15th 09:00 UTC", manualTrigger: "allowed" },
  "cron-bug-fixer": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Daily 06:00 UTC", manualTrigger: "confirm" },
  "cron-campaign-calendar": { domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Weekly · Mon 16:00 UTC", manualTrigger: "allowed" },
  "cron-cloud-task-heartbeat": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Daily 09:30 UTC", manualTrigger: "allowed" },
  "cron-community-monitor": { domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Daily 08:00 UTC", manualTrigger: "allowed" },
  "cron-competitive-analysis": { domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Monthly · 1st 09:00 UTC", manualTrigger: "allowed" },
  "cron-compound-promote": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Weekly · Sun 00:00 UTC", manualTrigger: "allowed" },
  "cron-content-generator": { domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Tue & Thu 10:00 UTC", manualTrigger: "allowed" },
  "cron-content-publisher": { domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Daily 14:00 UTC", manualTrigger: "confirm" },
  "cron-content-vendor-drift": { domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Weekly · Mon 11:17 UTC", manualTrigger: "confirm" },
  "cron-daily-triage": { domain: "Operations", ownerRole: "COO", scheduleLabel: "Daily 04:00 UTC", manualTrigger: "allowed" },
  "cron-dev-migration-drift": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Every 6h (:15)", manualTrigger: "allowed" },
  "cron-email-ingress-probe": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Daily 06:00 UTC", manualTrigger: "allowed" },
  "cron-follow-through-monitor": { domain: "Operations", ownerRole: "COO", scheduleLabel: "Weekdays 09:00 UTC", manualTrigger: "allowed" },
  "cron-gh-pages-cert-state": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Daily 03:00 UTC", manualTrigger: "allowed" },
  "cron-github-app-drift-guard": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Hourly", manualTrigger: "confirm" },
  "cron-github-cidr-refresh": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Daily 06:41 UTC", manualTrigger: "allowed" },
  "cron-growth-audit": { domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Weekly · Mon 07:00 UTC", manualTrigger: "allowed" },
  "cron-growth-execution": { domain: "Marketing", ownerRole: "CMO", scheduleLabel: "1st & 15th 10:00 UTC", manualTrigger: "confirm" },
  "cron-inngest-cron-watchdog": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Every 4h", manualTrigger: "allowed" },
  "cron-kb-template-health": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Hourly", manualTrigger: "allowed" },
  "cron-legal-audit": { domain: "Legal", ownerRole: "CLO", scheduleLabel: "Quarterly · 1st 11:00 UTC", manualTrigger: "confirm" },
  "cron-linkedin-token-check": { domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Weekly · Mon 11:00 UTC", manualTrigger: "allowed" },
  "cron-main-health-monitor": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Every 6h", manualTrigger: "allowed" },
  "cron-membership-health": { domain: "Operations", ownerRole: "COO", scheduleLabel: "Hourly (:17)", manualTrigger: "allowed" },
  "cron-nag-4216-readiness": { domain: "Operations", ownerRole: "COO", scheduleLabel: "Weekly · Mon 14:00 UTC", manualTrigger: "allowed" },
  "cron-oauth-probe": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Hourly", manualTrigger: "allowed" },
  "cron-plausible-goals": { domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Monthly · 1st 07:00 UTC", manualTrigger: "allowed" },
  "cron-review-reminder": { domain: "Operations", ownerRole: "COO", scheduleLabel: "Monthly · 1st 00:00 UTC", manualTrigger: "allowed" },
  "cron-roadmap-review": { domain: "Operations", ownerRole: "COO", scheduleLabel: "Weekly · Mon 09:00 UTC", manualTrigger: "allowed" },
  "cron-rule-prune": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Quarterly · 1st 09:00 UTC", manualTrigger: "allowed" },
  "cron-ruleset-bypass-audit": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Daily 06:13 UTC", manualTrigger: "allowed" },
  "cron-seo-aeo-audit": { domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Weekly · Mon 11:00 UTC", manualTrigger: "allowed" },
  "cron-skill-freshness": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Monthly · 1st 02:00 UTC", manualTrigger: "allowed" },
  "cron-stale-deferred-scope-outs": { domain: "Operations", ownerRole: "COO", scheduleLabel: "Daily 12:00 UTC", manualTrigger: "allowed" },
  "cron-strategy-review": { domain: "Operations", ownerRole: "COO", scheduleLabel: "Weekly · Mon 08:00 UTC", manualTrigger: "allowed" },
  "cron-supabase-disk-io": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Every 6h", manualTrigger: "allowed" },
  "cron-terraform-drift": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Twice daily 06:00 & 18:00 UTC", manualTrigger: "confirm" },
  "cron-ux-audit": { domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Monthly · 1st 09:00 UTC", manualTrigger: "allowed" },
  "cron-weekly-analytics": { domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Weekly · Mon 06:00 UTC", manualTrigger: "allowed" },
  "cron-weekly-release-digest": { domain: "Operations", ownerRole: "COO", scheduleLabel: "Weekly · Fri 15:00 UTC", manualTrigger: "allowed" },
  "cron-workspace-gc": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Every 6h", manualTrigger: "confirm" },
  "cron-workspace-sync-health": { domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Daily 06:23 UTC", manualTrigger: "allowed" },
};
