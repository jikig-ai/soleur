# Better Stack LOGS alerts — native, Terraform-managed (ADR-218, #8097).
#
# PURPOSE. Page the on-call when a web-1 monitor unit's OWN send path fails: #8073 made
# disk-monitor / resource-monitor / container-restart-monitor / cron-egress-alarm emit a
# PRIORITY-2 journald row (`SOLEUR_<UNIT>_SEND_FAILED …` / `SOLEUR_<UNIT>_REFUSED …`) whenever
# their Resend email or Sentry event could not be delivered. Vector Source 2 ships those rows to
# Logs source 2457081; without this file nothing paged on them, so a broken Resend/Sentry path
# left ops unpaged while the customer met the underlying outage first. The detector lives on
# Better Stack precisely because the thing being detected IS the Sentry/Resend path — this is the
# exit that survives a Sentry-side outage (model.c4 `betterstack -> founder`).
#
# Plan: knowledge-base/project/plans/2026-09-12-feat-betterstack-send-failed-alert-rule-plan.md
# Runbook: knowledge-base/engineering/operations/runbooks/monitor-send-failed-alert.md
# Decision: knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md
# Drift guard: apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh (+ its mutation battery)
#
# WHY `SOLEUR_*_SEND_SKIPPED` NEVER PAGES. Two of the four units (cron-egress-alarm,
# container-restart-monitor) emit SEND_SKIPPED for a deliberate skip (cooldown, jq missing, a
# channel's env unset) as its own marker class "so a future alert
# rule on SEND_FAILED never pages on configuration" (cron-egress-alarm.sh). The predicate below
# uses `multiSearchAny` with LITERAL needles and no LIKE wildcard, so `_SEND_SKIPPED` matches
# neither `_SEND_FAILED` nor `_REFUSED` by construction; the drift guard asserts that against
# every SKIPPED/_HALT literal in the emitters. `SOLEUR_<UNIT>_HALT` (the #7797 xtrace guard,
# also PRIORITY 2) is deliberately outside the operator's stated scope — decision-challenges
# UC-1 and ADR-218 record the exclusion; opting in is one more needle.
#
# ROUTING. The free tier has no escalation policy (every `betteruptime_policy` is
# `count = var.betterstack_paid_tier ? 1 : 0`), so this alert emails the same team surface every
# sibling monitor and heartbeat uses (account owner + betteruptime_team_member.ops) and escalates
# to betteruptime_policy.uptime when the paid tier is enabled — the same ternary as
# uptime-alerts.tf, in the alert's escalation_target shape.
#
# CHANGED THE SQL? BUMP THE REV. `monitor_send_failed_probe_rev` is the ONLY trigger of
# terraform_data.send_failed_alert_probe (server.tf): the SSH apply runs on every push to main
# that touches this root (on.push.paths), so a per-run nonce would page ops on every infra merge.
# The probe fires exactly when the rev changes and never otherwise — with ONE exception: a failed
# provisioner (SSH down mid-apply) taints the resource, and the next apply re-runs it at the SAME
# rev, so a page after a red apply run is the retry, not a second failure; a rev bump performs zero Better Stack API writes, so re-verification never
# perturbs the alert under test. Digits only (interpolated into a root shell literal and a
# ClickHouse LIKE) — enforced by the probe's lifecycle.precondition and by the guard.
#
# TO ADD ANOTHER LOGS ALERT (five steps, in this order):
#   1. a `locals { <name>_sql = <<-SQL … SQL }` predicate (probe it live via betterstack-query.sh
#      with a positive control first — the template SQL is NOT validated by `terraform validate`);
#   2. a `logtail_exploration` carrying that SQL, `variable "source"` = local.vector_prd_source_id;
#   3. a `logtail_exploration_alert` on it (copy the paging semantics below, incl. treat_as_zero);
#   4. two `-target=` lines in apply-web-platform-infra.yml's MAIN plan allowlist (the #5566
#      guard in terraform-target-parity.test.ts reds until they exist);
#   5. a "Standing alarms over this source" row in runbooks/betterstack-log-query.md + a runbook.
#   A same-severity SOLEUR_* PRIORITY-2 class opts IN to THIS alert by adding a needle (+ a guard
#   row + a runbook decode row), not by adding a new alert — the free-tier alert count stays 1.
#
# DELETION. The per-merge apply is `-target`-scoped, so removing these resources is a silent
# no-op until the `[ack-destroy]` procedure runs (learning 2026-07-17). The runbook says so.

