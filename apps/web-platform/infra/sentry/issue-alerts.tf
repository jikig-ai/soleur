# Sentry alerting for the web-platform project.
#
# ADOPTED (#7650 Phase 2, 2026-09-04): 27 of the 29 rules are now managed as
# `sentry_alert`, the non-deprecated resource. Two remain on the deprecated
# `sentry_issue_alert` because the provider cannot express their trigger:
# `auth-per-user-loop` and `sandbox-startup-failure` both use
# `event_unique_user_frequency_count`, which v0.15.7's `trigger_conditions`
# does not offer (verified against the provider schema at the pinned tag, not
# a changelog — upstream jianyuan/terraform-provider-sentry issue 950).
#
# NAMES ARE LOAD-BEARING. `apps/web-platform/scripts/assert-byok-rules-exist.sh`
# EXPECTED_RULES and the operator dashboard queries both key on the `name`
# string. Preserve every byte.
#
# AUTHORING SOURCE. The 27 blocks below were generated from the committed live
# capture `knowledge-base/project/specs/fix-7650-sentry-alert-migration/
# phase2-live-workflows-capture-2026-09-04.json` — never from this file's own
# prior contents and never from configure-sentry-alerts.sh. Measured
# 2026-09-04: that script writes `frequency 60` for all three auth burst rules
# while live carries 60/61/62, so it is a drift source, not a source of truth.
# See phase2-measurements-2026-09-04.md.
#
# ADOPTION MECHANISM. Each rule carries a paired `removed{}` (forget the
# `sentry_issue_alert` address without destroying the live object) and
# `import{}` (adopt the same live object at the `sentry_alert` address). Both
# land in ONE merge; there is no out-of-band state surgery.
#   - `removed{}` with `destroy = false` is refresh-free: measured on Terraform
#     v1.10.5, a forget emits ZERO "Refreshing state..." lines against one for a
#     managed block, so it never touches the deprecated `rules/` endpoint
#     (HashiCorp PR 35458, `node_resource_plan_orphan.go`: `!n.skipRefresh && !forget`).
#   - `import{}` is idempotent — re-importing an already-managed address is a
#     documented no-op — and plans as `no-op` + `importing`, never as `create`.
#   - The 27 `import{}`/`removed{}` blocks stay in config until AC15-AC22 pass
#     on `main`. Removing an `import{}` for an address that was NOT actually
#     imported turns it into a planned CREATE of a live-colliding paging rule.
#
# TRIGGER LOGIC IS HARDCODED BY THE PROVIDER. `sentry_alert` exposes no
# `logic_type` on `trigger_conditions` -- it always applies `any-short`. That is
# semantics-preserving for all 27: measured 2026-09-04, every in-scope rule whose
# live `logicType` is "all" carries exactly ONE trigger condition, where `all` and
# `any-short` are identical, and zero rules have both multiple conditions and a
# non-any-short logic type. Had even one, adoption would have silently WIDENED a
# live paging trigger. Do not add a multi-condition trigger here without
# re-checking that. (Stated once: a per-block copy on 27 of 27 blocks is
# boilerplate, and the plan's own Cut List rejects markers that ship
# pre-suppressed for exactly that reason.)
#
# `ignore_changes = [environment]` on every block: no block SETS `environment`
# and all 27 are live-null, so this defends against an out-of-band UI edit
# binding a rule to an environment, not against config drift. It is deliberately
# the ONLY ignored attribute -- the wide `ignore_changes` the legacy blocks
# carried is what made Terraform not own their filters (see
# assert-byok-rules-exist.sh and the 2026-08-19 learning).
#
# THREE RESOURCE LABELS ARE NOT MECHANICAL derivations of their live name:
#   cron-egress-blocked            -> egress_blocked
#   web-host-private-nic-boot-gate -> web_private_nic_boot_gate
#   web-host-terminal-boot-fatal   -> web_terminal_boot_fatal
# These are historical aliases inherited from the `sentry_issue_alert` blocks
# this migration replaces. Being precise about why they are kept, because the
# obvious justification is wrong for half of it: the alias is FORCED only on the
# `removed{}` from-addresses, which must match the addresses already in state.
# The new `sentry_alert` labels were free to choose. They match the aliases so
# that a rule's three blocks (resource / removed / import) share one label and
# the forget<->import bijection is readable by eye. Once this config is applied
# the `sentry_alert` labels ARE state, and renaming one then IS a Terraform
# address change -- a destroy+create of a live paging rule. So: free to change
# before the first apply, load-bearing after it. Do not "tidy" them.
#
# Note the three runs below are sorted by LIVE RULE NAME, not by label, so
# `egress_blocked` sits under `cron-egress-blocked` between
# `container_restart_burst` and `disk_io_wal_concentration`. That is consistent
# across all three runs and is not a sort bug.
#
# A CLEAN PLAN IS NOT EVIDENCE THE DEPRECATION LIFTED. The two survivors still
# read through the deprecated endpoint, so a green plan may simply mean it ran
# outside a brownout window. The brownout retry in apply-sentry-infra.yml STAYS
# until zero `sentry_issue_alert` resources remain (Phase 3.4, blocked on 950).

