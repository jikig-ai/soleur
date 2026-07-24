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
// It also asserts every entry has a non-empty `description` (#5424) — a new
// cron cannot be added without explaining what it does.
//
// NO raw cron field: the cron expression's single source of truth is the
// { cron: "..." } literal inside each cron-*.ts. scheduleLabel is a
// human-readable display string only.

export interface RoutineMeta {
  /**
   * One-sentence, user-facing explanation of what the routine does and what
   * it's for (shown on the dashboard routine row + detail drawer, and returned
   * by the `routines_list` agent tool). REQUIRED — a new cron cannot be added
   * without one (the `routine-metadata-parity.test.ts` description guard + this
   * non-optional field enforce it). Keep it plain-language, 10–160 chars.
   */
  description: string;
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
  "cron-action-required-sla": { description: "Weekly staleness contract for the action-required queue: escalates aging ops asks and auto-expires dead chores (fail-safe, never closes an ops ask).", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Weekly · Fri 12:00 UTC", manualTrigger: "allowed" },
  "cron-agent-native-audit": { description: "Audits the codebase for agent-native architecture violations and files scored findings as GitHub issues.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Monthly · 15th 09:00 UTC", manualTrigger: "allowed" },
  "cron-anthropic-cost-report": { description: "Daily pull of the Anthropic Admin cost & usage API; emits an authoritative per-model + org-total spend marker to Better Stack.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Daily (06:17 UTC)", manualTrigger: "allowed" },
  "cron-anthropic-credit-probe": { description: "Hourly 1-token canary on the operator Anthropic API key; pages Sentry when credit is exhausted or the key is invalid.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Hourly (:47)", manualTrigger: "allowed" },
  "cron-architecture-diagram-sync": { description: "Weekly review of C4 architecture diagrams against the codebase; updates stale diagrams and files a drift report as a GitHub issue.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Weekly · Sun 02:00 UTC", manualTrigger: "allowed" },
  "cron-bug-fixer": { description: "Autonomously fixes low-priority bugs each morning; auto-merges safe single-file fixes when CI passes.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Daily 06:00 UTC", manualTrigger: "confirm" },
  "cron-campaign-calendar": { description: "Refreshes the marketing campaign calendar and flags overdue distribution content for publishing.", domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Weekly · Mon 16:00 UTC", manualTrigger: "allowed" },
  "cron-cloud-task-heartbeat": { description: "Daily liveness check for all scheduled cloud tasks; warns when one goes silent or a bot PR goes stale.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Daily 09:30 UTC", manualTrigger: "allowed" },
  "cron-community-monitor": { description: "Posts a daily digest of community activity across GitHub, Discord, X, LinkedIn, Bluesky and HN.", domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Daily 08:00 UTC", manualTrigger: "allowed" },
  "cron-competitive-analysis": { description: "Monthly competitor analysis; cascades findings into strategy docs and sales battlecards.", domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Monthly · 1st 09:00 UTC", manualTrigger: "allowed" },
  "cron-compound-promote": { description: "Clusters knowledge-base learnings weekly and proposes consolidations into AGENTS.md and skills.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Weekly · Sun 00:00 UTC", manualTrigger: "allowed" },
  "cron-content-generator": { description: "Twice-weekly auto-generation of SEO content from the queue, validated in CI, with distribution copy.", domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Tue & Thu 10:00 UTC", manualTrigger: "allowed" },
  "cron-content-publisher": { description: "Publishes scheduled distribution content daily to Discord, X, LinkedIn and Bluesky.", domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Daily 14:00 UTC", manualTrigger: "confirm" },
  "cron-content-vendor-drift": { description: "Detects upstream drift in third-party skills weekly; opens PRs for low-risk changes, issues for security.", domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Weekly · Mon 11:17 UTC", manualTrigger: "confirm" },
  "cron-daily-triage": { description: "Triages open GitHub issues each morning, classifying them by priority, type and domain.", domain: "Operations", ownerRole: "COO", scheduleLabel: "Daily 04:00 UTC", manualTrigger: "allowed" },
  "cron-dev-migration-drift": { description: "Checks the dev database every 6 hours for schema migration drift.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Every 6h (:15)", manualTrigger: "allowed" },
  "cron-domain-model-drift": { description: "Weekly check that the domain-model register cites no unresolvable source; files an idempotent GitHub issue when a stale citation is found.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Weekly (Mon 08:00 UTC)", manualTrigger: "allowed" },
  "cron-email-ingress-probe": { description: "Daily email-ingress SLA probe; purges old triage items and pings as deadlines approach.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Daily 06:00 UTC", manualTrigger: "allowed" },
  "cron-expenses-verify-by": { description: "Weekly check that no estimate row in the expense ledger has outlived its verify_by date; files an idempotent GitHub issue when one has.", domain: "Finance", ownerRole: "CFO", scheduleLabel: "Weekly (Mon 08:00 UTC)", manualTrigger: "allowed" },
  "cron-follow-through-monitor": { description: "Verifies open follow-through commitments each weekday via live probes and flags overdue ones.", domain: "Operations", ownerRole: "COO", scheduleLabel: "Weekdays 09:00 UTC", manualTrigger: "allowed" },
  "cron-gh-pages-cert-reissue": { description: "Event-triggered remediation for a stuck (bad_authz) GitHub Pages cert: transiently flips apex+www to DNS-only and re-orders the cert, then restores.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Event-triggered (reissue remediation)", manualTrigger: "confirm" },
  "cron-gh-pages-cert-state": { description: "Polls the GitHub Pages TLS certificate daily; warns ~21 days before expiry and pages on errors.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Daily 03:00 UTC", manualTrigger: "allowed" },
  "cron-ghcr-token-minter": { description: "Mints a 1h packages:read GitHub App installation token every 20 min and writes it to Doppler for private-GHCR host pulls (ADR-088).", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Every 20 min", manualTrigger: "confirm" },
  "cron-github-app-drift-guard": { description: "Hourly check for GitHub App auth/permission drift; guards against token leaks via tripwire patterns.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Hourly", manualTrigger: "confirm" },
  "cron-github-cidr-refresh": { description: "Refreshes the GitHub egress IP allowlist from /meta daily and self-heals the firewall on rotation.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Daily 06:41 UTC", manualTrigger: "allowed" },
  "cron-growth-audit": { description: "Weekly audit of website content quality, AEO and technical SEO; files an action plan and issues.", domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Weekly · Mon 07:00 UTC", manualTrigger: "allowed" },
  "cron-growth-execution": { description: "Applies queued keyword optimizations to stale priority pages twice a month.", domain: "Marketing", ownerRole: "CMO", scheduleLabel: "1st & 15th 10:00 UTC", manualTrigger: "confirm" },
  "cron-inngest-config-drift": { description: "Compares the Inngest host's applied config digest vs the promoted pointer and alarms on drift (ADR-135); dormant until the #6178 cutover.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Dormant until #6178 cutover (event-only)", manualTrigger: "confirm" },
  "cron-inngest-cron-watchdog": { description: "Liveness beacon every 4 hours — its own check-in proves the Inngest cron scheduler is alive.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Every 4h", manualTrigger: "allowed" },
  "cron-kb-template-health": { description: "Hourly health probe of the knowledge-base template endpoint; files a P1 ops issue on drift.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Hourly", manualTrigger: "allowed" },
  "cron-legal-audit": { description: "Quarterly legal/compliance audit of the codebase and site content; files findings as GitHub issues.", domain: "Legal", ownerRole: "CLO", scheduleLabel: "Quarterly · 1st 11:00 UTC", manualTrigger: "confirm" },
  "cron-linkedin-token-check": { description: "Checks the LinkedIn OAuth token weekly and files an issue if it has expired (HTTP 401).", domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Weekly · Mon 11:00 UTC", manualTrigger: "allowed" },
  "cron-main-health-monitor": { description: "Triggers the main-branch health-check workflow every 6 hours.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Every 6h", manualTrigger: "allowed" },
  "cron-membership-health": { description: "Hourly team-membership health probe; files a P0 incident when the health endpoint reports degraded.", domain: "Operations", ownerRole: "COO", scheduleLabel: "Hourly (:17)", manualTrigger: "allowed" },
  "cron-nag-4216-readiness": { description: "Posts a weekly reminder comment on issue #4216 (PR-I readiness) while it stays open.", domain: "Operations", ownerRole: "COO", scheduleLabel: "Weekly · Mon 14:00 UTC", manualTrigger: "allowed" },
  "cron-oauth-probe": { description: "Synthetic OAuth sign-in probe (GitHub, Google) run hourly; files an issue on timeout or failure.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Hourly", manualTrigger: "allowed" },
  "cron-plausible-goals": { description: "Idempotently provisions Plausible Analytics conversion goals each month.", domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Monthly · 1st 07:00 UTC", manualTrigger: "allowed" },
  "cron-review-reminder": { description: "Triggers the monthly pull-request review-reminder workflow.", domain: "Operations", ownerRole: "COO", scheduleLabel: "Monthly · 1st 00:00 UTC", manualTrigger: "allowed" },
  "cron-roadmap-review": { description: "Reviews the product roadmap weekly for staleness, updates its frontmatter and files findings.", domain: "Operations", ownerRole: "COO", scheduleLabel: "Weekly · Mon 09:00 UTC", manualTrigger: "allowed" },
  "cron-rule-prune": { description: "Quarterly prune of AGENTS.md hard rules idle 26+ weeks; opens a PR proposing retirements.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Quarterly · 1st 09:00 UTC", manualTrigger: "allowed" },
  "cron-ruleset-bypass-audit": { description: "Daily audit of bypass actors + required checks on the GitHub 'CI Required' and 'CLA Required' rulesets; files a compliance issue on drift.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Daily 06:13 UTC", manualTrigger: "allowed" },
  "cron-seo-aeo-audit": { description: "Weekly SEO and accessibility audit of the site; generates reports and actionable GitHub issues.", domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Weekly · Mon 11:00 UTC", manualTrigger: "allowed" },
  "cron-skill-freshness": { description: "Monthly skill-usage aggregator; files issues for idle (180d+) or archival-ready (365d+) skills.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Monthly · 1st 02:00 UTC", manualTrigger: "allowed" },
  "cron-stale-deferred-scope-outs": { description: "Sweeps deferred-scope-out issues daily and closes those with no activity for 90+ days.", domain: "Operations", ownerRole: "COO", scheduleLabel: "Daily 12:00 UTC", manualTrigger: "allowed" },
  "cron-strategy-review": { description: "Reviews knowledge-base strategy docs weekly and files an issue listing overdue ones for re-review.", domain: "Operations", ownerRole: "COO", scheduleLabel: "Weekly · Mon 08:00 UTC", manualTrigger: "allowed" },
  "cron-supabase-advisor-scan": { description: "Nightly gate asserting no table in a Supabase public schema is missing row-level security.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Daily 03:37 UTC", manualTrigger: "confirm" },
  "cron-supabase-disk-io": { description: "Early-warning monitor for production Supabase disk-IO pressure; files an issue when thresholds hit.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Every 6h", manualTrigger: "allowed" },
  "cron-terraform-drift": { description: "Triggers the Terraform infrastructure drift-detection workflow twice a day.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Twice daily 06:00 & 18:00 UTC", manualTrigger: "confirm" },
  "cron-ux-audit": { description: "Monthly UX audit driven by Playwright functional tests; uploads findings to Supabase.", domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Monthly · 1st 09:00 UTC", manualTrigger: "allowed" },
  "cron-weekly-analytics": { description: "Captures a weekly Plausible metrics snapshot as a PR and cascades when a KPI is missed.", domain: "Marketing", ownerRole: "CMO", scheduleLabel: "Weekly · Mon 06:00 UTC", manualTrigger: "allowed" },
  "cron-weekly-release-digest": { description: "Curates the week's GitHub Releases into a sanitized digest and posts it to Discord on Fridays.", domain: "Operations", ownerRole: "COO", scheduleLabel: "Weekly · Fri 15:00 UTC", manualTrigger: "allowed" },
  "cron-workspace-gc": { description: "Cleans up leaked ephemeral cron-clone directories from the shared workspace volume every 6 hours.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Every 6h", manualTrigger: "confirm" },
  "cron-workspace-sync-health": { description: "Daily read-only scan that reports unreachable workspace rows (missing GitHub install) to Sentry.", domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Daily 06:23 UTC", manualTrigger: "allowed" },
};
