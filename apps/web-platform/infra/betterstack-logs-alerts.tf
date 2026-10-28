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
# TO ADD ANOTHER LOGS ALERT (seven steps, in this order):
#   1. a `locals { <name>_sql = <<-SQL … SQL }` predicate (probe it live via betterstack-query.sh
#      with a positive control first — the template SQL is NOT validated by `terraform validate`).
#      Source 2457081 carries EVERY web host (web-1 `soleur-web-platform`, web-2 `soleur-web-2`):
#      if the signal belongs to one host, add a `host_name` conjunct or the other host's rows
#      satisfy it (#8706);
#   2. a `logtail_exploration` carrying that SQL, `variable "source"` = local.vector_prd_source_id;
#   3. a `logtail_exploration_alert` on it (copy the paging semantics below, incl. treat_as_zero);
#   4. two `-target=` lines in apply-web-platform-infra.yml's MAIN plan allowlist (NOT covered by
#      the #5566 guard in terraform-target-parity.test.ts, which checks terraform_data only: your
#      alert's own drift guard must assert both lines);
#   5. a "Standing alarms over this source" row in runbooks/betterstack-log-query.md + a runbook;
#   6. one `values = [local.vector_prd_source_id]` more in the exploration count that
#      apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh asserts exactly;
#   7. a `run: bash` step for the alert's drift guard in .github/workflows/infra-validation.yml
#      (apps/web-platform/test/infra/ is not glob-registered), plus any runbook path the guard reads
#      in that workflow's `paths:` filters.
#   A same-severity SOLEUR_* PRIORITY-2 class opts IN to THIS alert by adding a needle (+ a guard
#   row + a runbook decode row), not by adding a new alert. (The alert count and the unmeasured
#   free-tier cap are recorded in ADR-218.)
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
  # row text; the runbook's step 1 is the readback SQL that names the marker. Host-neutral on purpose
  # (#10136): since the Inngest host's TLS check opted in, a page can come from that host and not web-1.
  incident_cause = "SOLEUR_*_SEND_FAILED / _REFUSED row from a host monitor unit — either a web-1 monitor's own Resend/Sentry send failed, or the Inngest host's TLS check logged SOLEUR_INNGEST_TLS_REFUSED (listener down or certificate near expiry). The runbook's readback names the marker and the host. Runbook: ${local.monitor_send_failed_runbook_url}"
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
# an on-host rollback, or any boot that mounted a device other than the additive volume (the
# plaintext volume is destroyed and the template no longer has an arm for it, #9786, so this is now
# the tripwire for a regression of that, not a reachable state) — and each of those means writes are
# landing UNENCRYPTED again, which is the one thing this whole change exists to prevent. Nothing
# else notices: the scheduler is healthy in every one of those states, so uptime stays green.
#
# WHAT IT DELIBERATELY DID NOT DETECT: the plaintext backstop volume merely staying ATTACHED
# while the store was correctly on the encrypted one (the additive design's rollback route). That
# volume was destroyed on 2026-10-09 (#8285), so the state this paragraph excluded no longer exists;
# the rule's scope (a probe row pinning a non-encrypted alias) is unchanged.
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
# and (until it was retired with the cutover trio, #10112) inngest-luks-cutover.sh used.
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
  #
  # #8516 — the same treat_as_zero also blinds this alert to the probe going SILENT: a dead
  # emitter, a Vector journald-allowlist regression, or a sink outage all read as zero
  # wrong-volume rows while the store sitting on a non-encrypted device goes unpaged (the plaintext
  # volume hcloud_volume.inngest_redis this once named was destroyed 2026-10-09, #8285).
  # The dead-probe sibling that carries the absence-of-signal case is
  # betteruptime_heartbeat.inngest_server_probe (uptime-alerts.tf), armed and fed by
  # scheduled-inngest-probe-heartbeat.yml (#9703; arm record: runbook inngest-server.md section
  # "Arming the probe heartbeat (#9703)"; live state is read from Better Stack, not from this file).
  # The daily follow-through probe that once reported the same silence was retired 2026-10-12
  # (#9703 Stage 3b).
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

  # #11068 — push armed under the #9168 measured-flip convention; revert to `push = false` if the apply refuses it.
  email          = true
  push           = true
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

# ── #9927 item 2: the on-host LUKS key-continuity probe (paging alert) ──────────────────────────
# Once the owner delivers the signed bundle (#11266; merged, inert until then), the dedicated Inngest host
# runs a bounded probe (luks_key_probe_tick in inngest-cutover-flip.sh)
# that asks cryptsetup whether the key the host holds still unlocks the LUKS2 header behind
# /mnt/data, and reports ONE row per run: `SOLEUR_INNGEST_LUKS_KEY_PROBE token=<tok> rc=<n> at=<where>`,
# token in {ok, fail_passphrase, fail_header, fail_key_absent, indeterminate}, shipped twice (the
# journald tag inngest-cutover-flip, and a curl-direct phone-home whose message BEGINS with the marker).
# Rulings: decision-challenges.md D4 (paging) and D12 (the dead-man alert is NOT in this file: it
# ships in a follow-up PR once an owner-authorized create-and-delete probe proves the API accepts
# query_period = 2592000; tracked on the owner-hold issue #11266, a blocking prerequisite of the
# bundle promotion), plan 2026-10-26-feat-inngest-luks-key-continuity-probe-plan.md Phase 3.
# Pinned by apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh.
#
# SQL RULES: the marker is anchored at message position 1, never a `raw LIKE` prefilter (webhook
# payloads that quote the marker reach this source); the window filter is the `dt` COLUMN, never
# the `time` alias; one whole-window aggregate, no GROUP BY.
locals {
  # PAGES on any failed verdict. `indeterminate` is deliberately absent: an unmeasured verdict
  # never pages on its own (a transient low-memory skip would page a day). A non-ok probe re-runs
  # hourly, so a failing incident stays open on recovery_period (it outlasts the gap between rows) and a fixed one clears in about 1.25 to 1.5 h.
  inngest_luks_key_probe_fail_sql = <<-SQL
    SELECT toDateTime({{end_time}}) AS time, count(*) AS value
    FROM {{source}}
    WHERE dt BETWEEN {{start_time}} AND {{end_time}}
      AND position(JSONExtractString(raw, 'message'), 'SOLEUR_INNGEST_LUKS_KEY_PROBE') = 1
      AND position(JSONExtractString(raw, 'message'), 'token=fail_') > 0
  SQL

  # The subsection is written by the same change (runbook section 5c, "Key-continuity probe (#9927 item 2)").
  inngest_luks_key_probe_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md#key-continuity-probe-9927-item-2"
}