data "sentry_project_issue_stream_monitor" "web_platform" {
  organization = var.sentry_org
  project      = var.sentry_project
  first        = true
}

# --------------------------------------------------------------------------
# The two rules that CANNOT migrate: event_unique_user_frequency_count is
# absent from trigger_conditions at v0.15.7 (upstream issue 950).
# --------------------------------------------------------------------------

resource "sentry_issue_alert" "auth_per_user_loop" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "auth-per-user-loop"
  action_match = "all"
  filter_match = "all"
  frequency    = 30

  # Provider schema requires actions_v2 ≥ 1 at config-time even for
  # imported resources. The placeholder is overwritten by import; lifecycle
  # ignore_changes (below) keeps the real state authoritative thereafter.
  conditions_v2 = []
  filters_v2    = []
  actions_v2 = [
    {
      notify_email = {
        target_type      = "IssueOwners"
        fallthrough_type = "ActiveMembers"
      }
    },
  ]

  lifecycle {
    ignore_changes = [
      conditions_v2,
      filters_v2,
      actions_v2,
      environment,
      frequency,
    ]
  }
}

resource "sentry_issue_alert" "sandbox_startup_failure" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "sandbox-startup-failure"
  action_match = "all"
  filter_match = "all"
  frequency    = 22

  conditions_v2 = [
    {
      event_unique_user_frequency = {
        comparison_type = "count"
        value           = 2 # STRICT `>`: fires at ≥3 distinct tenants (#6429)
        interval        = "1h"
      }
    },
  ]
  filters_v2 = [
    {
      tagged_event = {
        key   = "feature"
        match = "EQUAL"
        value = "agent-sandbox"
      }
    },
    {
      tagged_event = {
        key   = "op"
        match = "EQUAL"
        value = "sdk-startup"
      }
    },
  ]
  # N=1 accepted risk (mirrors the sibling rules in this file): IssueOwners has no
  # ownership rule on this project → falls through to ActiveMembers, paging the
  # active founder + ops@soleur.ai. The event carries only a userIdHash (Recital
  # 26 pseudonymized at the emit boundary) + bwrap/kernel stderr — no plaintext
  # tenant PII — so the fallthrough does not over-disclose. Revisit recipient
  # pinning (target_type="Member") before the first non-ops Sentry seat.
  actions_v2 = [
    {
      notify_email = {
        target_type      = "IssueOwners"
        fallthrough_type = "ActiveMembers"
      }
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

# --------------------------------------------------------------------------
# The 27 adopted rules, generated from the live capture.
# --------------------------------------------------------------------------

resource "sentry_alert" "action_required_sla_veto_bypass" {
  organization      = var.sentry_org
  name              = "action-required-sla-veto-bypass"
  enabled           = true
  frequency_minutes = 5
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { first_seen_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "op", match = "eq", value = "action-required-sla" } },
        { tagged_event = { key = "sla_action", match = "eq", value = "expire" } },
        { tagged_event = { key = "human_engaged", match = "eq", value = "true" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "auth_callback_no_code_burst" {
  organization      = var.sentry_org
  name              = "auth-callback-no-code-burst"
  enabled           = true
  frequency_minutes = 62
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { event_frequency_count = { interval = "15m", value = 3 } },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "auth" } },
        { tagged_event = { key = "op", match = "eq", value = "callback_no_code" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "auth_exchange_code_burst" {
  organization      = var.sentry_org
  name              = "auth-exchange-code-burst"
  enabled           = true
  frequency_minutes = 61
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { event_frequency_count = { interval = "15m", value = 5 } },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "auth" } },
        { tagged_event = { key = "op", match = "eq", value = "exchangeCodeForSession" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "auth_signout_burst" {
  organization      = var.sentry_org
  name              = "auth-signout-burst"
  enabled           = true
  frequency_minutes = 60
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { event_frequency_count = { interval = "15m", value = 5 } },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "auth" } },
        { tagged_event = { key = "op", match = "eq", value = "signOut" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "byok_art_33_breach" {
  organization      = var.sentry_org
  name              = "byok-art-33-breach"
  enabled           = true
  frequency_minutes = 5
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "byok-delegations" } },
        { tagged_event = { key = "art_33_breach", match = "eq", value = "true" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "byok_cap_exceeded" {
  organization      = var.sentry_org
  name              = "byok-cap-exceeded"
  enabled           = true
  frequency_minutes = 15
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { first_seen_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "byok-delegations" } },
        { tagged_event = { key = "op", match = "in", value = "hourly-cap-exceeded,daily-cap-exceeded" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "NoOne" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "chat_message_save_failure" {
  organization      = var.sentry_org
  name              = "chat-message-save-failure"
  enabled           = true
  frequency_minutes = 10
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "cc-dispatcher" } },
        { tagged_event = { key = "op", match = "in", value = "tenant-mint.persistUserMessage,persistUserMessage.workspaceRead,persist-user-message" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "container_restart_burst" {
  organization      = var.sentry_org
  name              = "container-restart-burst"
  enabled           = true
  frequency_minutes = 17
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "container-restart-monitor" } },
        { tagged_event = { key = "op", match = "in", value = "restart_storm,fresh_crash_loop" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "egress_blocked" {
  organization      = var.sentry_org
  name              = "cron-egress-blocked"
  enabled           = true
  frequency_minutes = 30
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "cron-egress-firewall" } },
        { tagged_event = { key = "op", match = "in", value = "egress_blocked" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "disk_io_wal_concentration" {
  organization      = var.sentry_org
  name              = "disk-io-wal-concentration"
  enabled           = true
  frequency_minutes = 21
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "cron-supabase-disk-io" } },
        { tagged_event = { key = "op", match = "eq", value = "wal-concentration" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "gh_pages_cert_reissue_failed" {
  organization      = var.sentry_org
  name              = "gh-pages-cert-reissue-failed"
  enabled           = true
  frequency_minutes = 63
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { event_frequency_count = { interval = "1h", value = 0 } },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "cron-gh-pages-cert-reissue" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "git_data_boot_fatal" {
  organization      = var.sentry_org
  name              = "git-data-boot-fatal"
  enabled           = true
  frequency_minutes = 24
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { event_frequency_count = { interval = "1h", value = 0 } },
  ]

  action_filters = [
    {
      logic_type = "any-short"
      conditions = [
        { tagged_event = { key = "stage", match = "eq", value = "gitdata_runcmd_early" } },
        { tagged_event = { key = "stage", match = "eq", value = "sshd_config" } },
        { tagged_event = { key = "stage", match = "eq", value = "volume_mount" } },
        { tagged_event = { key = "stage", match = "eq", value = "gitdata_doppler_dl" } },
        { tagged_event = { key = "stage", match = "eq", value = "doppler_run" } },
        { tagged_event = { key = "stage", match = "eq", value = "luks_open" } },
        { tagged_event = { key = "stage", match = "eq", value = "bootstrap" } },
        { tagged_event = { key = "stage", match = "eq", value = "gc" } },
        { tagged_event = { key = "stage", match = "eq", value = "gc_timer" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "github_webhook_founder_ambiguous" {
  organization      = var.sentry_org
  name              = "github-webhook-founder-ambiguous"
  enabled           = true
  frequency_minutes = 19
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "github-webhook" } },
        { tagged_event = { key = "op", match = "eq", value = "founder-ambiguous" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "inbox_action_required_notify_failure" {
  organization      = var.sentry_org
  name              = "inbox-action-required-notify-failure"
  enabled           = true
  frequency_minutes = 15
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { first_seen_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "inbox" } },
        { tagged_event = { key = "op", match = "eq", value = "notify-inbox-action-required" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "kb_db_error" {
  organization      = var.sentry_org
  name              = "kb-db-error"
  enabled           = true
  frequency_minutes = 13
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "kb-share" } },
        { tagged_event = { key = "op", match = "in", value = "create,list,revoke,preview,preview-invariant" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "kb_sync_protected_fallback_failed" {
  organization      = var.sentry_org
  name              = "kb-sync-protected-fallback-failed"
  enabled           = true
  frequency_minutes = 18
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "session-sync" } },
        { tagged_event = { key = "op", match = "in", value = "kb-sync.protected-fallback-failed" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "kb_sync_silent_failure" {
  organization      = var.sentry_org
  name              = "kb-sync-silent-failure"
  enabled           = true
  frequency_minutes = 12
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "kb-route-helpers" } },
        { tagged_event = { key = "op", match = "in", value = "kb-sync.unexpected" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "local_cache_reload_rate" {
  organization      = var.sentry_org
  name              = "local-cache-reload-rate"
  enabled           = true
  frequency_minutes = 26
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { event_frequency_count = { interval = "1h", value = 0 } },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "registry", match = "eq", value = "local-cache" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "outbound_email_send_failure" {
  organization      = var.sentry_org
  name              = "outbound-email-send-failure"
  enabled           = true
  frequency_minutes = 16
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "outbound-email" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "repo_resolver_divergence" {
  organization      = var.sentry_org
  name              = "repo-resolver-divergence"
  enabled           = true
  frequency_minutes = 20
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "repo-resolver-divergence" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "seccomp_remediation_failed" {
  organization      = var.sentry_org
  name              = "seccomp-remediation-failed"
  enabled           = true
  frequency_minutes = 27
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { event_frequency_count = { interval = "1h", value = 0 } },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "op", match = "eq", value = "seccomp-remediation-failed" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "stale_bot_pr" {
  organization      = var.sentry_org
  name              = "stale-bot-pr"
  enabled           = true
  frequency_minutes = 14
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "cron-cloud-task-heartbeat" } },
        { tagged_event = { key = "op", match = "in", value = "stale-bot-pr,stale-bot-pr-scan-failed,stale-bot-pr-comment-failed" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "web_private_nic_boot_gate" {
  organization      = var.sentry_org
  name              = "web-host-private-nic-boot-gate"
  enabled           = true
  frequency_minutes = 24
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { event_frequency_count = { interval = "1h", value = 1 } },
  ]

  action_filters = [
    {
      logic_type = "any-short"
      conditions = [
        { tagged_event = { key = "stage", match = "eq", value = "private_nic_timeout" } },
        { tagged_event = { key = "stage", match = "eq", value = "private_nic_probe_fault" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "web_terminal_boot_fatal" {
  organization      = var.sentry_org
  name              = "web-host-terminal-boot-fatal"
  enabled           = true
  frequency_minutes = 24
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { event_frequency_count = { interval = "1h", value = 1 } },
  ]

  action_filters = [
    {
      logic_type = "any-short"
      conditions = [
        { tagged_event = { key = "stage", match = "eq", value = "terminal_preamble" } },
        { tagged_event = { key = "stage", match = "eq", value = "hostscripts_incomplete" } },
        { tagged_event = { key = "stage", match = "eq", value = "doppler_download" } },
        { tagged_event = { key = "stage", match = "eq", value = "docker_run" } },
        { tagged_event = { key = "stage", match = "eq", value = "pull" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "workspace_sync_health" {
  organization      = var.sentry_org
  name              = "workspace-sync-health"
  enabled           = true
  frequency_minutes = 11
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { first_seen_event = {} },
    { reappeared_event = {} },
    { regression_event = {} },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "workspace-sync-health" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "workspaces_luks_drift" {
  organization      = var.sentry_org
  name              = "workspaces-luks-drift"
  enabled           = true
  frequency_minutes = 25
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { event_frequency_count = { interval = "1h", value = 0 } },
  ]

  action_filters = [
    {
      logic_type = "all"
      conditions = [
        { tagged_event = { key = "feature", match = "eq", value = "workspaces-luks" } },
        { tagged_event = { key = "op", match = "eq", value = "workspaces-luks-drift" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

resource "sentry_alert" "zot_mirror_fallback_rate" {
  organization      = var.sentry_org
  name              = "zot-mirror-fallback-rate"
  enabled           = true
  frequency_minutes = 23
  monitor_ids       = [data.sentry_project_issue_stream_monitor.web_platform.id]

  trigger_conditions = [
    { event_frequency_count = { interval = "1h", value = 0 } },
  ]

  action_filters = [
    {
      logic_type = "any-short"
      conditions = [
        { tagged_event = { key = "registry", match = "eq", value = "ghcr-fallback" } },
        { tagged_event = { key = "registry", match = "eq", value = "zot-gate-degraded" } },
        { tagged_event = { key = "stage", match = "eq", value = "inngest_ghcr_fallback" } },
        { tagged_event = { key = "stage", match = "eq", value = "app_ghcr_fallback" } },
        { tagged_event = { key = "stage", match = "eq", value = "app_ghcr_served" } },
      ]
      actions = [
        { email = { target_type = "issue_owners", fallthrough_type = "ActiveMembers" } },
      ]
    },
  ]

  lifecycle {
    ignore_changes = [environment]
  }
}

# --------------------------------------------------------------------------
# Forget the legacy addresses WITHOUT destroying the live objects.
# --------------------------------------------------------------------------

removed {
  from = sentry_issue_alert.action_required_sla_veto_bypass
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.auth_callback_no_code_burst
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.auth_exchange_code_burst
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.auth_signout_burst
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.byok_art_33_breach
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.byok_cap_exceeded
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.chat_message_save_failure
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.container_restart_burst
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.egress_blocked
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.disk_io_wal_concentration
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.gh_pages_cert_reissue_failed
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.git_data_boot_fatal
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.github_webhook_founder_ambiguous
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.inbox_action_required_notify_failure
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.kb_db_error
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.kb_sync_protected_fallback_failed
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.kb_sync_silent_failure
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.local_cache_reload_rate
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.outbound_email_send_failure
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.repo_resolver_divergence
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.seccomp_remediation_failed
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.stale_bot_pr
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.web_private_nic_boot_gate
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.web_terminal_boot_fatal
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.workspace_sync_health
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.workspaces_luks_drift
  lifecycle {
    destroy = false
  }
}

removed {
  from = sentry_issue_alert.zot_mirror_fallback_rate
  lifecycle {
    destroy = false
  }
}

# --------------------------------------------------------------------------
# Adopt the same live objects at the sentry_alert addresses.
# --------------------------------------------------------------------------

import {
  to = sentry_alert.action_required_sla_veto_bypass
  id = "${var.sentry_org}/715628"
}

import {
  to = sentry_alert.auth_callback_no_code_burst
  id = "${var.sentry_org}/566683"
}

import {
  to = sentry_alert.auth_exchange_code_burst
  id = "${var.sentry_org}/566682"
}

import {
  to = sentry_alert.auth_signout_burst
  id = "${var.sentry_org}/566672"
}

import {
  to = sentry_alert.byok_art_33_breach
  id = "${var.sentry_org}/600195"
}

import {
  to = sentry_alert.byok_cap_exceeded
  id = "${var.sentry_org}/600196"
}

import {
  to = sentry_alert.chat_message_save_failure
  id = "${var.sentry_org}/607768"
}

import {
  to = sentry_alert.container_restart_burst
  id = "${var.sentry_org}/638577"
}

import {
  to = sentry_alert.egress_blocked
  id = "${var.sentry_org}/624623"
}

import {
  to = sentry_alert.disk_io_wal_concentration
  id = "${var.sentry_org}/666233"
}

import {
  to = sentry_alert.gh_pages_cert_reissue_failed
  id = "${var.sentry_org}/705074"
}

import {
  to = sentry_alert.git_data_boot_fatal
  id = "${var.sentry_org}/728266"
}

import {
  to = sentry_alert.github_webhook_founder_ambiguous
  id = "${var.sentry_org}/671178"
}

import {
  to = sentry_alert.inbox_action_required_notify_failure
  id = "${var.sentry_org}/675790"
}

import {
  to = sentry_alert.kb_db_error
  id = "${var.sentry_org}/611582"
}

import {
  to = sentry_alert.kb_sync_protected_fallback_failed
  id = "${var.sentry_org}/638698"
}

import {
  to = sentry_alert.kb_sync_silent_failure
  id = "${var.sentry_org}/636637"
}

import {
  to = sentry_alert.local_cache_reload_rate
  id = "${var.sentry_org}/703994"
}

import {
  to = sentry_alert.outbound_email_send_failure
  id = "${var.sentry_org}/636539"
}

import {
  to = sentry_alert.repo_resolver_divergence
  id = "${var.sentry_org}/643978"
}

import {
  to = sentry_alert.seccomp_remediation_failed
  id = "${var.sentry_org}/703995"
}

import {
  to = sentry_alert.stale_bot_pr
  id = "${var.sentry_org}/630477"
}

import {
  to = sentry_alert.web_private_nic_boot_gate
  id = "${var.sentry_org}/707232"
}

import {
  to = sentry_alert.web_terminal_boot_fatal
  id = "${var.sentry_org}/695939"
}

import {
  to = sentry_alert.workspace_sync_health
  id = "${var.sentry_org}/609710"
}

import {
  to = sentry_alert.workspaces_luks_drift
  id = "${var.sentry_org}/703574"
}

import {
  to = sentry_alert.zot_mirror_fallback_rate
  id = "${var.sentry_org}/685990"
}
