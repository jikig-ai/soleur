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
  # source lists `include_matches.PRIORITY = 0..4`: OBSERVED (18 rows, 2026-09-16..23), the source's
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

  email          = true
  push           = false
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

  incident_cause = "The workspaces-LUKS dead-man FIRED on web-1: the cutover's backstop timer stopped the app, unmounted the encrypted /workspaces volume and remounted the retained plaintext one. Writes since the freeze may be stranded on the LUKS volume. Read the SOLEUR_WORKSPACES_LUKS_DEADMAN rows (result=ok or result=fail) to see how the revert ended, then follow the runbook. This incident auto-resolves after 10 quiet minutes; resolution does NOT mean the stranded writes were reconciled, only that no new fire row arrived. Runbook: ${local.workspaces_luks_deadman_runbook_url}"
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

# ── #9534: egress gateway — deny-class spike + probe silence ────────────────────
#
# WHAT THEY DETECT. The gateway's sole security surface is its deny decisions
# (Squid TCP_DENIED on the shared CIDR ACL + kernel `egress-gw-deny:` drops are
# the same class). A spike means something is actively probing internal space —
# a prompt-injected session reaching for metadata/RFC1918, or a confused-deputy
# forwarder. During the PR-A dark launch the only legitimate deny traffic is the
# synthetic probe's one row per 5 min, so a sustained rate above that pages.
#
# The heartbeat alert is the absence detector: cron-egress-resolve emits one
# `egress_gw_probe` line every 5 min under SYSLOG_IDENTIFIER=egress-gw-probe.
# Silence means the resolver timer died, the gateway container is gone (the
# probe skips with gw_absent — a row, not silence), or Vector stopped — none of
# which may read as green. The deny SPIKE is deliberately NOT on the probe row
# itself: a probe that only emits failures still pages via Sentry
# (egress_gw_probe_fail op), and the deny spike counts SQUID decisions, which a
# dead gateway cannot produce either — the two rules cover distinct failure
# arms (no gateway at all vs a live gateway mis-ACL'd).
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

  egress_gw_probe_silent_sql = <<-SQL
    SELECT {{time}} AS time, count(*) AS value
    FROM {{source}}
    WHERE time BETWEEN {{start_time}} AND {{end_time}}
      AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'egress-gw-probe'
    GROUP BY time
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

  # < 1 heartbeat row in 15 min (probe emits every 5 min when due). No rows ->
  # the absence is the alert; treat_as_zero makes "no bucket" read as 0 beats.
  alert_type          = "threshold"
  operator            = "lower_than"
  value               = 1
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

  incident_cause = "No egress_gw_probe heartbeat from cron-egress-resolve for 15+ min — the resolver timer, the Vector pipeline, or the host journal is dead. The gateway's allow/deny verification is dark. Runbook: ${local.egress_gw_runbook_url}"
  metadata = {
    runbook = local.egress_gw_runbook_url
  }

  escalation_target {
    policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null
    team_name = var.betterstack_paid_tier ? null : "Your team"
  }
}
