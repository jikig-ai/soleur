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
# Plan: knowledge-base/project/plans/archive/20260913-190954-2026-09-12-feat-betterstack-send-failed-alert-rule-plan.md
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

# ── #6894 / ADR-142: the store is not on the encrypted volume ───────────────────────────────────
#
# WHAT IT DETECTS. After the LUKS cutover, the dedicated host's own probe row resolves the device
# backing /mnt/data all the way to a Hetzner by-id alias (`data_mount_devid`, probe_schema=8). Post
# cutover that alias must be the ADDITIVE volume's. Anything else is the store having moved back —
# an on-host rollback, a reboot that took the pre-cutover arm because the pointer went missing, or
# a replace whose first boot resolved the plaintext volume — and each of those means writes are
# landing UNENCRYPTED again, which is the one thing this whole change exists to prevent. Nothing
# else notices: the scheduler is healthy in every one of those states, so uptime stays green.
#
# WHAT IT DELIBERATELY DOES NOT DETECT: the plaintext backstop volume merely staying ATTACHED
# while the store is correctly on the encrypted one. That is the additive design's rollback route,
# and retiring it is a Terraform declaration change, tracked with an expiry in issue #8285.
#
# WHY IT SHIPPED PAUSED, AND WHY IT NO LONGER IS. Before the cutover the correct value of that
# field WAS the plaintext alias, so an armed rule would have paged continuously from merge until
# the cutover — and an alert that pages when nothing is wrong is one that gets muted, which is how
# a real page is missed later. The 2026-09-20 additive cutover inverted that: the store now reports
# on the encrypted alias, so a probe row pinning the plaintext one is the regression this rule
# exists to catch. `var.inngest_luks_cutover_complete` was flipped to true in #8296 and the
# DECLARATION is armed.
#
# ARMING HAPPENS ON THE APPLY, NOT AT MERGE — `paused` is a provider-side attribute, so until an
# apply runs, this file says armed and Better Stack still has it paused. There is no
# `terraform apply -var …` route here: this root is applied by apply-web-platform-infra.yml, which
# takes no such input. Flip the declared default in variables.tf (or the Doppler override the
# comment there names) and let the workflow apply it. The declared/live divergence in between is
# what the reconciler (heartbeat-live-reconcile.ts) reports as `logs-alert-paused` twice daily;
# since #8296 that report is no longer suppressed for this alert.
#
# THE ID COMES FROM THE RESOURCE, never a literal: a volume re-created under a new id would
# otherwise leave the rule watching for an alias that no longer exists — the alert would go quiet,
# which reads exactly like health. `hcloud_volume.inngest_redis_luks.id` is the digits Hetzner
# assigns; the by-id alias is `scsi-0HC_Volume_<id>`, the same construction the host's own resolver
# and inngest-luks-cutover.sh use.
locals {
  inngest_luks_wrong_volume_alias = "scsi-0HC_Volume_${hcloud_volume.inngest_redis_luks.id}"

  # The probe row is a space-separated key=value message, so the field is matched WITH its key and
  # WITH a trailing space — `data_mount_devid=scsi-0HC_Volume_1234` is a prefix of
  # `…_12345`, and the row has a field after this one on every emitted path. The negation is over
  # the whole predicate, so a row that cannot be matched at all (a schema change that drops or
  # renames the field) FIRES rather than going quiet: an unreadable answer is not a clean one.
  # LIVE-PROBED 2026-09-18 against the ClickHouse table (the step-1 requirement above), 24h window:
  #   total=37248  probe_rows=22  host_role=dedicated rows=11
  #   watched alias = the live PLAINTEXT alias  -> 0 rows   (quiet when the field matches)
  #   watched alias = a wrong id                -> 11 rows  (positive control: the rule is live)
  #   watched alias = the plaintext id TRUNCATED by one digit -> 11 rows (the trailing space is
  #     what stops `…_10626194` from matching `…_106261946`; without it this control returns 0)
  # The 11 non-dedicated probe rows in the same window are web-1's, which is what the host_role
  # scope excludes — measured, not assumed.
  inngest_luks_wrong_volume_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND position(JSONExtractString(raw, 'message'), 'SOLEUR_INNGEST_SERVER_PROBE') = 1
      AND position(JSONExtractString(raw, 'message'), 'host_role=dedicated ') > 0
      AND position(JSONExtractString(raw, 'message'), 'data_mount_devid=${local.inngest_luks_wrong_volume_alias} ') = 0
    GROUP BY time
  SQL

  inngest_luks_wrong_volume_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md"
}

resource "logtail_exploration" "inngest_luks_wrong_volume" {
  name      = "soleur-inngest-luks-wrong-volume-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    # Single-line at the resource site, for the same perpetual-diff reason as the sibling above.
    sql_query = replace(trimspace(local.inngest_luks_wrong_volume_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "inngest_luks_wrong_volume" {
  exploration_id = logtail_exploration.inngest_luks_wrong_volume.id
  name           = "soleur-inngest-luks-wrong-volume-prd"

  # The probe emits hourly, so the window is an hour wide plus slack: a narrower one would report
  # "no rows" between emissions, and with treat_as_zero that reads as healthy rather than as
  # "nothing measured". recovery_period covers two emissions, so one good row does not close an
  # incident the next row would re-open.
  alert_type          = "threshold"
  operator            = "higher_than"
  value               = 0
  check_period        = 300
  query_period        = 5400
  confirmation_period = 0
  recovery_period     = 10800
  on_missing_data     = "treat_as_zero"

  # Armed since #8296 by var.inngest_luks_cutover_complete's declared default (takes effect on the
  # apply) — see "WHY IT SHIPPED PAUSED, AND WHY IT NO LONGER IS" above. This is the one alert in
  # this file whose paused state is a variable rather than a constant `false`.
  paused = !var.inngest_luks_cutover_complete

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "The dedicated Inngest host reports /mnt/data backed by a volume that is NOT the encrypted one (probe_schema=8 data_mount_devid). Redis writes are landing unencrypted. Runbook: ${local.inngest_luks_wrong_volume_runbook_url}"
  metadata = {
    runbook = local.inngest_luks_wrong_volume_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}
