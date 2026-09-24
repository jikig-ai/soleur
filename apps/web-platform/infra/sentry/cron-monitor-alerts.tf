# Email route for Sentry cron-monitor failures (#8630).
#
# Every `sentry_cron_monitor` in this root (cron-monitors.tf today) opens a Sentry
# issue when a check-in is missed or fails. Before this file no alert workflow was
# bound to any cron detector, so those issues emailed nobody. This one
# `sentry_alert` binds every declared cron monitor and emails the org.
#
# ROUTING RULE (Guard 1, test/server/inngest/sentry-cron-monitor-routing-parity.test.ts):
# each declared cron monitor is EITHER an element of the alert's id list below
# (as `sentry_cron_monitor.<label>.id`) OR a key of the unrouted map in `locals`
# with a "<reason> (#N)" value -- never both, never neither. Derive the list, never
# hand-type it:
#   grep -hoE '^resource "sentry_cron_monitor" "[a-z0-9_]+"' apps/web-platform/infra/sentry/*.tf | awk -F'"' '{print $4}' | LC_ALL=C sort
#
# TWO-PR RULE: a monitor created in a PR has no detector id at plan time, so it
# cannot be routed in the same apply (the projection floor refuses it). Declare it
# in PR 1 and list it in the unrouted map; route it in PR 2 after the first apply.
#
# TRIGGERS. The cron occurrence fingerprint is `crons:{monitor_env.id}`, so each
# monitor environment is ONE issue group for its whole life:
#   - first_seen_event: its first incident.
#   - regression_event: each failure after a recovery.
#   - reappeared_event: an issue archived "until escalating" escalates, i.e. the
#     cron failed again after the operator archived it (without it, archiving
#     would silence the monitor for good).
# frequency_minutes = 1440 throttles actions per group: a flapping monitor emails
# at most once per 24 h. No event-frequency-count re-page, deliberately: it would
# email every chronically-red monitor daily from day one. A persistent failure
# emails once, at its start; Sentry's own broken-monitor (14 d) and mute (~28 d)
# notices are the long-outage reminder. A monitor already red at apply time stays
# silent until its next regression. The provider hard-codes `any-short` for the
# triggers, so any single one fires.
#
# Cron issues have no owners, so `issue_owners` always falls through to
# ActiveMembers (every active org member). `environment` stays unset, the root's
# convention: heartbeats post no environment, so every monitor env is `production`.
#
# Long form: ADR-031 (knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md)
# and knowledge-base/project/plans/2026-09-24-feat-route-cron-monitor-failures-to-email-alert-plan.md.

locals {
  # label => "<reason> (#<issue>)". Declared-unrouted cron monitors. EMPTY at merge.
  # Not read by any resource: it is the reviewed record Guard 1 checks against.
  cron_monitor_alert_unrouted = {}
}

resource "sentry_alert" "cron_monitor_failure" {
  organization      = var.sentry_org
  name              = "cron-monitor-failure"
  enabled           = true
  frequency_minutes = 1440
  # ONE element per declared sentry_cron_monitor, minus the unrouted map, sorted.
  monitor_ids = [
    sentry_cron_monitor.cron_action_required_sla.id,
    sentry_cron_monitor.cron_egress_resolve.id,
    sentry_cron_monitor.cron_email_ingress_probe.id,
    sentry_cron_monitor.cron_github_cidr_refresh.id,
    sentry_cron_monitor.cron_kb_template_health.id,
    sentry_cron_monitor.cron_weekly_release_digest.id,
    sentry_cron_monitor.cron_workspace_sync_health.id,
    sentry_cron_monitor.main_health_monitor.id,
    sentry_cron_monitor.scheduled_actions_queue_health.id,
    sentry_cron_monitor.scheduled_agent_native_audit.id,
    sentry_cron_monitor.scheduled_anthropic_cost_report.id,
    sentry_cron_monitor.scheduled_anthropic_credit_probe.id,
    sentry_cron_monitor.scheduled_architecture_diagram_sync.id,
    sentry_cron_monitor.scheduled_bug_fixer.id,
    sentry_cron_monitor.scheduled_campaign_calendar.id,
    sentry_cron_monitor.scheduled_cloud_task_heartbeat.id,
    sentry_cron_monitor.scheduled_community_monitor.id,
    sentry_cron_monitor.scheduled_competitive_analysis.id,
    sentry_cron_monitor.scheduled_compound_promote.id,
    sentry_cron_monitor.scheduled_content_generator.id,
    sentry_cron_monitor.scheduled_content_publisher.id,
    sentry_cron_monitor.scheduled_content_vendor_drift.id,
    sentry_cron_monitor.scheduled_daily_triage.id,
    sentry_cron_monitor.scheduled_devin_docs_drift.id,
    sentry_cron_monitor.scheduled_domain_model_drift.id,
    sentry_cron_monitor.scheduled_follow_through.id,
    sentry_cron_monitor.scheduled_gh_pages_cert_state.id,
    sentry_cron_monitor.scheduled_github_app_drift_guard.id,
    sentry_cron_monitor.scheduled_growth_audit.id,
    sentry_cron_monitor.scheduled_growth_execution.id,
    sentry_cron_monitor.scheduled_heartbeat_reconcile.id,
    sentry_cron_monitor.scheduled_inngest_cron_watchdog.id,
    sentry_cron_monitor.scheduled_inngest_health.id,
    sentry_cron_monitor.scheduled_legal_audit.id,
    sentry_cron_monitor.scheduled_linkedin_token_check.id,
    sentry_cron_monitor.scheduled_machinery_drain.id,
    sentry_cron_monitor.scheduled_marketplace_drift.id,
    sentry_cron_monitor.scheduled_membership_health.id,
    sentry_cron_monitor.scheduled_nag_4216_readiness.id,
    sentry_cron_monitor.scheduled_oauth_probe.id,
    sentry_cron_monitor.scheduled_plausible_goals.id,
    sentry_cron_monitor.scheduled_prod_version_drift.id,
    sentry_cron_monitor.scheduled_realtime_probe.id,
    sentry_cron_monitor.scheduled_roadmap_review.id,
    sentry_cron_monitor.scheduled_rule_prune.id,
    sentry_cron_monitor.scheduled_ruleset_bypass_audit.id,
    sentry_cron_monitor.scheduled_sentry_alert_drift.id,
    sentry_cron_monitor.scheduled_seo_aeo_audit.id,
    sentry_cron_monitor.scheduled_skill_freshness.id,
    sentry_cron_monitor.scheduled_stale_deferred_scope_outs.id,
    sentry_cron_monitor.scheduled_strategy_review.id,
    sentry_cron_monitor.scheduled_supabase_advisor_scan.id,
    sentry_cron_monitor.scheduled_supabase_disk_io.id,
    sentry_cron_monitor.scheduled_terraform_drift.id,
    sentry_cron_monitor.scheduled_ux_audit.id,
    sentry_cron_monitor.scheduled_weekly_analytics.id,
    sentry_cron_monitor.scheduled_workspace_gc.id,
    sentry_cron_monitor.workspaces_luks_verify.id,
    sentry_cron_monitor.zot_restart_loop_alarm.id,
  ]

  trigger_conditions = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = []
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}