locals {
  # The existing Logs source, already public in vector.toml's sink URI
  # (`https://s2457081.eu-fsn-3.betterstackdata.com/`). A LITERAL, deliberately: the provider's
  # `logtail_source` data source exposes the source's ingest `token` attribute as Computed but
  # NOT Sensitive, so a data-source read would land the ingest token unflagged in
  # `terraform show -json` (the ARM step) and in the drift cron's plan text (pasted into a
  # public issue). The drift guard pins this literal to the sink URI.
  vector_prd_source_id = "2457081"

  # The predicate, live-probed 2026-09-12 against the ClickHouse table (positive control returned
  # real SOLEUR_ rows; constant checks: skipped_matches=0 failed_matches=1 refused_matches=1).
  # `{{time}}` / `{{source}}` / `{{start_time}}` / `{{end_time}}` are the Better Stack template
  # variables. PRIORITY = '2' is load-bearing: it is what keeps the non-crit `_REFUSED` markers
  # elsewhere in the fleet (inngest-cutover-flip.sh at user.notice, resend-inbound-bootstrap.sh
  # with no logger at all) out of the rule.
  monitor_send_failed_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND JSONExtractString(raw, 'PRIORITY') = '2'
      AND startsWith(JSONExtractString(raw, 'message'), 'SOLEUR_')
      AND multiSearchAny(JSONExtractString(raw, 'message'), ['_SEND_FAILED', '_REFUSED'])
    GROUP BY time
  SQL

  # The synthetic probe's only trigger — see "CHANGED THE SQL? BUMP THE REV" above.
  monitor_send_failed_probe_rev = "1"

  monitor_send_failed_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/monitor-send-failed-alert.md"
}

resource "logtail_exploration" "monitor_send_failed" {
  name      = "soleur-monitor-send-failed-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    # Collapsed to ONE line at the resource site: the provider mirrors `sql_query` back verbatim
    # with no DiffSuppressFunc (v11.2.0 resource_exploration.go), so a heredoc's indentation and
    # trailing newline would be a perpetual diff if the API normalises whitespace. Every provider
    # example is single-line; the local above stays readable, the API sees the flat form.
    sql_query = replace(trimspace(local.monitor_send_failed_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "monitor_send_failed" {
  exploration_id = logtail_exploration.monitor_send_failed.id
  name           = "soleur-monitor-send-failed-prd"

  # Any matching row in the window pages. query_period 300 >= the timers' 5-min cadence, so a
  # persisting failure holds ONE open incident instead of flapping; recovery_period 600 gives a
  # 10-min quiet window before auto-resolve. treat_as_zero: a count query with no rows returns
  # NO bucket — that must read as healthy (0), never as "unknown", or an open incident could
  # never observe recovery.
  alert_type          = "threshold"
  operator            = "higher_than"
  value               = 0
  check_period        = 60
  query_period        = 300
  confirmation_period = 0
  recovery_period     = 600
  on_missing_data     = "treat_as_zero"

  # Intent, written explicitly: a vendor-side pause (paused_reason "complexity issues" / "too many
  # failures") is re-armed by the next per-merge apply, so the untargeted drift plan is NOT the
  # detector — the `logs_alert` arm of reconcile-live-heartbeats.ts is (twice daily).
  paused = false

  # Mirrors every sibling heartbeat's channel set.
  email = true
  push  = false
  call  = false
  sms   = false
  # No sibling sets it and the free tier has no quiet hours; the knob to flip on the paid tier.
  critical_alert = false

  # The one field most likely rendered in the email, so it carries a CLICKABLE runbook URL —
  # a repo path is not actionable for a non-technical reader. A count alert's email carries no
  # row text; the runbook's step 1 is the readback SQL that names the marker.
  incident_cause = "SOLEUR_*_SEND_FAILED / _REFUSED row from a web-1 monitor unit — the monitor's own Resend/Sentry send failed. Runbook: ${local.monitor_send_failed_runbook_url}"
  metadata = {
    runbook = local.monitor_send_failed_runbook_url
  }

  # Same routing contract as uptime-alerts.tf's `policy_id` ternary: free tier → team email,
  # paid tier → the uptime escalation policy. Provider v11.2.0 `alert_shared.go`: all four
  # nested fields are plain Optional (no ExactlyOneOf); nulls are skipped on write and not
  # mirrored on read, so the null sibling never drifts.
  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }

  # DELIBERATELY OMITTED: aggregation_interval, series_names, series_names_except,
  # source_variable — all Optional+Computed; aggregation_interval is the one the API may snap to
  # a bucket size and rewrite (perpetual diff).
}
