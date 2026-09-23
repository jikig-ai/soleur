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

# ── #8408 (a): the registry store is not on LUKS, or its escrow is not proven ───────────────────
#
# WHAT IT DETECTS. The registry host's */5 SOLEUR_ZOT_DISK heartbeat (a direct POST to this same
# source — zot-registry.tf's `betterstack_logs_ingest_url` is s2457081, which IS
# local.vector_prd_source_id) carries two store fields in its TRUSTED HEAD, everything before
# ` zot_last_err=` (the free-text tail, emitted last; scripts/lib/zot-telemetry-parse.sh cuts there):
#   (A) `store_luks=yes ` absent from the head — the store is off the LUKS mapper after a replace,
#       a reboot, or a boot that took the wrong arm. zot is then serving from plaintext.
#   (B) `store_escrow=<token>` present in the head with any value other than `ok` — the daily
#       re-test says the next reboot may not be able to reopen the store (fail_passphrase,
#       fail_header, fail_key_absent), or the re-test itself stopped measuring (stale, none,
#       indeterminate, __UNREADABLE__). "Anything but ok" is deliberate: a fail-only arm leaves a
#       dead escrow job silent, which is exactly how it would rot. The one other quiet token is
#       `pending`: the heartbeat writes it only while no result exists yet AND uptime < 2 h (the
#       first-boot run is deferred 15 min); after 2 h an absent result reads `none`, which pages.
#
# WHY IT SHIPS UNPAUSED AT MERGE. Every live row today carries `store_luks=yes ` (measured below),
# and rows that predate the escrow field carry no `store_escrow=` at all, so arm (B) cannot fire on
# them. The rule is quiet from the moment it exists.
#
# HEAD-SCOPING. Each arm compares a position against ` zot_last_err=` exactly once, so tail text
# (zot's own log line, attacker-influenced) can neither satisfy nor suppress either arm:
#   (A) a `store_luks=yes ` that first appears in the tail is past the cut, so the row still fires;
#   (B) the FIRST `store_escrow=` in the row is the head field (the emitter writes it before
#       ` host=`), and the row is quiet only if a `store_escrow=ok ` starts at that same position.
#   The envelope conjunct is the direct-POST shape `zot_envelope_anchor` uses: a Vector-shipped
#   journald row that merely QUOTES the marker starts `{"PRIORITY":…` and cannot match.
#
# LIVE-PROBED 2026-09-21 against the ClickHouse table (hot remote() UNION ALL s3Cluster archive),
# 24h window, the predicate below verbatim:
#   envelope rows (startsWith only)                              -> 288 (24h x 12/h: every heartbeat)
#   (i)   as written                                             -> 0   (quiet on the live fleet)
#   (ii)  'store_luks=yes ' -> 'store_luks=nope '                -> 288 (positive control: arm A is live)
#   (iii) arm-B presence 'store_escrow=' -> 'store_luks='        -> 288 (arm B is live SQL, not dead syntax)
#   (iv)  (iii) plus 'store_escrow=ok ' -> 'store_luks=yes ', arm A forced false
#                                                                -> 0   (arm B's ok-negation suppresses)
#   (v)   2026-09-21, hot table only (remote(), 24h), AFTER the `pending` conjunct was added:
#         envelope 119, as written 0, arm-A positive control 119, rows carrying store_escrow= 0.
#         So arm B is not yet exercisable live: no delivered heartbeat carries the field until the
#         next registry replace. (iii)/(iv) above are its evidence that the SQL is live.
#         [Delivered on boot 5639cc07, 2026-09-22: heartbeats now carry store_escrow=.]
#
# NO BOOT GRACE FOR ARM A. On the last registry replace boot (b3ec6c3b) 342 of 342 heartbeat rows
# read `store_luks=yes ` and none read `absent`: the mapper is open before the first heartbeat, so
# arm A needs no uptime exemption. `value = 1` still absorbs one transient row.
#
# PAGING SEMANTICS. The alert is a per-bucket threshold, and the bucket (`aggregation_interval`,
# omitted here as in every sibling) is snapped by the API to query_period: measured 2026-09-21 on
# the two live siblings, 300 -> 300 and 5400 -> 5400. So one 900 s bucket holds up to three
# heartbeats, and `higher_than 1` pages on >= 2 matching rows in it: a single transient row
# during a replace (one pre-mount tick on the new boot) does not page, a persistent condition does.
locals {
  registry_store_not_luks_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND startsWith(raw, '{"message":"SOLEUR_ZOT_DISK ')
      AND position(JSONExtractString(raw, 'message'), 'SOLEUR_ZOT_DISK ') = 1
      AND (
        NOT (position(JSONExtractString(raw, 'message'), 'store_luks=yes ') > 0
          AND position(JSONExtractString(raw, 'message'), 'store_luks=yes ') < position(JSONExtractString(raw, 'message'), ' zot_last_err='))
        OR (position(JSONExtractString(raw, 'message'), 'store_escrow=') > 0
          AND position(JSONExtractString(raw, 'message'), 'store_escrow=') < position(JSONExtractString(raw, 'message'), ' zot_last_err=')
          AND position(JSONExtractString(raw, 'message'), 'store_escrow=ok ') != position(JSONExtractString(raw, 'message'), 'store_escrow=')
          AND position(JSONExtractString(raw, 'message'), 'store_escrow=pending ') != position(JSONExtractString(raw, 'message'), 'store_escrow='))
      )
    GROUP BY time
  SQL

  registry_store_not_luks_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md"
}