resource "logtail_exploration" "inngest_luks_key_probe_fail" {
  name      = "soleur-inngest-luks-key-probe-fail-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    # Single-line at the resource site, for the same perpetual-diff reason as the siblings above.
    sql_query = replace(trimspace(local.inngest_luks_key_probe_fail_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "inngest_luks_key_probe_fail" {
  exploration_id = logtail_exploration.inngest_luks_key_probe_fail.id
  name           = "soleur-inngest-luks-key-probe-fail-prd"

  # Presence-only, so safe before the probe is delivered (no rows, value 0). The window is 900 s
  # because that is the largest query_period Better Stack has accepted for a per-row-parse alert
  # since September (see the measured table below). The probe re-emits no sooner than hourly after any
  # non-ok token, so while it fails a row is in the window for 900 s of every ~3600 s; the count
  # reads 0 in between, but recovery_period (3600) is longer than that ~2700 s gap, so the incident
  # stays open and does not re-page. It pages within about 5 min of the first failing row and
  # clears about 1.25 to 1.5 h after the LAST failing row (the window, then recovery_period), which is
  # not proof of recovery: only a token=ok row is. Any missed hourly failing row (a dying probe, or one
  # indeterminate row between two failing ones) leaves a gap of up to ~6300 s with no failing row,
  # longer than recovery_period, so the incident can resolve and re-page once.
  #
  # MEASURED 2026-10-28 (a read-only GET of the live /api/v2/alerts, 19 alerts), not inferred: this
  # alert was refused 422 "too resource intensive" FOUR times at merge apply, at (check, query) =
  # (300, 10800) #11260, (900, 10800) #11384, (3600, 10800) #11404 and (300, 5400) #11374. Live
  # alerts with query_period above 900 are all September-created: luks_monitor_host_timer_dark
  # 3600/97200, claude_cost_daily_burn and claude_cost_capture_dark 3600/86400, inngest_luks_wrong_volume
  # 300/5400. Every alert created since 2026-10-01 has query_period <= 900 (registry_zot_log_credential_shape
  # 300/900 on 10-15, egress_gw_probe_fail 300/900 on 10-12, web_nic_guard_unpinned_url 60/300 on 10-27).
  # So an existing long window proves nothing about what the API accepts today. If 300/900 is refused
  # too, stop iterating merges: the next step is an owner-authorized create-and-delete probe.
  alert_type          = "threshold"
  operator            = "higher_than"
  value               = 0
  check_period        = 300
  query_period        = 900
  confirmation_period = 0
  recovery_period     = 3600
  on_missing_data     = "treat_as_zero"

  paused = false

  # #11068 convention (#9168 measured flip): push armed; revert to `push = false` if the apply refuses it.
  email          = true
  push           = true
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "The on-host LUKS key-continuity probe on the dedicated Inngest host reports a FAILED verdict (token=fail_passphrase, fail_header or fail_key_absent): the key the host holds no longer opens the volume behind /mnt/data, or is absent. The next reboot may not be able to reopen the store, and no header backup exists. Do NOT replace the host until the cause is established. Runbook: ${local.inngest_luks_key_probe_runbook_url}"
  metadata = {
    runbook = local.inngest_luks_key_probe_runbook_url
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

# ── #7530: a registry-plane clientIP that is not RFC1918 ────────────────────────────────────────
#
# WHAT IT DETECTS. zot logs the connecting peer as `clientIP` on its access lines. The CLO's
# 2026-08-13 ruling (knowledge-base/legal/audits/2026-08-counsel-review-7440.md) holds that the
# registry log shipper may ship `clientIP` unredacted ONLY while every observable value is
# RFC1918 (the estate's own hosts, 10.0.1.x, behind the Cloudflare tunnel and a deny-all-public
# firewall). Nothing enforced that. If ingress topology drifts (an inbound firewall rule, a proxy
# change) a public address becomes Art. 4(1) personal data on rows already in flight, silently.
# This alert EMAILS the team (free tier: email only, no escalation policy) on the first address-shaped `clientIP` outside 10/8, 172.16/12, 192.168/16
# (any IPv6 that is not an IPv4-mapped RFC1918 value included). It is DETECTION, not prevention:
# latency is up to about 20 minutes (300 s check, 900 s window, plus ingest), so the legal records
# say "monitored and alerted by email", never "guaranteed". Runbook: registry-clientip-rfc1918-7530.md.
#
# WHICH ROWS. Both producer shapes the registry host POSTs to this source, each anchored at OFFSET 0
# of the stored `raw` (the direct-POST envelope), so a Vector-shipped journald row that merely
# QUOTES the marker (it starts `{"PRIORITY":…`) cannot match: the shipper envelope
# `SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry ` (host-scoped: this source also
# carries web-1 and web-2) and the `SOLEUR_ZOT_DISK ` heartbeat (host-agnostic exactly as
# registry_store_not_luks is). The disk arm grades the WHOLE message including the free-text
# ` zot_last_err=` tail ON PURPOSE: on the non-fallback tiers (panic / error / warn) that tail carries
# zot's own log line, and so its clientIP (ADR-211 left it unmasked for this alert to see); on the
# tier-4 fallback the producer emits the parsed message only. In practice the shipper rows are the
# carrier: see the live probe (iv) below, and note the disk arm has NO live positive control.
#
# WHICH clientIP. Only the FIRST one in the decoded message (`extract` returns the first match):
# zot writes its own `clientIP` BEFORE `method`, `path` and `headers`, so a later client-controlled
# copy inside a header or a path cannot hide a real address (a decoy with no real field is a
# safe-direction false alert). The value is stripped of an optional `[` and an IPv4-mapped
# `::ffff:` prefix, then: dotted-IPv4-shaped AND not private -> alerts; two or more colons left
# (IPv6, or `ip:port` of a public IPv6) -> alerts; anything else (`default`, empty) is quiet.
#
# WHY IT IS WRITTEN LIKE THIS. The one-element array binds the extracted value once so the lambda
# reads it twice without a `WITH` alias; `[.]`, `[[]` and `[^ ,}"]` avoid backslashes in an HCL
# heredoc; the single literal space inside `[^ ,}"]` survives the whitespace collapse at the
# resource site.
#
# SAMPLING CAVEAT. The shipper rate-caps ORDINARY rows to 17 per tick, so detection is sampled over
# SHIPPED rows only; a topology change would produce many public rows, so this is adequate. Rows
# the shipper drops never reach Better Stack (they stay in the host-local journald log under its
# size bound). A low-rate public prober inside the high-volume private stream can be sampled out
# for some time. A public address in a top-level field other than `clientIP` is not covered.
#
# FIELD-ORDER CONTRACT. The grade depends on zot writing `clientIP` before `method`/`path`/
# `headers` and on the field name; `treat_as_zero` makes a renamed or reordered field read as
# healthy forever. The drift guard therefore pins the zot image digest the order was verified
# against: a bump of `zot_image_amd64` in zot-registry.tf fails the guard until someone re-runs the
# live population check below and updates the pin.
#
# BOOT FALSE-POSITIVE CHECK. The measured boots show no loopback or docker-NAT value. A localhost
# readiness probe that ever surfaced as `127.0.0.1` alerts BY DESIGN; the predicate is then narrowed
# with evidence, not guessed (the #7530 follow-through probe validates the first post-replace window).
#
# LIVE-PROBED 2026-10-14 against the ClickHouse table (hot remote() UNION ALL s3Cluster archive),
# 7-day window, the predicate's conjuncts verbatim (time bounds replaced by the window):
#   (i)   population: rows carrying a clientIP under the two anchors     -> 18767 (a rolling window: two runs seconds apart differ by a few rows)
#   (ii)  as written                                                      -> 0   (quiet on the live fleet)
#   (iii) positive control: private ranges flagged instead of excluded    -> 18767 (the whole population)
#   (iv)  SOLEUR_ZOT_DISK rows carrying a clientIP                        -> 0
#   (v)   16-literal classification table through the same predicate (RFC 5737 / 3849 documentation
#         addresses, synthetic only; flagged = alerts):
#         0: 10.0.1.10:54321  172.16.0.1:1  172.31.255.255:9  192.168.1.1:80  ::ffff:10.0.0.5  default
#         1: 198.51.100.7:443  127.0.0.1:5000  172.15.0.1:1  172.32.0.1:9  192.169.0.1:80
#            169.254.169.254:80  100.64.0.1:80  [2001:db8::1]:80  2001:db8::1  ::ffff:198.51.100.7
# FIELD ORDER VERIFIED AGAINST zot v2.1.22 @sha256:46f688dc26315a35a247e1784368829e66a67bf91de94c7d8d1645044fac1d5b
# (the running image, heartbeat zot_image_digest=46f688dc2631, at the time of the probe).
#
# WHY IT SHIPS UNPAUSED AT MERGE. The 7-day population is all-private (5 boots, plan-measured), so the rule
# is quiet on arrival. value = 0 with higher_than: ONE shipped public row alerts (there is no
# transient-row tolerance to buy here, unlike the escrow field). The channel is ONE email to the team
# (free tier, no escalation policy; push, call, sms and critical_alert are all false).
locals {
  registry_clientip_not_rfc1918_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND (startsWith(raw, '{"message":"SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry ')
        OR startsWith(raw, '{"message":"SOLEUR_ZOT_DISK '))
      AND arrayExists(n -> (match(n, '^[0-9]{1,3}([.][0-9]{1,3}){3}')
            AND NOT match(n, '^(10[.]|192[.]168[.]|172[.](1[6-9]|2[0-9]|3[01])[.])'))
          OR length(n) - length(replaceAll(n, ':', '')) >= 2,
        [replaceRegexpOne(extract(JSONExtractString(raw, 'message'), 'clientIP[:=]"?([^ ,}"]+)'), '^[[]?(::ffff:)?', '')])
    GROUP BY time
  SQL

  registry_clientip_not_rfc1918_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/registry-clientip-rfc1918-7530.md"
}

resource "logtail_exploration" "registry_clientip_not_rfc1918" {
  name      = "soleur-registry-clientip-not-rfc1918-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    # Single-line at the resource site, for the same perpetual-diff reason as the siblings above.
    sql_query = replace(trimspace(local.registry_clientip_not_rfc1918_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "registry_clientip_not_rfc1918" {
  exploration_id = logtail_exploration.registry_clientip_not_rfc1918.id
  name           = "soleur-registry-clientip-not-rfc1918-prd"

  # One shipped public-address row in a 900 s window alerts by email (no tolerance; email-only on the free tier). The
  # window covers the */5 heartbeat and the shipper's per-tick envelopes; recovery_period covers two
  # windows so one clean bucket does not close an incident the next would re-open.
  alert_type          = "threshold"
  operator            = "higher_than"
  value               = 0
  check_period        = 300
  query_period        = 900
  confirmation_period = 0
  recovery_period     = 1800
  # A count query with no rows returns NO bucket, which must read as healthy (0) so an open
  # incident can observe recovery. Silence is NOT this rule's job: registry_store_not_luks, the
  # registry heartbeats (zot-registry.tf) and scheduled-zot-restart-loop.yml own liveness.
  on_missing_data = "treat_as_zero"

  paused = false

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "The registry plane shipped a clientIP outside RFC1918 (a public or non-private address on a SOLEUR_ZOT_LOG or SOLEUR_ZOT_DISK row), so a client address may now be personal data on rows already in flight. Fix the ingress cause first; do not paste the address anywhere. Runbook: ${local.registry_clientip_not_rfc1918_runbook_url}"
  metadata = {
    runbook = local.registry_clientip_not_rfc1918_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}

# ── #8611 / ADR-243: Anthropic spend — a step outliving the proxy, and the daily burn ───────────
#
# WHY THESE EXIST. The self-hosted Inngest server calls every step at the Cloudflare-proxied
# serveOrigin, and Cloudflare gives up on an origin response after ~100 s. A claude-eval step that
# outlives that gets a 524, `retries: 1` re-invokes it while the first Claude session is still
# running, and the run fails anyway: 51% of 30-day cron spend was those duplicates and a $50
# top-up lasted ~39 h. Three standing alarms, one per question:
#   (1) inngest_step_524         — is a step being cut at the proxy again? (per 15 min)
#   (2) claude_cost_daily_burn   — is the cron fleet spending more than $25 in 24 h?
#   (3) claude_cost_capture_dark — has the cost telemetry itself gone dark for 24 h?
# (2) cannot fire on silence (treat_as_zero reads "no rows" as $0), which is why (3) exists.
# (2) is a FLOOR on spend, not the total: a marker with a null cost_usd (a timeout, a no-result or
# parse-error exit, the HTTP-transport crons compound-promote / weekly-release-digest / the credit
# probe) sums as $0, and a run killed mid-flight emits no marker at all.
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
# calendar-aligned bucket splits a trailing 24 h across two partial days — $40 of spend would read
# as two sub-$25 buckets, and every early-UTC evaluation of (3) would see a near-empty bucket and
# page. The window filter is therefore on the `dt` COLUMN, never on the `time` alias: here the
# alias is a constant, so `time BETWEEN …` would be always-true and sum the source's entire
# history (measured in the probe: $58.64 for a day whose real total is $34.41).
# query_period 86400 is NOT validated client-side by the logtail provider (v11.2.0 schema:
# "The query evaluation window in seconds", no bound) and the largest live precedent in this file
# is 5400. If the API rejects it, the create fails the apply step loudly (no silent state); fall
# back to 5400 and scale (2) to $25 x 5400 / 86400 ~= $1.56 per window (local.claude_cost_daily_burn_usd
# is the single place to change), recorded in ADR-243.
#
# CREDIT EXHAUSTION IS NOT A TELEMETRY FAILURE. (3)'s arm B counts the credit probe's own
# `anthropic-credit-exhausted` / `anthropic-key-invalid` rows (hourly while RED), so a zero-spend
# day with no credit is quiet. That page is the credit probe's (Sentry monitor
# scheduled-anthropic-credit-probe), not this rule's.
locals {
  # (1) Field-isolated rather than `raw LIKE '%…524%'`: GitHub webhook payloads (issue and PR
  # bodies) reach this source, and this very incident's issues quote the literal. No PRIORITY
  # filter — the live lines are PRIORITY 6. They ship even though vector.toml's inngest_journald
  # source listed `include_matches.PRIORITY = 0..4` at OBSERVATION time (18 rows, 2026-09-16..23 — PRIORITY 3 in bounds then and now; the #10255 partition narrowed the arm to {3,4}): the source's
  # `include_units` admits the unit independently of the PRIORITY match (Vector appears to OR the
  # two; the same mechanism is the suspect in #6551). That behaviour is load-bearing for this alert
  # and is pinned by vector-pii-scrub.test.sh; scripts/probe-inngest-524-count.sh prints unit_rows
  # as the positive control, so "no inngest-server rows ship" can never read as "no 524s".
  inngest_step_524_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND JSONExtractString(raw, '_SYSTEMD_UNIT') = 'inngest-server.service'
      AND multiSearchAny(JSONExtractString(raw, 'message', 'error'), ['invalid status code: 524', 'error parsing stream: error reading response body', 'Your server reset the connection while we were reading the reply'])
    GROUP BY time
  SQL
  # The two later needles are the inngest v1.45.1 inngest-server `error` texts for a step STREAM that
  # dropped mid-response, measured in the #8611 spike (streaming-spike.md): S7's network cut and
  # app kill -> "error parsing stream: error reading response body to check for status code:
  # unexpected end of JSON input"; S3's ~20-min drop -> "Your server reset the connection while we
  # were reading the reply: Unexpected ending response". Under streaming a 524 should not recur,
  # so these are the live form of the same failure. A web deploy that kills a running step also
  # matches — one page per such deploy is the accepted cost. One array, one alert.

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

  # The burn threshold, in dollars per trailing 24 h. $25 clears a healthy Monday (the per-site
  # medians already sum ~$13 before daily-triage and follow-through, newly metered by #8611) and a
  # 1st-of-quarter day, while staying under the $28–34 duplicate-storm days probed above.
  # Recalibrate after 14 funded days (#8613). Interpolated into the alert's value AND its email text.
  claude_cost_daily_burn_usd = 25

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

  # #11068 — push armed under the #9168 measured-flip convention; revert to `push = false` if the apply refuses it.
  email          = true
  push           = true
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "The Inngest server lost a function step's response: HTTP 524 through Cloudflare, or a streamed step response that dropped mid-flight ('error parsing stream' / 'reset the connection'). A web deploy that killed a running step also matches. The retry joins the live Claude child when the single-flight guard holds (Sentry op claude-eval-singleflight-join). Runbook: ${local.claude_spend_runbook_url}"
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

  # See local.claude_cost_daily_burn_usd for the threshold's rationale. The window is a trailing
  # 24 h checked hourly; spend ages out of it, so recovery needs no slack.
  alert_type          = "threshold"
  operator            = "higher_than"
  value               = local.claude_cost_daily_burn_usd
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

  incident_cause = "The claude-eval cron fleet spent more than USD ${local.claude_cost_daily_burn_usd} of operator Anthropic credit in the last 24 h (SOLEUR_CLAUDE_COST cost_usd, cron sources; a floor: null-cost markers sum as $0). Runbook: ${local.claude_spend_runbook_url}"
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

# ── #8706: web-1's daily LUKS at-rest probe has stopped reporting ───────────────────────────────
# luks-monitor.timer never existed on web-1 for nine weeks and nothing noticed: the shared
# betteruptime_heartbeat.workspaces_luks has a second pusher (workspaces-luks-verify.yml, over SSH)
# that kept it green. This alert singles out the HOST unit on web-1. Under luks-monitor.service
# every log() line is journaled twice; the stdout copy carries _SYSTEMD_UNIT (measured 100% on the
# stdout rows of sibling web-1 units such as web-private-nic-guard.service, whose SyslogIdentifier
# also differs from its unit name; luks-monitor.service itself has never run). logger rows drop it
# about half the time. The verify job's rows carry session-N.scope or no unit, so they can never
# keep this quiet. host_name scopes it to web-1: web-2 (soleur-web-2) ships to the same source.
#
# Window: OnCalendar=daily + RandomizedDelaySec=1800 can space two runs 24h30m (88200 s) apart,
# so a 24 h window would read empty for up to 30 minutes on a healthy day. 27 h (97200 s) covers it
# with margin. Pages about 27 h after the last good host run; a Vector or Logs-source outage trips
# it too (the runbook's decode says to check the pipeline before the host).
#
# Live-probed 2026-09-27 (7 days, hot+archive): as written 0 (the dark state this pages on);
# control with the unit swapped for inngest-heartbeat.service and no needle 39228; the unit
# conjunct dropped 9 (the verify job's OK rows — the unit conjunct is what excludes them).
# The host_name conjunct was added at review (2026-09-27): stdout rows from web-1 units read
# host_name='soleur-web-platform', web-2's read 'soleur-web-2' (measured over 2 days).
locals {
  luks_monitor_host_timer_sql = <<-SQL
    SELECT toDateTime({{end_time}}) AS time, count(*) AS value
    FROM {{source}}
    WHERE dt BETWEEN {{start_time}} AND {{end_time}}
      AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor'
      AND JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service'
      AND JSONExtractString(raw, 'message') LIKE '%OK: /mnt/data is LUKS-backed%'
      AND JSONExtractString(raw, 'host_name') = 'soleur-web-platform'
  SQL

  luks_monitor_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md#host-timer-liveness-alert-8706"
}

resource "logtail_exploration" "luks_monitor_host_timer_dark" {
  name      = "soleur-luks-monitor-host-timer-dark-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    # Single-line at the resource site, for the same perpetual-diff reason as the siblings above.
    sql_query = replace(trimspace(local.luks_monitor_host_timer_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "luks_monitor_host_timer_dark" {
  exploration_id = logtail_exploration.luks_monitor_host_timer_dark.id
  name           = "soleur-luks-monitor-host-timer-dark-prd"

  alert_type          = "threshold"
  operator            = "lower_than"
  value               = 1
  check_period        = 3600
  query_period        = 97200
  confirmation_period = 0
  recovery_period     = 3600
  # A missing value must read as 0 so silence FIRES (the claude_cost_capture_dark precedent).
  on_missing_data = "treat_as_zero"

  paused = false

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "web-1's nightly encryption self-check (luks-monitor.service) has not recorded a PASSING run in about 27 hours. Either the host check is not running, or it runs and fails one of its checks; a failing check is the incident, so look first for a luks-monitor FAIL row or a workspaces-luks-drift event. First step: check whether ANY luks-monitor rows arrived at all; total silence means the log pipeline, not the host. The daily workspaces-luks-verify job checks the volume independently. Runbook: ${local.luks_monitor_runbook_url}"
  metadata = {
    runbook = local.luks_monitor_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}

# ── #9045: the workspaces-LUKS dead-man FIRED on web-1 ──────────────────────────────────────────
# The cutover arms a transient systemd timer (workspaces-cutover.sh arm_dead_man) that reverts web-1
# to the plaintext volume if the attended run dies inside the freeze window. A fire is unattended by
# construction (the SIGKILL residual, or any future path that leaves the timer armed), and on
# 2026-07-20 one remounted the plaintext over a healthy LUKS mount with nothing paging for ~6 h
# (#6812). The fire command's FIRST act is
#   logger -t luks-monitor -- 'SOLEUR_WORKSPACES_LUKS_DEADMAN feature=workspaces-luks op=workspaces-luks-deadman result=fired reason=timer_elapsed'
# and this alert pages on that row. Its later result=ok / result=fail rows say how the revert
# ended; the runbook reads them. arm_failed / cutover_aborted are NOT here. Sentry
# (sentry_alert.workspaces_luks_drift) pages only the rows whose path also calls emit_drift:
# arm_failed (deadman_arm_failed), disarm_failed (deadman_disarm_failed), and a cutover_aborted
# whose cleanup() rolled back (rollback_engaged) or rolled forward past the canary
# (cutover_aborted_post_canary). A plain `result=cutover_aborted outcome=pre_freeze` row, from a
# die() that never called emit_drift, pages NOTHING: it is only in the run log and Better Stack.
# Nothing was frozen on that path, and no alert watches it.
#
# Paging semantics are monitor_send_failed's (ADR-218): any one matching row in a bucket pages,
# treat_as_zero so the open incident observes recovery. Scoped by tag AND host (web-2 ships to the
# same source) AND the marker at the start of the message, so a row that merely QUOTES the marker
# (a systemd "Started …" line under another identifier, or an echoed command line) cannot page;
# the cutover scrubs `=` to `_` in any free-text detail= field, so no arm-failure text can spoof it.
# LIVE-PROBED 2026-09-28 (s3Cluster archive, 60 days; no fired row is retained, the only fire was
# 2026-07-20): as written 0; the same tag+host with the marker swapped for SOLEUR_WORKSPACES_READYZ
# and the needle for `ready=true writable=true` 36 (positive control: every conjunct shape is live
# SQL that matches this tag's logger rows on web-1, which carry host_name='soleur-web-platform').
locals {
  workspaces_luks_deadman_fired_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor'
      AND JSONExtractString(raw, 'host_name') = 'soleur-web-platform'
      AND startsWith(JSONExtractString(raw, 'message'), 'SOLEUR_WORKSPACES_LUKS_DEADMAN ')
      AND position(JSONExtractString(raw, 'message'), 'op=workspaces-luks-deadman result=fired') > 0
    GROUP BY time
  SQL

  workspaces_luks_deadman_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md#dead-man-and-abort-triage-9045"
}

resource "logtail_exploration" "workspaces_luks_deadman_fired" {
  name      = "soleur-workspaces-luks-deadman-fired-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    # Single-line at the resource site, for the same perpetual-diff reason as the siblings above.
    sql_query = replace(trimspace(local.workspaces_luks_deadman_fired_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "workspaces_luks_deadman_fired" {
  exploration_id = logtail_exploration.workspaces_luks_deadman_fired.id
  name           = "soleur-workspaces-luks-deadman-fired-prd"

  # monitor_send_failed's values: one row pages within about a minute, the 5-min window holds ONE
  # incident across the fire's result=fired / result=ok pair, and 10 quiet minutes auto-resolve it.
  alert_type          = "threshold"
  operator            = "higher_than"
  value               = 0
  check_period        = 60
  query_period        = 300
  confirmation_period = 0
  recovery_period     = 600
  on_missing_data     = "treat_as_zero"

  paused = false

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "The workspaces-LUKS dead-man FIRED on web-1: the cutover's backstop timer ran. While the retained plaintext volume still exists, a fire stops the app, unmounts the encrypted /workspaces volume and remounts the plaintext one (result=ok reason=plaintext_remounted), so writes since the freeze may be stranded on the LUKS volume. Once the plaintext wipe (#6604 step 7) has run, a fire refuses instead (result=fail reason=refused_plaintext_wiped or refused_plaintext_record_gone) and leaves the LUKS mount untouched. Read the SOLEUR_WORKSPACES_LUKS_DEADMAN rows (result= and reason=) to see how it ended, then follow the runbook. This incident auto-resolves after 10 quiet minutes; resolution does NOT mean any stranded writes were reconciled, only that no new fire row arrived. Runbook: ${local.workspaces_luks_deadman_runbook_url}"
  metadata = {
    runbook = local.workspaces_luks_deadman_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}

# ── #9342: a deploy was rolled back by the BLOCKING bwrap sandbox probe ─────────────────────────
# The canary stage of ci-deploy.sh runs a blocking bwrap probe. When it fails the deploy rolls back
# (reason=canary_sandbox_failed) and the script writes exactly one journald row under
# `logger -t ci-deploy`, whose message STARTS with
#   DEPLOY_ROLLBACK: bwrap sandbox non-functional in <image>:<tag> rc=… ms=… cstate=… err_chars=… bwrap_err="…"
# Before this alert a recurrence was visible only through the release-failure email (which has
# failed once: RESEND_API_KEY unset, 2026-09-27), the workflow ::error:: annotation, or a hand-run
# query. The 16-rollbacks-in-7-days flake behind it was the docker-exec PDEATHSIG race, removed by
# dropping --die-with-parent from the probe. The steady state is EXPECTED to be zero rows once that fix
# is deployed on every host (a full post-deploy day has not been observed yet), so read ms and cstate
# before treating a match as a new regression. The runbook (canary-probe-set.md) is the no-SSH decode.
#
# Paging semantics are monitor_send_failed's (ADR-218): any one matching row in a bucket alerts,
# treat_as_zero so the open incident observes recovery. On the free tier the channel is team email
# only; escalation applies on the paid tier.
#
# Scoped by tag AND the marker at the START of the message, so a row that merely QUOTES the marker
# (inngest ships GitHub-webhook logs quoting issue and PR bodies to this same source, under another
# identifier) cannot alert.
# NO host_name conjunct, on purpose — this DIVERGES from the workspaces-luks dead-man sibling above.
# The signal belongs to every deploy host, not one: live `ci-deploy` rows come from three host_name
# values (soleur-web-platform, soleur-web-2, and soleur-inngest-prd, which is web-1's name before
# 2026-09-19). A host conjunct would silently exclude web-2 and the pre-rename rows. The drift guard
# (bwrap-probe-rollback-alert.test.sh, row R4) reds on the harmonising edit.
# LIVE-PROBED 2026-10-01 (hot remote() UNION s3Cluster archive, 14 days): the exact predicate below
# matched 19 real rows across 8 UTC days, all of the PDEATHSIG-flake shape per the plan-time decode
# (rc=137, ms 73-104; the rows themselves are not committed) — the positive control that the predicate
# shape matches live rows. The
# same predicate with the needle changed to `…non-functionalX` returns 0.
# Both -target= lines are enforced only by this alert's own drift guard (see header step 4).
locals {
  bwrap_probe_rollback_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'ci-deploy'
      AND startsWith(JSONExtractString(raw, 'message'), 'DEPLOY_ROLLBACK: bwrap sandbox non-functional')
    GROUP BY time
  SQL

  bwrap_probe_rollback_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/canary-probe-set.md#blocking-bwrap-sandbox-probe--reading-its-self-report-8016-pr-8026"
}

resource "logtail_exploration" "bwrap_probe_rollback" {
  name      = "soleur-bwrap-probe-rollback-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    # Single-line at the resource site, for the same perpetual-diff reason as the siblings above.
    sql_query = replace(trimspace(local.bwrap_probe_rollback_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "bwrap_probe_rollback" {
  exploration_id = logtail_exploration.bwrap_probe_rollback.id
  name           = "soleur-bwrap-probe-rollback-prd"

  # monitor_send_failed's values: one row alerts within about a minute, the 5-min window holds ONE
  # incident across a CI retry's repeated rollback rows, and 10 quiet minutes auto-resolve it.
  alert_type          = "threshold"
  operator            = "higher_than"
  value               = 0
  check_period        = 60
  query_period        = 300
  confirmation_period = 0
  recovery_period     = 600
  on_missing_data     = "treat_as_zero"

  paused = false

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "No user-facing outage: a release was blocked and rolled back; production still runs the previous version. The canary's blocking bwrap probe failed (reason canary_sandbox_failed). The email has no row body: read it without SSH via the runbook's Query block, taking rc, ms and cstate from the ci-deploy row only. Remediation is GitHub Re-run failed jobs on the release run. This incident auto-resolves after 10 quiet minutes; resolution does NOT mean the cause was found. Runbook: ${local.bwrap_probe_rollback_runbook_url}"
  metadata = {
    runbook = local.bwrap_probe_rollback_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}

# ── #9391 / ADR-096: a host's hosts-file GHCR deny is no longer in force ────────────────────────
#
# WHAT IT DETECTS. Every host carries a hosts-file deny that sinkholes ghcr.io to 0.0.0.0. It is an
# accident guard on NAME RESOLUTION (ADR-096, Amendment 2026-09-30), not an egress control, and deploy
# pulls are zot-only since #8036, so no deploy depends on it. Two emitters report whether it is in
# force, and value 0 means ghcr.io resolved to a real address:
#   * web hosts (web-1, web-2): ci-deploy writes `logger -t ci-deploy "GHCR_DENY ghcr_blocked=<1|0|unknown>"`
#     on every ci-deploy.sh invocation that passes validation (deploy, restart, quiesce, enable), before
#     flock. The whole message is that string, so arm W compares it for EQUALITY;
#   * the registry host: its SOLEUR_ZOT_DISK heartbeat (every five minutes, a direct POST with no Vector,
#     so the row has NO host_name key: the host is the in-message `host=` token) carries
#     ` ghcr_blocked=<…> ` in the head, BEFORE the attacker-influenced free text ` zot_last_err=`; arm R
#     scopes the match to the head as registry_store_not_luks does.
# What is exposed when the deny is lost: host processes and host-network containers resolving ghcr.io
# (bridge containers are covered by the #9275 carve once it is delivered, #9393). The Sentry op `ghcr_deny_lost` (cron-egress-resolve.sh)
# watches that carve from inside the app container, a different property.
#
# WHAT IT DELIBERATELY DOES NOT DETECT, and so reads as quiet:
#   * `unknown` (ghcr.io does not resolve): not the deny regressing, and a blind probe is silence, not health;
#   * a web host that has not run ci-deploy since the loss: the web arm is a sample per invocation, not a
#     monitor, so it can never precede the pull it would have guarded, and an idle host is not sampled;
#   * a host whose ci-deploy.sh predates the GHCR_DENY line (#9169);
#   * a registry row whose message does not parse: arm R is a positive match, so it is fail-QUIET where
#     registry_store_not_luks is fail-loud on the same row (`[ci/zot-telemetry-silent]` covers ABSENT
#     registry rows only);
#   * a compromised host: both arms are self-reports, so this is a drift alarm, not a tamper-evident control.
#
# HOW IT RESOLVES. The incident closes after quiet minutes (recovery_period), which says nothing about the
# cause: a deny lost on a web host stays lost until a delivery re-asserts it, and the next ci-deploy writes
# value 0 again. The per-host repair routes are in the runbook, not here.
#
# Paging semantics are registry_store_not_luks's measured combination (check 300 / query 900 / recovery 1800):
# the registry heartbeat is */5, so one 900 s bucket holds up to three of its rows and the incident does not
# flap across one gap. `higher_than 0`: a single value-0 row is the signal on either arm. Free tier: team
# email only; the paid tier escalates.
#
# NO host_name conjunct, on purpose: web-1 (`soleur-web-platform`, and `soleur-inngest-prd` before
# 2026-09-19), web-2 (`soleur-web-2`) and the registry host (no host_name at all) all carry these rows. The
# drift guard (ghcr-blocked-alert.test.sh, row M9) reds on the harmonising edit.
#
# LIVE-PROBED 2026-10-04 (hot remote() UNION s3Cluster archive, 14-day window, counts only), the predicate
# below. The fields shipped on 2026-09-28 (registry heartbeat) and 2026-09-30 (web GHCR_DENY), so the window
# holds about six and four days of emissions:
#   (1) as written, arm W 1 (a web-1 row from 2026-09-30, a minute before web-2's first row), arm R 0;
#   (2) positive controls, the needle changed to value 1: arm W 97 (web-1 49, web-2 48), arm R 1,669;
#   (3) a loose variant (any row containing `ghcr_blocked=0`, no identifier scoping, no equality): 14, so
#       the scoping excludes 13 rows that merely QUOTE the marker: inngest GitHub-webhook payload logs
#       (identifier `doppler`, host `soleur-inngest-prd`) carrying issue and PR text.
# Both -target= lines are enforced only by this alert's own drift guard (see header step 4).
locals {
  ghcr_hostsfile_deny_lost_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND (
        (JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'ci-deploy'
          AND JSONExtractString(raw, 'message') = 'GHCR_DENY ghcr_blocked=0')
        OR (startsWith(raw, '{"message":"SOLEUR_ZOT_DISK ')
          AND position(JSONExtractString(raw, 'message'), 'SOLEUR_ZOT_DISK ') = 1
          AND position(JSONExtractString(raw, 'message'), ' ghcr_blocked=0 ') > 0
          AND position(JSONExtractString(raw, 'message'), ' ghcr_blocked=0 ') < position(JSONExtractString(raw, 'message'), ' zot_last_err='))
      )
    GROUP BY time
  SQL

  ghcr_hostsfile_deny_lost_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md#hosts-file-deny-lost-better-stack-alert"
}

resource "logtail_exploration" "ghcr_hostsfile_deny_lost" {
  name      = "soleur-ghcr-hostsfile-deny-lost-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    # Single-line at the resource site, for the same perpetual-diff reason as the siblings above.
    sql_query = replace(trimspace(local.ghcr_hostsfile_deny_lost_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "ghcr_hostsfile_deny_lost" {
  exploration_id = logtail_exploration.ghcr_hostsfile_deny_lost.id
  name           = "soleur-ghcr-hostsfile-deny-lost-prd"

  # See "Paging semantics" above: registry_store_not_luks's windows, with higher_than 0 because one value-0
  # row is the signal on either arm. recovery_period covers two windows so one good bucket does not close an
  # incident the next would re-open.
  alert_type          = "threshold"
  operator            = "higher_than"
  value               = 0
  check_period        = 300
  query_period        = 900
  confirmation_period = 0
  recovery_period     = 1800
  # A count query with no rows returns NO bucket, which must read as healthy (0) so an open incident can
  # observe recovery. Silence is NOT this rule's job (see WHAT IT DELIBERATELY DOES NOT DETECT).
  on_missing_data = "treat_as_zero"

  paused = false

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "A host reports that its hosts-file GHCR deny is no longer in force: ghcr.io resolved to a real address (ci-deploy GHCR_DENY ghcr_blocked=0 on a web host, or the registry heartbeat's ghcr_blocked=0). The deny is an accident guard on name resolution and deploy pulls are zot-only, so this is not a deploy or user outage; host processes and host-network containers on that host could resolve ghcr.io. The web arm samples only when ci-deploy runs. This incident auto-resolves after 30 quiet minutes, which does NOT mean the deny is back. Decode the arm and host, and pick the repair route per host, in the runbook: ${local.ghcr_hostsfile_deny_lost_runbook_url}"
  metadata = {
    runbook = local.ghcr_hostsfile_deny_lost_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}

# ── #9534: egress gateway — deny-class spike + probe silence + probe failure ────
#
# WHAT THEY DETECT. The gateway's sole security surface is its deny decisions
# (Squid TCP_DENIED on the shared CIDR ACL + kernel `egress-gw-deny:` drops are
# the same class). A spike means something is actively probing internal space —
# a prompt-injected session reaching for metadata/RFC1918, or a confused-deputy
# forwarder. During the PR-A dark launch the only legitimate deny traffic is the
# synthetic probe's one row per 5 min, so a sustained rate above that pages.
#
# The heartbeat alert is the absence detector: cron-egress-resolve emits one
# `egress_gw_probe` line every 5 min per host under SYSLOG_IDENTIFIER=egress-gw-probe.
# Silence means the resolver timer died, the Vector pipeline stopped shipping
# (measured 2026-10-12: a stale birth-frozen vector.toml dropped web-2's rows at
# the Source-4 allowlist while the probe ran — journald had them, Better Stack
# never saw them), or the host journal is dead — none of which may read as
# green. The count is DISTINCT host_name over the whole window (ADR-218's
# amendment): a source-multiplexed aggregate where one host's rows keep the
# sum above threshold while the other host is dark is exactly the failure this
# alert exists for, so it pages when the emitting-host count drops below the
# fleet roster (length(var.web_hosts)).
#
# egress_gw_probe_fail is the verdict detector: result=fail rows (allow leg
# refused, deny leg bypassed) are security-relevant on first sight, and
# reason=gw_absent rows mean the probe's gateway check failed — the gateway
# container missing is an incident, not noise. The deny SPIKE deliberately does
# not key on the probe row: it counts SQUID decisions, which a dead gateway
# cannot produce either — the rules cover distinct failure arms (no gateway at
# all vs a live gateway mis-ACL'd vs a live gateway returning wrong verdicts).
#
# WHAT THEY DELIBERATELY DO NOT DETECT: allowed-traffic abuse/volume anomalies
# (documented gap — CMO review; tracked in the spec's open questions), and
# domain-fronting/SNI-vs-CONNECT drift (Squid cannot see past the tunnel; the
# residual is recorded in the ADR).
locals {
  # Squid's soleur_json logformat puts the decision in `decision` (%Ss);
  # TCP_DENIED is Squid's refusal class (ACL deny + auth deny both land here —
  # a brute-forcing unauthenticated client is the same signal worth paging).
  egress_gw_deny_spike_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND JSONExtractString(raw, 'CONTAINER_NAME') = 'soleur-egress-gw'
      AND position(JSONExtractString(raw, 'message'), 'TCP_DENIED') > 0
    GROUP BY time
  SQL

  # Whole-window scalar (ADR-218's host-mask amendment): one value per window =
  # how many DISTINCT hosts shipped a probe row in it. count(*) would let one
  # healthy host's ~3 beats keep a 2-host fleet above a row threshold while the
  # other host ships nothing. `host_name` is Vector's injected per-host field
  # (`soleur-web-platform` / `soleur-web-2`).
  egress_gw_probe_silent_sql = <<-SQL
    SELECT toDateTime({{end_time}}) AS time, count(DISTINCT JSONExtractString(raw, 'host_name')) AS value
    FROM {{source}}
    WHERE dt BETWEEN {{start_time}} AND {{end_time}}
      AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'egress-gw-probe'
  SQL

  # Verdict failures. `result=fail` covers allow-leg refused AND deny-bypassed;
  # `reason=gw_absent` is the skip class where the gateway container is missing
  # (the probe cannot run at all — same severity, different mechanism). Other
  # skip reasons (budget, container_absent, no_gw_ip, token_dir_unwritable) are
  # transient-host conditions the silent alert already owns; paging on them
  # double-fires the same fault.
  egress_gw_probe_fail_sql = <<-SQL
    SELECT toDateTime({{end_time}}) AS time, count(*) AS value
    FROM {{source}}
    WHERE dt BETWEEN {{start_time}} AND {{end_time}}
      AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'egress-gw-probe'
      AND (position(JSONExtractString(raw, 'message'), 'result=fail') > 0
        OR position(JSONExtractString(raw, 'message'), 'reason=gw_absent') > 0)
  SQL

  egress_gw_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md#egress-gateway-better-stack-alerts"
}

resource "logtail_exploration" "egress_gw_deny_spike" {
  name      = "soleur-egress-gw-deny-spike-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    sql_query       = replace(trimspace(local.egress_gw_deny_spike_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "egress_gw_deny_spike" {
  exploration_id = logtail_exploration.egress_gw_deny_spike.id
  name           = "soleur-egress-gw-deny-spike-prd"

  # > 20 deny rows in 5 min. Dark-launch baseline is ~1 row per probe pair; the
  # 20x headroom keeps a few noisy-but-legit client retries sub-paging while any
  # sustained internal-space scan clears it in one window.
  alert_type          = "threshold"
  operator            = "higher_than"
  value               = 20
  check_period        = 300
  query_period        = 300
  confirmation_period = 0
  recovery_period     = 1800
  on_missing_data     = "treat_as_zero"

  paused = false

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "Sustained Squid TCP_DENIED volume on soleur-egress-gw — sessions are attempting CONNECT to denied destination classes (metadata/RFC1918/ULA). Check which workspace tokens are generating denies; revocation is deleting the token file. Runbook: ${local.egress_gw_runbook_url}"
  metadata = {
    runbook = local.egress_gw_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}

resource "logtail_exploration" "egress_gw_probe_silent" {
  name      = "soleur-egress-gw-probe-silent-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    sql_query       = replace(trimspace(local.egress_gw_probe_silent_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "egress_gw_probe_silent" {
  exploration_id = logtail_exploration.egress_gw_probe_silent.id
  name           = "soleur-egress-gw-probe-silent-prd"

  # Fewer emitting HOSTS than the fleet roster in 15 min (each host's probe
  # emits every 5 min when due). count(DISTINCT host_name) — a multiplexed row
  # count would let web-1's beats mask a dead web-2 probe pipeline (the
  # pre-amendment defect). treat_as_zero makes a fully-dark window read as 0.
  alert_type          = "threshold"
  operator            = "lower_than"
  value               = length(var.web_hosts)
  check_period        = 300
  query_period        = 900
  confirmation_period = 0
  recovery_period     = 900
  on_missing_data     = "treat_as_zero"

  paused = false

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "Fewer than the expected ${length(var.web_hosts)} web hosts emitted an egress_gw_probe heartbeat in 15+ min — a resolver timer, Vector pipeline (stale Source-4 allowlist on one host is a measured failure mode), or host journal is dead. The gateway's allow/deny verification is dark on the silent host(s). Runbook: ${local.egress_gw_runbook_url}"
  metadata = {
    runbook = local.egress_gw_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}

# A live probe returning WRONG verdicts (allow refused / deny bypassed) or
# reporting its gateway missing: previously Sentry-only (op egress_gw_probe_fail),
# which pages nobody. >0 rows in 15 min — a real failure recurs every 5 min while
# broken; a single deny_bypassed row is already security-critical.
resource "logtail_exploration" "egress_gw_probe_fail" {
  name      = "soleur-egress-gw-probe-fail-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    sql_query       = replace(trimspace(local.egress_gw_probe_fail_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "egress_gw_probe_fail" {
  exploration_id = logtail_exploration.egress_gw_probe_fail.id
  name           = "soleur-egress-gw-probe-fail-prd"

  alert_type          = "threshold"
  operator            = "higher_than"
  value               = 0
  check_period        = 300
  query_period        = 900
  confirmation_period = 0
  recovery_period     = 900
  on_missing_data     = "treat_as_zero"

  paused = false

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "The egress gateway CONNECT probe returned result=fail (allow leg refused, or deny leg BYPASSED — Squid accepted a denied destination) or reported reason=gw_absent (gateway container missing). Check the incident's host_name; a deny_bypassed row means the private-CIDR policy is not in force. Runbook: ${local.egress_gw_runbook_url}"
  metadata = {
    runbook = local.egress_gw_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}

# ── #10321 / ADR-218: credential shapes in the zot container-log channel ─────
#
# WHY THIS EXISTS. scripts/followthroughs/zot-log-channel-7440.sh carried the only
# automated read of what the registry shipper's redact() actually emits on this
# source — its exit-1 arm flags three credential shapes in shipped SOLEUR_ZOT_LOG
# rows. Its tracker #7455 closed on PASS 2026-08-13 and scripts/sweep-followthroughs.sh
# reads only open issues plus closed ones inside CLOSED_LOOKBACK_DAYS=14, so the
# arm has been dormant since ~2026-08-27 while its header still claimed
# "enrolled as a REGRESSION detector" (#10321). A check meant to outlive its
# tracker is a standing alert, not a follow-through probe — the same vehicle the
# 2026-10-14 CTO ruling gave the sibling clientIP invariant (#7530). The probe
# file stays as the manual deep-grader.
#
# THE THREE SHAPES (ported from the probe's authleak/shapeleak arms):
#   (a) any `Authorization:[<v>` value that is neither the zot `***` mask (three
#       or more asterisks) nor the shipper's REDACTED marker — evaluated per
#       OCCURRENCE so a leading decoy cannot hide a real credential on the same
#       row (probe fixture S13); a literal `Authorization:[]` is benign while
#       `Authorization:[ ` (a value that empties after the space cut) fails loud,
#       matching the probe's malformed-unmasked arm.
#   (b) a Doppler token prefix `dp.(pt|st|sa|ct).` followed by a token run with
#       >=16 non-separator chars (`._-` stripped — substance, not length, so 20
#       dots of padding cannot post a page on demand).
#   (c) a bcrypt prefix `$2[aby]$<2 digits>$`.
# Unlike the probe — whose newest-boot scoping existed to attribute DELIVERY —
# every matching row fires: a credential-shaped row on any host generation is an
# incident. COVERAGE BOUNDARY (named, not hidden): shapes outside these three
# patterns, rows the shipper's rate cap never emitted, and a leak on another
# source are not this alert's.
#
# LIVE-PROBE: not run (the predicate is a port of the probe's tested arms, not a
# new hypothesis; the drift guard asserts each arm on the as-written SQL text).

locals {
  registry_zot_log_credential_shape_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND startsWith(raw, '{"message":"SOLEUR_ZOT_LOG ')
      AND position(JSONExtractString(raw, 'message'), 'SOLEUR_ZOT_LOG ') = 1
      AND (
        arrayExists(
          v -> v != 'Authorization:[' AND NOT match(v, '^Authorization:\\[(\\*\\*\\*|REDACTED)'),
          extractAll(JSONExtractString(raw, 'message'), 'Authorization:\\[[^\\]\\s]*')
        )
        OR match(JSONExtractString(raw, 'message'), 'Authorization:\\[\\s')
        OR arrayExists(
          t -> length(replaceRegexpAll(t, '^dp\\.(?:pt|st|sa|ct)\\.|[._-]', '')) >= 16,
          extractAll(JSONExtractString(raw, 'message'), 'dp\\.(?:pt|st|sa|ct)\\.[A-Za-z0-9._-]+')
        )
        OR match(JSONExtractString(raw, 'message'), '\\$2[aby]\\$[0-9][0-9]\\$')
      )
    GROUP BY time
  SQL

  registry_zot_log_credential_shape_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/registry-zot-credential-shape-10321.md"
}

resource "logtail_exploration" "registry_zot_log_credential_shape" {
  name      = "soleur-registry-zot-log-credential-shape-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    # Single-line at the resource site, for the same perpetual-diff reason as the siblings above.
    sql_query = replace(trimspace(local.registry_zot_log_credential_shape_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "registry_zot_log_credential_shape" {
  exploration_id = logtail_exploration.registry_zot_log_credential_shape.id
  name           = "soleur-registry-zot-log-credential-shape-prd"

  # value = 0 with higher_than: ONE credential-shaped row is a page — unlike
  # registry_store_not_luks there is no transient benign row for this signal.
  # recovery_period covers two windows so one clean bucket does not close an
  # incident the next would re-open.
  alert_type          = "threshold"
  operator            = "higher_than"
  value               = 0
  check_period        = 300
  query_period        = 900
  confirmation_period = 0
  recovery_period     = 1800
  # A count query with no rows returns NO bucket, which must read as healthy (0)
  # so an open incident can observe recovery. Silence is NOT this rule's job:
  # the channel going dark is covered by the registry heartbeats
  # (betteruptime_heartbeat.registry_prd; the ci/zot-telemetry-silent arm).
  on_missing_data = "treat_as_zero"

  paused = false

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "A shipped SOLEUR_ZOT_LOG row carries something shaped like a credential: an unmasked Authorization value (neither the *** mask nor REDACTED), a Doppler token prefix dp.(pt|st|sa|ct). with a substantive run, or a bcrypt $2[aby]$ hash. The registry push/pull credential protects the image supply chain — rotate the affected credential FIRST, then fix redact(). Counts only: never echo the matched value. Runbook: ${local.registry_zot_log_credential_shape_runbook_url}"
  metadata = {
    runbook = local.registry_zot_log_credential_shape_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}

# ── #10445: a live agent Bash call hit the SDK apply-seccomp helper's EPERM ─────────────────────
# WHAT IT DETECTS. A hosted agent's Bash tool_result carried the SDK command-side helper's own line
#   apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted
# (the shim's seccomp filter is inherited by the helper, which then cannot create its user namespace; every
# Bash call in the session fails), or the same helper failing with EPERM at ANY other of its steps (#10455 e: an exact
# allowlist of the 16 step strings in the vendored binary). server/cc-dispatcher.ts `mirrorBashSandboxFailure`
# classifies the output (server/sandbox-startup-classifier.ts `classifyBashSandboxFailure`; errorCode
# `helper_userns_eperm` for the userns step, `helper_step_eperm` for every other step, and the predicate below pages on
# BOTH) and mirrors ONE pino row per user per debounce window per code: feature `agent-sandbox`, op
# `bash-tool-result`, with the code in `extra.sandboxErrorCode`. The row lands in this same prd Logs source under the
# app container.
#
# ROW SHAPE (verified on sibling pino rows that reach this source, 2026-10-16; no row of THIS emitter had ever arrived, so
# its first real hit is its positive control): `raw.CONTAINER_NAME` is
# `soleur-web-platform`; `raw.message` is an OBJECT (not a string) whose top-level keys are `feature`, `op`,
# `level`, `msg` plus the `extra` keys, so the three message conjuncts use the nested form
# `JSONExtractString(raw, 'message', '<key>')`.
# NO host_name conjunct, on purpose: the container name is `soleur-web-platform` on web-1 and web-2 alike, and the
# signal belongs to every web host (the same divergence the bwrap_probe_rollback alert records above).
#
# WHAT IT DELIBERATELY DOES NOT DETECT: a session whose Bash output never reaches the dispatcher's tool_result
# observer (the legacy agent-runner loop has none), and a dropped Vector/journald path (a silent row is silence,
# not health). The deploy-time canary covers the container (and was blind to this class: its replay never ran the
# command-side wrapper); this covers a live tenant session on the cc-soleur-go path only.
#
# Paging semantics are bwrap_probe_rollback's (ADR-218): any one matching row in the 5-min window alerts,
# treat_as_zero so the open incident observes recovery; on the free tier the channel is team email only.
# Both -target= lines are enforced by apps/web-platform/test/infra/sandbox-alerts.test.sh.
locals {
  agent_sandbox_bash_denial_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND JSONExtractString(raw, 'CONTAINER_NAME') = 'soleur-web-platform'
      AND JSONExtractString(raw, 'message', 'feature') = 'agent-sandbox'
      AND JSONExtractString(raw, 'message', 'op') = 'bash-tool-result'
      AND JSONExtractString(raw, 'message', 'sandboxErrorCode') IN ('helper_userns_eperm', 'helper_step_eperm')
    GROUP BY time
  SQL

  agent_sandbox_bash_denial_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/betterstack-log-query.md#standing-alarms-over-this-source-log-content-recurrence-alarms"
}

resource "logtail_exploration" "agent_sandbox_bash_denial" {
  name      = "soleur-agent-sandbox-bash-denial-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    # Single-line at the resource site, for the same perpetual-diff reason as the siblings above.
    sql_query = replace(trimspace(local.agent_sandbox_bash_denial_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "agent_sandbox_bash_denial" {
  exploration_id = logtail_exploration.agent_sandbox_bash_denial.id
  name           = "soleur-agent-sandbox-bash-denial-prd"

  # bwrap_probe_rollback's values: one row alerts within about a minute, the 5-min window holds ONE incident
  # across a burst of denials, and 10 quiet minutes auto-resolve it.
  alert_type          = "threshold"
  operator            = "higher_than"
  value               = 0
  check_period        = 60
  query_period        = 300
  confirmation_period = 0
  recovery_period     = 600
  on_missing_data     = "treat_as_zero"

  paused = false

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "A live hosted-agent Bash call failed in a step of the SDK apply-seccomp helper (for example apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted), so Bash is unavailable to the affected tenant session(s). The row is the app container's op=bash-tool-result mirror with sandboxErrorCode=helper_userns_eperm (the user-namespace step) or helper_step_eperm (any other helper step); it carries only the matched line, so read the count and timestamps via the runbook Query block without SSH. This incident auto-resolves after 10 quiet minutes; resolution does NOT mean the cause was fixed. Runbook: ${local.agent_sandbox_bash_denial_runbook_url}"
  metadata = {
    runbook = local.agent_sandbox_bash_denial_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}

# ── #10453: the deploy-time SDK Bash smoke reported the build cannot run a real wrapped Bash call ──
# WHAT IT DETECTS. ci-deploy.sh `run_sdk_bash_smoke` (non-blocking, ADR-079 addendum 2026-10-19) execs the baked
# `infra/lib/sdk-bash-probe.mjs` in the CANARY container and runs ONE real Bash call through the real Agent SDK, the
# shipped shim and the production sandbox config. When the probe's verdict is `sdk_bash_smoke_failed` (Bash was dispatched
# and the per-run nonce did not come back, or the call hung, or the tool_result carries a sandbox error) the script writes
# exactly one journald row under `logger -t ci-deploy` through `sandbox_canary_sentry_event`, whose message STARTS with
#   SANDBOX_CANARY_FAIL: verdict=sandbox_broken reason=sdk_bash_smoke_failed: <detail> sdk= (op=sandbox-canary; report-only canary, never gated)
# This is the #10445 shape the faithful canary was blind to (its replay ends in `-- true` and never runs the command-side
# wrapper); the smoke closes it on the deploy that carries the break, with no tenant text and no Vector-side dependence
# beyond the journald shipper every ci-deploy row already uses.
#
# THREE conjuncts, and each is load-bearing (CTO ruling 2026-10-19):
#   * SYSLOG_IDENTIFIER = 'ci-deploy' — a row that merely QUOTES the marker (inngest ships GitHub-webhook logs quoting issue
#     and PR bodies to this same source under another identifier) cannot alert;
#   * startsWith(message, '…verdict=sandbox_broken reason=sdk_bash_smoke_failed') — the `reason=` needle is MANDATORY: the
#     inner faithful canary's `bwrap_*` rows share the `verdict=sandbox_broken` prefix, and so did the standing outer-wrap rows
#     (retired by #10454, still in the 90-day retention window);
#   * position(message, '(op=sandbox-canary;') > 0 — the `;` terminator keeps `op=sandbox-canary-outer-wrap` out.
# `smoke_infra_error` does NOT page (it is the smoke's own failure to run; three in a row warn through Sentry as
# SDK_BASH_SMOKE_STALE). NO host_name conjunct, on purpose, the same divergence bwrap_probe_rollback records above: the
# signal belongs to every deploy host and a host conjunct would silence web-2.
#
# Paging semantics are bwrap_probe_rollback's (ADR-218): one matching row in the 5-min window alerts, treat_as_zero so the
# open incident observes recovery; on the free tier the channel is team email only. ONE row per failed deploy, so the alert
# cannot flap. The drift guard (test/infra/faithful-canary-sandbox-alert.test.sh) reads all three needles FROM ci-deploy.sh.
# Both -target= lines are enforced only by that guard (see header step 4).
locals {
  faithful_canary_sandbox_broken_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'ci-deploy'
      AND startsWith(JSONExtractString(raw, 'message'), 'SANDBOX_CANARY_FAIL: verdict=sandbox_broken reason=sdk_bash_smoke_failed')
      AND position(JSONExtractString(raw, 'message'), '(op=sandbox-canary;') > 0
    GROUP BY time
  SQL

  faithful_canary_sandbox_broken_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/canary-probe-set.md#sdk-bash-smoke-and-the-helper_userns_eperm-denial-10445"
}

resource "logtail_exploration" "faithful_canary_sandbox_broken" {
  name      = "soleur-faithful-canary-sandbox-broken-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    # Single-line at the resource site, for the same perpetual-diff reason as the siblings above.
    sql_query = replace(trimspace(local.faithful_canary_sandbox_broken_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "faithful_canary_sandbox_broken" {
  exploration_id = logtail_exploration.faithful_canary_sandbox_broken.id
  name           = "soleur-faithful-canary-sandbox-broken-prd"

  # bwrap_probe_rollback's values: one row alerts within about a minute, the 5-min window holds ONE incident across a CI
  # retry's repeated failed-smoke rows, and 10 quiet minutes auto-resolve it.
  alert_type          = "threshold"
  operator            = "higher_than"
  value               = 0
  check_period        = 60
  query_period        = 300
  confirmation_period = 0
  recovery_period     = 600
  on_missing_data     = "treat_as_zero"

  paused = false

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "Report-only signal (the smoke does not gate the deploy): a canary build could not run one real wrapped Bash call through the real Agent SDK, the shim and the production sandbox config (reason sdk_bash_smoke_failed). The deploy was NOT rolled back and this build is promoted to production in the same run: treat hosted Bash as failing in production until the reason is read and cleared (the 2026-10-06 incident shape, #10445); if only the AF_UNIX variant fails the consequence applies only once the agent-sandbox-unix-deny flag is ON. The email has no row body: read the failure detail without SSH from the deploy-status field sdk_bash_smoke (reason carries the first sandbox error line) or the runbook's Query block. This incident auto-resolves after 10 quiet minutes; resolution does NOT mean the cause was fixed. Runbook: ${local.faithful_canary_sandbox_broken_runbook_url}"
  metadata = {
    runbook = local.faithful_canary_sandbox_broken_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}

# ── #9639 F8: the nic guard refused to POST the token to an unpinned ingest URL ────────────────
#
# WHAT IT DETECTS. web-private-nic-guard.sh refuses to send the Better Stack token to a
# destination other than the pinned ingest URL: on its `[nic] unpinned_url:` stderr line the POST
# is withheld AND the liveness beat lapses — the guard that cannot report must not claim health.
# The line is journald-tagged SYSLOG_IDENTIFIER='web-nic-guard' at PRIORITY 6 — NOT a SOLEUR_*
# PRIORITY-2 marker, so monitor_send_failed's predicate cannot see it; until this alert the
# refusal mode was visible only through a post-merge query (betterstack-log-query.md's decode).
#
# NO host_name conjunct, deliberately: the guard timer runs on web-1 (SSH provisioner) and is
# baked for web-2-class hosts (cloud-init.yml), and either host can refuse — the luks sibling's
# host conjunct would blind half the fleet (the #8706 lesson in reverse: a threshold-any-row
# alert, not a liveness count).
#
# Column shape: live positive control `doppler run -p soleur -c prd_terraform --
# scripts/betterstack-query.sh` (2026-10-26, rc 0) returned rows carrying `dt`; the {{time}}
# placeholder resolves to that column, same as every sibling above.
locals {
  web_nic_guard_unpinned_url_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'web-nic-guard'
      AND position(JSONExtractString(raw, 'message'), 'unpinned_url') > 0
    GROUP BY time
  SQL

  web_nic_guard_unpinned_url_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/web-nic-guard-unpinned-url-alert.md"
}

resource "logtail_exploration" "web_nic_guard_unpinned_url" {
  name      = "soleur-web-nic-guard-unpinned-url-prd"
  team_name = "Your team"

  chart {
    chart_type = "line_chart"
  }

  query {
    query_type      = "sql_expression"
    source_variable = "source"
    # Single-line at the resource site, for the same perpetual-diff reason as the siblings above.
    sql_query = replace(trimspace(local.web_nic_guard_unpinned_url_sql), "/\\s+/", " ")
  }

  variable {
    name          = "source"
    variable_type = "source"
    values        = [local.vector_prd_source_id]
  }
}

resource "logtail_exploration_alert" "web_nic_guard_unpinned_url" {
  exploration_id = logtail_exploration.web_nic_guard_unpinned_url.id
  name           = "soleur-web-nic-guard-unpinned-url-prd"

  # monitor_send_failed's paging semantics: any matching row in a 5-min bucket pages within a
  # minute, one quiet 10-min window auto-resolves. treat_as_zero: a count query with no rows
  # returns NO bucket — that must read as healthy or an open incident can never observe recovery.
  alert_type          = "threshold"
  operator            = "higher_than"
  value               = 0
  check_period        = 60
  query_period        = 300
  confirmation_period = 0
  recovery_period     = 600
  on_missing_data     = "treat_as_zero"

  # Same note as monitor_send_failed: vendor-side pauses are re-armed by the next per-merge
  # apply; the `logs_alert` arm of reconcile-live-heartbeats.ts is the drift detector.
  paused = false

  email          = true
  push           = false
  call           = false
  sms            = false
  critical_alert = false

  incident_cause = "A web host's private-NIC guard refused to POST the Better Stack token to an unpinned ingest URL ([nic] unpinned_url) and withheld its beat — the host is healthy but cannot report, so its web_nic_guard heartbeat lapse will read as host-down on that beat. The runbook's readback names the row and the remediation (fix the Doppler value or the pin). This incident auto-resolves after 10 quiet minutes; resolution does NOT mean the cause was fixed. Runbook: ${local.web_nic_guard_unpinned_url_runbook_url}"
  metadata = {
    runbook = local.web_nic_guard_unpinned_url_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}
