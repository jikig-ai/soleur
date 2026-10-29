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
# TWO-PR RULE (add AND remove): see this root's README.
#
# TRIGGERS. The cron occurrence fingerprint is `crons:{monitor_env.id}`, so each
# monitor environment is ONE issue group for its whole life:
#   - first_seen_event: its first incident.
#   - regression_event: each failure after a recovery.
#   - reappeared_event: an issue archived "until escalating" escalates, i.e. the
#     cron failed again after the operator archived it (without it, archiving
#     would silence the monitor for good).
# frequency_minutes = 1441 throttles actions per group: a flapping monitor emails
# at most once per ~24 h. 1441, not 1440, follows this root's unique-frequency
# convention (issue-alerts.tf comments record a POST-time dedup keyed on action
# shape + frequency); anthropic_credit_exhausted holds 1440 with the same email
# action. Whether the workflows endpoint dedups at all is unmeasured: two groups of
# three live rules already share such a key.
# No event-frequency-count re-page, deliberately (ADR-031 #8630 amendment): a
# persistent failure emails once, at its start. The provider hard-codes
# `any-short` for the triggers, so any single one fires.
#
# Cron issues have no owners, so `issue_owners` always falls through to
# ActiveMembers (every active org member). `environment` stays unset, the root's
# convention: heartbeats post no environment, so every monitor env is `production`.
#
# Long form: ADR-031 (knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md),
# #8630 amendment.

locals {
  # label => "<reason> (#<issue>)". Declared-unrouted cron monitors.
  # Not read by any resource: it is the reviewed record Guard 1 checks against.
  cron_monitor_alert_unrouted = {
    # #9274 — added under the two-PR rule: deliberately not in
    # monitor_ids; a future PR may route it once the loop is measured. Real
    # cover meanwhile: a dead reaper lets armed bot PRs sit >48h, which
    # cron-cloud-task-heartbeat's stale-bot-PR scan (#5138) feeds
    # sentry_alert.stale_bot_pr (issue-alerts.tf) → email; the unrouted
    # monitor itself still opens a Sentry issue on failure.
    scheduled_bot_pr_reaper = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B). Supersedes the #9274 pending-route note: its stale_bot_pr cover lives under pruned cron-cloud-task-heartbeat"
    # #6931 — the web-2 soak-marker job's liveness monitor, added under the two-PR rule: the in-run
    # ci/luks-verify-web2 GitHub issue is the primary channel; route this after its first measured check-in.
    workspaces_luks_verify_web2 = "in-run ci/luks-verify-web2 GitHub issue is the primary channel; route after the first measured check-in (#9372)"
    # #10390 WS1 — the Better Stack incident mirror's liveness monitor, added under the two-PR rule:
    # the mirror's own [ci/betterstack-incident] issues are the primary channel; route after the
    # first measured check-in.
    scheduled_betterstack_incident_mirror = "the mirror's own ci/betterstack-incident GitHub issues are the primary channel; route after the first measured check-in (#10390)"
    # ---- PR-A unbind set (#6590 / feat-observability-vendor-eval): moved out of monitor_ids
    # pending the PR-B resource destroy. Never routed again — entries die with the resources.
    cron_action_required_sla            = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    cron_github_cidr_refresh            = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    cron_weekly_release_digest          = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_actions_queue_health      = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_agent_native_audit        = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_anthropic_cost_report     = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_architecture_diagram_sync = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_bug_fixer                 = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_campaign_calendar         = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_cloud_task_heartbeat      = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_community_monitor         = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_competitive_analysis      = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_compound_promote          = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_content_generator         = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_content_publisher         = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_content_vendor_drift      = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_daily_triage              = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_devin_docs_drift          = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_domain_model_drift        = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_follow_through            = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_growth_audit              = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_growth_execution          = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_integration_suites        = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_legal_audit               = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_linkedin_token_check      = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_machinery_drain           = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_nag_4216_readiness        = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_orphan_sweeps             = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_plausible_goals           = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_prod_version_drift        = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_roadmap_review            = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_rule_prune                = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_ruleset_bypass_audit      = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_seo_aeo_audit             = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_skill_freshness           = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_stale_deferred_scope_outs = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_strategy_review           = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_supabase_advisor_scan     = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_supabase_disk_io          = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_ux_audit                  = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_weekly_analytics          = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
    scheduled_workspace_gc              = "pruned per #6590 silence-doctrine + 90d catch-value; destroy lands in the follow-up PR (feat-observability-vendor-eval PR-B)"
  }
}

resource "sentry_alert" "cron_monitor_failure" {
  organization      = var.sentry_org
  name              = "cron-monitor-failure"
  enabled           = true
  frequency_minutes = 1441
  # ONE element per declared sentry_cron_monitor, minus the unrouted map, sorted.
  monitor_ids = [
    sentry_cron_monitor.cron_egress_resolve.id,
    sentry_cron_monitor.cron_email_ingress_probe.id,
    sentry_cron_monitor.cron_kb_template_health.id,
    sentry_cron_monitor.cron_workspace_sync_health.id,
    sentry_cron_monitor.image_cve_scan.id,
    sentry_cron_monitor.main_health_monitor.id,
    sentry_cron_monitor.scheduled_anthropic_credit_probe.id,
    sentry_cron_monitor.scheduled_github_app_drift_guard.id,
    sentry_cron_monitor.scheduled_heartbeat_reconcile.id,
    sentry_cron_monitor.scheduled_inngest_cron_watchdog.id,
    sentry_cron_monitor.scheduled_inngest_health.id,
    sentry_cron_monitor.scheduled_inngest_probe_heartbeat.id,
    sentry_cron_monitor.scheduled_marketplace_drift.id,
    sentry_cron_monitor.scheduled_membership_health.id,
    sentry_cron_monitor.scheduled_merge_queue_stall_dispatch.id,
    sentry_cron_monitor.scheduled_oauth_probe.id,
    sentry_cron_monitor.scheduled_realtime_probe.id,
    sentry_cron_monitor.scheduled_sentry_alert_drift.id,
    sentry_cron_monitor.scheduled_supabase_watchdog.id,
    sentry_cron_monitor.scheduled_terraform_drift.id,
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