resource "logtail_exploration" "registry_store_not_luks" {
  name      = "soleur-registry-store-not-luks-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    # Single-line at the resource site, for the same perpetual-diff reason as the siblings above.
    sql_query = replace(trimspace(local.registry_store_not_luks_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "registry_store_not_luks" {
  exploration_id = logtail_exploration.registry_store_not_luks.id
  name           = "soleur-registry-store-not-luks-prd"

  # The heartbeat is */5, so a 900 s window covers three emissions; see PAGING SEMANTICS above
  # for why value = 1 means ">= 2 matching rows". recovery_period covers two windows, so one good
  # bucket does not close an incident the next would re-open.
  alert_type          = "threshold"
  operator            = "higher_than"
  value               = 1
  check_period        = 300
  query_period        = 900
  confirmation_period = 0
  recovery_period     = 1800
  # A count query with no rows returns NO bucket, which must read as healthy (0) so an open
  # incident can observe recovery. Silence is NOT this rule's job: zot not running is
  # betteruptime_heartbeat.registry_prd's (zot-registry.tf), and SOLEUR_ZOT_DISK itself going dark
  # is scheduled-zot-restart-loop.yml's (scripts/zot-restart-loop-alarm.sh, its SILENT and
  # INGEST_DARK verdicts).
  on_missing_data = "treat_as_zero"

  paused = false

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "The registry host's SOLEUR_ZOT_DISK heartbeat says its zot store is NOT on the LUKS mapper (store_luks is not yes), or the daily escrow re-test is not ok (store_escrow is fail_*, stale, none or indeterminate). Runbook: ${local.registry_store_not_luks_runbook_url}"
  metadata = {
    runbook = local.registry_store_not_luks_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}

# ── #8611 / ADR-243: Anthropic spend — a step outliving the proxy, and the daily burn ───────────
#
# WHY THESE EXIST. The self-hosted Inngest server calls every step at the Cloudflare-proxied
# serveHost, and Cloudflare gives up on an origin response after ~100 s. A claude-eval step that
# outlives that gets a 524, `retries: 1` re-invokes it while the first Claude session is still
# running, and the run fails anyway: 51% of 30-day cron spend was those duplicates and a $50
# top-up lasted ~39 h. Three standing alarms, one per question:
#   (1) inngest_step_524         — is a step being cut at the proxy again? (per 15 min)
#   (2) claude_cost_daily_burn   — is the cron fleet spending more than $15 in 24 h?
#   (3) claude_cost_capture_dark — has the cost telemetry itself gone dark for 24 h?
# (2) cannot fire on silence (treat_as_zero reads "no rows" as $0), which is why (3) exists.
#
# AGGREGATES ONLY. Every select below is a count or a sum. The inngest-server line can carry
# queue-item payloads (email data) and a Cloudflare 524 page carries an IP, so no exploration here
# selects a message column or groups on free text. The drift guard asserts it.
#
# LIVE-PROBED 2026-09-23 via betterstack-query.sh, template variables substituted by hand
# ({{source}} = hot remote() UNION ALL s3Cluster archive, columns dt/raw):
#   (1) 2026-09-16..09-23: 18 matching rows (all `_SYSTEMD_UNIT=inngest-server.service`,
#       PRIORITY 6, message.error = 'invalid status code: 524', message.msg = 'error handling queue
#       item'); negative control 'invalid status code: 523' -> 0 rows.
#   (2) 24 h ending 09-14 23:59:59 -> $34.41 (pages), ending 09-21 23:59:59 -> $28.35 (pages),
#       ending 09-22 23:59:59 -> $0 (credit exhausted, quiet).
#   (3) 24 h ending 09-22 23:59:59 -> 27 (arm A 3 + arm B 24, quiet); both arms neutralised ->
#       one row with value 0 (the page fires).
#
# THE DAILY WINDOW. (2) and (3) aggregate the WHOLE evaluation window into one row instead of
# `GROUP BY {{time}}`: with query_period 86400 the bucket would be snapped to a day, and a
# calendar-aligned bucket splits a trailing 24 h across two partial days — $30 of spend would read
# as two sub-$15 buckets, and every early-UTC evaluation of (3) would see a near-empty bucket and
# page. The window filter is therefore on the `dt` COLUMN, never on the `time` alias: here the
# alias is a constant, so `time BETWEEN …` would be always-true and sum the source's entire
# history (measured in the probe: $58.64 for a day whose real total is $34.41).
# query_period 86400 is NOT validated client-side by the logtail provider (v11.2.0 schema:
# "The query evaluation window in seconds", no bound) and the largest live precedent in this file
# is 5400. If the API rejects it, the create fails the apply step loudly (no silent state); fall
# back to 5400 and scale (2) to $15 x 5400 / 86400 ~= $0.94 per window, recorded in ADR-243.
#
# CREDIT EXHAUSTION IS NOT A TELEMETRY FAILURE. (3)'s arm B counts the credit probe's own
# `anthropic-credit-exhausted` / `anthropic-key-invalid` rows (hourly while RED), so a zero-spend
# day with no credit is quiet. That page is the credit probe's (Sentry monitor
# scheduled-anthropic-credit-probe), not this rule's.
locals {
  # (1) Field-isolated rather than `raw LIKE '%…524%'`: GitHub webhook payloads (issue and PR
  # bodies) reach this source, and this very incident's issues quote the literal. No PRIORITY
  # filter — the live lines are PRIORITY 6 and ship because the inngest_journald source forwards
  # every priority for that unit.
  inngest_step_524_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND JSONExtractString(raw, '_SYSTEMD_UNIT') = 'inngest-server.service'
      AND multiSearchAny(JSONExtractString(raw, 'message', 'error'), ['invalid status code: 524'])
    GROUP BY time
  SQL
  # S7 SLOT (#8611 Phase 0): the streaming spike's stream-cut error text is appended to the
  # needle array above as a second literal once measured. One array, one alert.

  # (2) and (3) read the per-run marker at its nested path (pino fields sit under raw.message since
  # #8344; the top-level form reads 0 on every row). The `"SOLEUR_CLAUDE_COST":true` key match keeps
  # the SOLEUR_CLAUDE_COST_DAILY org-total rows out; `component = 'claude-cost'` keeps an echoed
  # issue body out; `source LIKE 'cron:%'` keeps founder BYOK sessions out (their spend is not the
  # operator key's).
  claude_cost_daily_burn_sql = <<-SQL
    SELECT toDateTime({{end_time}}) AS time, sum(JSONExtractFloat(raw, 'message', 'cost_usd')) AS value
    FROM {{source}}
    WHERE dt BETWEEN {{start_time}} AND {{end_time}}
      AND raw LIKE '%"SOLEUR_CLAUDE_COST":true%'
      AND JSONExtractString(raw, 'message', 'component') = 'claude-cost'
      AND JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'
  SQL

  claude_cost_capture_dark_sql = <<-SQL
    SELECT toDateTime({{end_time}}) AS time, count(*) AS value
    FROM {{source}}
    WHERE dt BETWEEN {{start_time}} AND {{end_time}}
      AND (
        (raw LIKE '%"SOLEUR_CLAUDE_COST":true%'
          AND JSONExtractString(raw, 'message', 'component') = 'claude-cost'
          AND JSONExtractString(raw, 'message', 'source') LIKE 'cron:%'
          AND JSONExtract(raw, 'message', 'cost_usd', 'Nullable(Float64)') IS NOT NULL)
        OR (JSONExtractString(raw, 'message', 'feature') = 'cron-anthropic-credit-probe'
          AND JSONExtractString(raw, 'message', 'op') IN ('anthropic-credit-exhausted', 'anthropic-key-invalid'))
      )
  SQL

  claude_spend_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/betterstack-log-query.md#standing-alarms-over-this-source-log-content-recurrence-alarms"
}

resource "logtail_exploration" "inngest_step_524" {
  name      = "soleur-inngest-step-524-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    # Single-line at the resource site, for the same perpetual-diff reason as the siblings above.
    sql_query = replace(trimspace(local.inngest_step_524_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "inngest_step_524" {
  exploration_id = logtail_exploration.inngest_step_524.id
  name           = "soleur-inngest-step-524-prd"

  # One 524 is already a double-billed run, so any row in 15 minutes pages. recovery_period covers
  # two windows, so one quiet window between two cron fires does not close the incident.
  alert_type          = "threshold"
  operator            = "higher_than"
  value               = 0
  check_period        = 300
  query_period        = 900
  confirmation_period = 0
  recovery_period     = 1800
  on_missing_data     = "treat_as_zero"

  paused = false

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "The Inngest server got HTTP 524 calling a function step through Cloudflare: a step outlived the proxy timeout, and a retry may have started a second paid Claude session. Runbook: ${local.claude_spend_runbook_url}"
  metadata = {
    runbook = local.claude_spend_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}

resource "logtail_exploration" "claude_cost_daily_burn" {
  name      = "soleur-claude-cost-daily-burn-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    # Single-line at the resource site, for the same perpetual-diff reason as the siblings above.
    sql_query = replace(trimspace(local.claude_cost_daily_burn_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "claude_cost_daily_burn" {
  exploration_id = logtail_exploration.claude_cost_daily_burn.id
  name           = "soleur-claude-cost-daily-burn-prd"

  # $15 is ~2x the post-fix funded-day rate (~$7); recalibrate after 14 funded days (ADR-243). The
  # window is a trailing 24 h checked hourly; spend ages out of it, so recovery needs no slack.
  alert_type          = "threshold"
  operator            = "higher_than"
  value               = 15
  check_period        = 3600
  query_period        = 86400
  confirmation_period = 0
  recovery_period     = 3600
  # An empty window is $0 spent — healthy. Silence is claude_cost_capture_dark's job.
  on_missing_data = "treat_as_zero"

  paused = false

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "The claude-eval cron fleet spent more than $15 of operator Anthropic credit in the last 24 h (SOLEUR_CLAUDE_COST cost_usd, cron sources). Runbook: ${local.claude_spend_runbook_url}"
  metadata = {
    runbook = local.claude_spend_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}

resource "logtail_exploration" "claude_cost_capture_dark" {
  name      = "soleur-claude-cost-capture-dark-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    # Single-line at the resource site, for the same perpetual-diff reason as the siblings above.
    sql_query = replace(trimspace(local.claude_cost_capture_dark_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "claude_cost_capture_dark" {
  exploration_id = logtail_exploration.claude_cost_capture_dark.id
  name           = "soleur-claude-cost-capture-dark-prd"

  # Pages when a trailing 24 h holds neither a cron cost marker with a non-null cost_usd nor a
  # credit-probe RED row. The cron fleet runs many times a day, so a whole day of neither means the
  # marker path (emitter, Vector, or the nested field) is broken — and the burn alert above is blind.
  alert_type          = "threshold"
  operator            = "lower_than"
  value               = 1
  check_period        = 3600
  query_period        = 86400
  confirmation_period = 0
  recovery_period     = 3600
  # The inverse of every sibling's reason: a missing value must read as 0 so silence FIRES.
  on_missing_data = "treat_as_zero"

  paused = false

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "No claude-eval cron cost marker with a cost_usd (and no credit-probe RED row) reached Better Stack in 24 h: the spend telemetry is dark, so the daily burn alert cannot fire. Runbook: ${local.claude_spend_runbook_url}"
  metadata = {
    runbook = local.claude_spend_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}
