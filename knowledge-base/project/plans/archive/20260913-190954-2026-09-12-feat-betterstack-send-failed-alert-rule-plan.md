---
title: "feat: page on SOLEUR_*_SEND_FAILED / _REFUSED rows from the four web-1 monitor units (Better Stack Logs alert, Terraform-managed)"
type: feat
date: 2026-09-12
slug: feat-betterstack-send-failed-alert-rule
branch: feat-one-shot-8097-betterstack-send-failed-alert
issue: 8097
closes: 8097
priority: p2
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
lane: cross-domain
---

# feat: page on `SOLEUR_*_SEND_FAILED` / `SOLEUR_*_REFUSED` rows from the four web-1 monitor units

## Enhancement Summary

**Deepened on:** 2026-09-13
**Sections enhanced:** Proposed Solution (2, 4, 5), Technical Considerations, Hypotheses, Files to Edit/Create, Infrastructure (IaC), Encryption Posture, Guard Contract, Observability, Acceptance Criteria, Test Scenarios, Domain Review
**Research agents used:** architecture-strategist, observability-coverage-reviewer, security-sentinel, test-design-reviewer, git-history-analyzer, pattern-recognition-specialist, verify-the-negative grep pass (sonnet); halts 4.5-4.11 evaluated (4.5 fired — network checklist already satisfied in `## Hypotheses`; 4.8 false-positive on `var.betterstack_api_token` recorded; all others pass)

### Key Improvements

1. **Ingest token kept out of unflagged state.** The `data "logtail_source"` read was dropped for a `local.vector_prd_source_id = "2457081"` literal (pinned to the sink URI by Guard 1): the provider's `token` attribute is `Computed` but not `Sensitive` (verified in `resource_source.go`), and the drift cron pastes plan text into a public issue (security-sentinel P1).
2. **Web-1-scoped positive control.** Source 2457081 is shared with the inngest host (40-min census: 3,202 inngest rows vs 731 web-1), so the follow-through's `channel_dark` control is now `host = 'soleur-web-platform'` over the same 14-day window as the probe read — an unscoped control would have let a dead web-1 Vector read as `row_absent` (observability-coverage P1; ADR-197).
3. **Mutation matrix is a committed battery.** `betterstack-send-failed-alert-mutation.test.sh` with per-row FAIL strings, registered in `infra-validation.yml` per the `*-mutation.test.sh` convention (≈:699 "an unrun battery is a claim"); emitters discovered by `emit_refusal()` definition so a fifth unit is found, not listed; `_HALT` added to the forbidden-match set; H1 split into the RED row and its vacuity control (test-design P0s).
4. **Provisioner-parity floor and battery.** `server.tf` has 16 SSH-connected `terraform_data` today (not 15); the probe makes 17, so `FLOOR_RESOURCES` 16 → 17 and the mutation battery's M1 string `swept only 15` → `swept only 16` — otherwise CI reds (architecture P1).
5. **Reconcile-arm invariants.** The `logs_alert` arm must go through the injected `fetchImpl` with a second exact-host constant (the SSRF pin on `uptime.betterstack.com` must not widen), extend the closed `ViolationReason` union (`logs-alert-paused | logs-alert-absent`), keep free text inside quoted `detail=`, and set rc=2 (the workflow's issue path keys on `rc == 2`, not on marker lines) — verified against `reconcile-live-heartbeats.ts` and the drift workflow.
6. **Digits-only `probe_rev`** via `lifecycle.precondition` on the probe resource (locals cannot carry `validation {}`), mirrored in Guard 1 and the follow-through's grep — it is interpolated into a root shell literal and a ClickHouse `LIKE`.
7. **Follow-through hardening** per 84/85 sibling scripts: `set -uo pipefail` (never `-e`), the #7797 xtrace guard (exit 78), `SEND_FAILED_PROBE_BQ` seam, `SOLEUR_SEND_FAILED_ALERT_PROBE verdict=… detail=…` line, projected (never raw) incident/alert JSON into the public comment, curl failure on the alerts GET → 3; five `env -i` test cases with a URL-dispatching `curl` stub.

### New Considerations Discovered

- `BETTERSTACK_API_TOKEN_READONLY` read authority on `telemetry.betterstack.com/api/v2/alerts` measured **200** at plan time (2026-09-13) — the reconcile arm and AC9 rest on a proven, not assumed, scope; re-confirmed as Phase 0.5b.
- `scheduled-terraform-drift.yml`'s `terraform init` runs without `-lockfile=readonly` — added to Files to Edit so a new third-party provider cannot resolve outside the committed lockfile there.
- The CI SSH bridge is TOFU (`StrictHostKeyChecking=accept-new`, no persisted `known_hosts`), pre-existing; `cert_verification` corrected to `off` with a bounded `exception` block and a deferral for host-key pinning.
- H2's "config sha matches" is a file read, not a process read (Vector loads config at start, no `--watch-config`); the gap closes by transitivity — web-1 ships Source-3 rows with `dt` after the file's `mtime`, and Sources 3/4 postdate Source 2 — so the running config contains Source 2.
- A count alert's email carries only the fixed `incident_cause`; it cannot name SKIPPED vs `_REFUSED`. The runbook's readback SQL is the only marker-naming read (Observability failure mode 3 corrected).
- All 25 PR/issue/ADR citations confirmed against `origin/main`; ADR-218 remains the next free ordinal across all refs; commit `e7ad93e31` is the precedent for adding a provider block + lockfile entry to this root.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed); this branch was entered via one-shot with no brainstorm/spec.

PR #8073 made every refused or failed alert send in the four web-1 monitor units (`disk-monitor`, `resource-monitor`, `container-restart-monitor`, `cron-egress-alarm`) emit a PRIORITY-2 journald row (`SOLEUR_<UNIT>_SEND_FAILED …` / `SOLEUR_<UNIT>_REFUSED …`, via `emit_refusal()` → `logger -p user.crit -t <unit>`) that Vector Source 2 (`system_journald`, PRIORITY 0-2) ships to Better Stack Logs source 2457081. Those rows are queryable but nothing pages on them, so a broken Resend or Sentry send path leaves the on-call unpaged while the customer meets the underlying disk / memory / container-restart / cron-egress outage first.

This plan adds **one Better Stack Logs alert, managed as Terraform** in the existing `apps/web-platform/infra/` root through the `BetterStackHQ/logtail` provider (`logtail_exploration` + `logtail_exploration_alert`), that notifies the same free-tier team-email surface every sibling Better Stack monitor and heartbeat already uses (escalating to a `betteruptime_policy` when `var.betterstack_paid_tier` is set, exactly like the siblings). It excludes the deliberate `SOLEUR_*_SEND_SKIPPED` class by construction, and it proves the rule end-to-end with one synthetic row emitted **through web-1's existing CI apply path** (a `terraform_data` provisioner run by `apply-web-platform-infra.yml` over the CF Tunnel SSH bridge — the same channel that delivers `disk-monitor.sh` itself), read back by a follow-through probe that closes #8097 only once the row AND the resulting incident are both observed.

**Measured size:** two `.tf` resources + one data source + one provider block + one `terraform_data` probe, two `-target=` lines, one drift-guard test, one follow-through script, one runbook, one ADR (+ one ADR amendment), two C4 prose edits.

## Research Reconciliation — Spec vs. Codebase

| Issue / hint claim | Reality (verified this session) | Plan response |
|---|---|---|
| "routed to the existing on-call policy" | **No escalation policy exists live.** `GET uptime.betterstack.com/api/v2/policies` returns an empty `data` array; all three `betteruptime_policy` resources (`uptime`, `inngest`, `github_webhook`) are `count = var.betterstack_paid_tier ? 1 : 0`, the variable defaults `false` (`variables.tf` `variable "betterstack_paid_tier"`) and `TF_VAR_betterstack_paid_tier` is absent from Doppler `prd_terraform`. Every live monitor has `policy_id: null, email: true`. The on-call calendar "Primary on-call schedule" (id 365422) lists no on-call users. | Route to the **same surface as every sibling**: `email = true` + `escalation_target { team_name = "Your team" }` on the free tier, `escalation_target { policy_id = betteruptime_policy.uptime[0].id }` when `var.betterstack_paid_tier` is true. This is what "the existing on-call" concretely is today (account owner + the managed `betteruptime_team_member.ops` = `ops@jikigai.com`). |
| "either one API-created alert documented in a runbook … or one TF resource if the provider exposes Logs alerts" — ADR-096 and `runbooks/betterstack-log-query.md` record "the `better-uptime` TF provider has no log-alert resource" | True for `BetterStackHQ/better-uptime` (0.20.17 pinned; even 0.22.0 has no Logs alert). But Better Stack ships a **second** provider, `BetterStackHQ/logtail` (v11.2.0, 2026-09-04), whose `docs/resources/` lists `exploration.md`, `exploration_alert.md`, `dashboard_alert.md` and `data-sources/source.md`. Verified via `gh api repos/BetterStackHQ/terraform-provider-logtail/contents/docs/resources`. | **Terraform, not a REST script** (`hr-exhaust-all-automated-options-before`). ADR-096's provider-gap sentence is amended to name the logtail provider (Phase 2.10). |
| "verify with a synthetic row (`logger -p user.crit -t disk-monitor '…'`) from web-1's apply path, not SSH" | The four monitor scripts reach web-1 via `terraform_data.disk_monitor_install` / `resource_monitor_install` / `container_restart_monitor_install` in `server.tf` — `connection { type = "ssh" }` + `remote-exec`, run by CI in `apply-web-platform-infra.yml`'s SSH-provisioned step (line ≈1212). The `/infra-config` webhook hook (`hooks.json.tmpl`) delivers a fixed 20-file payload that does NOT include these scripts and cannot run an arbitrary command. | The synthetic row is a new `terraform_data.send_failed_alert_probe` in `server.tf` mirroring `disk_monitor_install` (same connection block, `remote-exec` with the issue's exact `logger` line + `synthetic=1 probe_rev=<rev>`), added to the SSH `-target=` set. No human SSH anywhere (`hr-no-ssh-fallback-in-runbooks`). |
| "shipped by Vector Source 2" | Source 2 `[sources.system_journald]` is `include_matches.PRIORITY = ["0","1","2"]`, `exclude_units = [inngest-server.service, vector.service]` — no tag scoping, so `logger -p user.crit` (syslog severity 2) from any unit qualifies. The `pii_scrub_*` transforms edit only `.message` via credential-shaped regexes; `SOLEUR_… channel=resend http_code=000 rc=7` carries none. **However:** in 14 days the warehouse holds **zero** PRIORITY 0-2 rows with `host = soleur-web-platform`; every CRIT row is from `soleur-inngest`. Equally consistent with "web-1 had no CRIT events" and "web-1's live Vector lacks Source 2". The repo-research agent's claim that these tags must be in Source 4's `SYSLOG_IDENTIFIER` list is wrong (it also mis-read `user.crit` as PRIORITY 4); Source 4 is irrelevant to PRIORITY-2 rows. | Resolved at plan time via the deploy-status webhook (see `## Hypotheses` H2): web-1 runs the CURRENT vector.toml (live sha == rendered repo sha), so Source 2 is live; the zero is H1. The synthetic probe proves the last link (journald PRIORITY + Vector match). The follow-through reads the row back by `probe_rev` and reports the journald `host` field, never on `host_name` (web-1 wears the stale `host_name=soleur-inngest-prd` render, #6616). |
| "`--grep` compiles to raw LIKE over double-encoded JSON, so use `--raw-only` + jq PRIORITY filter" | Confirmed from `scripts/betterstack-query.sh`: `--grep` → `raw LIKE '%…%'` and the `raw` column is a JSON string re-encoded in JSONEachRow output. Server-side `JSONExtractString(raw,'PRIORITY') = '2'` works directly (used throughout this session). | Every AC and the runbook use raw SQL with `JSONExtractString`, or the documented `--raw-only` + `jq '.raw\|fromjson\|select(.PRIORITY=="2")'` form. Never `--grep PRIORITY=2`. |
| Only the four units emit `_SEND_FAILED` / `_REFUSED` | Repo-wide enumeration (`git grep -ohE 'SOLEUR_[A-Z0-9_]*(_REFUSED\|_SEND_FAILED)[A-Z0-9_]*'` over definers, not tests) finds two more: `SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED` (`inngest-cutover-flip.sh` calls `logger -t` with **no** `-p`, so the default `user.notice` = PRIORITY 5 applies) and `SOLEUR_RESEND_INBOUND_BOOTSTRAP_REFUSED` (`resend-inbound-bootstrap.sh`, `emit_refusal` never calls `logger`). | Both are excluded by the `PRIORITY = '2'` clause, which is therefore load-bearing (Guard 1 pins it). No tag pin: the rule stays convention-based as the issue asks, and the guard fails if a future `user.crit` emitter of these substrings appears outside the documented set. |

## Problem Statement / Motivation

The monitors exist to page ops before a customer notices. #8073 made the monitors' own send failures visible in the warehouse; visibility without a page is a dashboard-eyeball dependency (`hr-no-dashboard-eyeball-pull-data-yourself`). Because the failure being detected IS the Sentry/Resend send path, the detector must live on the vendor that is independent of both — Better Stack, "the exit that survives a Sentry-side outage" (`model.c4` `betterstack -> founder`). ADR-096's default for log-content alarms (a GH-Actions cron poller surfacing a GitHub issue) cannot page and reports through Sentry self-liveness — the wrong vendor for this signal — and ADR-096 itself carves out "a pure stateless per-bucket count with an email-acceptable surface" as the case for a native alert. `count(rows matching) > 0` per bucket is exactly that.

## Proposed Solution

1. **Provider:** add `logtail = { source = "BetterStackHQ/logtail", version = "~> 11.2" }` to `main.tf` `required_providers` and `provider "logtail" { api_token = var.betterstack_api_token }` — the existing global token (no new variable; GET-probed 200 on `telemetry.betterstack.com/api/v2/explorations`, `/api/v2/alerts`, `/api/v1/sources` with that exact credential).
2. **Resources** in a new `apps/web-platform/infra/betterstack-logs-alerts.tf`:
   - `locals { vector_prd_source_id = "2457081" }` — the existing Logs source, the same id already public in `vector.toml`'s sink URI (`s2457081.eu-fsn-3…`). **No `data "logtail_source"`** (security-sentinel, verified against provider source `internal/provider/resource_source.go`: the source schema's `token` attribute is `Computed` and NOT `Sensitive`, so a data-source read would land the ingest token in `terraform show -json` output unflagged — the ARM step writes that JSON to `$RUNNER_TEMP`, and `scheduled-terraform-drift.yml` pastes plan text into a PUBLIC issue with only a `token = "…"` sed mask). Guard 1 pins the literal to the sink URI.
   - `locals { monitor_send_failed_sql = <<-SQL … SQL }` — the predicate below lives in ONE local consumed by both the exploration and the probe's trigger, so the two cannot drift.
   - `resource "logtail_exploration" "monitor_send_failed"` — `name = "soleur-monitor-send-failed-prd"` (Required), `chart { chart_type = "line_chart" }`, `query { query_type = "sql_expression", source_variable = "source", sql_query = local.monitor_send_failed_sql }`, `variable { name = "source", variable_type = "source", values = [local.vector_prd_source_id] }`, `team_name = "Your team"`.
   - `resource "logtail_exploration_alert" "monitor_send_failed"` — `exploration_id = logtail_exploration.monitor_send_failed.id` (Required), `name = "soleur-monitor-send-failed-prd"` (sibling naming: `soleur-workspaces-luks-prd`), `alert_type = "threshold"`, `operator = "higher_than"`, `value = 0`, `check_period = 60`, `query_period = 300`, `confirmation_period = 0`, `recovery_period = 600`, `on_missing_data = "treat_as_zero"`, **`paused = false` written explicitly** (a vendor-side pause — `paused_reason` "complexity issues / too many failures" — then shows as drift in the untargeted `scheduled-terraform-drift.yml` plan, but only BETWEEN infra merges: the per-merge targeted apply re-arms it silently and the vendor re-pauses, a fight the 12 h plan can miss whenever `apps/web-platform/infra/**` merges more than twice a day, which it does. so `paused = false` is intent, and the reconcile arm below is the detector), `email = true`, `push/call/sms = false` (mirrors every sibling heartbeat), `incident_cause = "SOLEUR_*_SEND_FAILED / _REFUSED row from a web-1 monitor unit — the monitor's own Resend/Sentry send failed. Runbook: https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/monitor-send-failed-alert.md"` (a full URL, in the field most likely rendered in the email — a repo path is not clickable for a non-technical operator; whether Logs-alert emails render `incident_cause` or `metadata` is unproven, so the follow-through prints which fields the real incident carried and the runbook is corrected once), `metadata = { runbook = <same URL> }`, and one static `escalation_target { policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null; team_name = var.betterstack_paid_tier ? null : "Your team" }` — the same null-sibling ternary shape as `uptime-alerts.tf`'s `policy_id` line (terraform-architect read provider v11.2.0 `alert_shared.go`: all four nested fields are plain `Optional`, no `ExactlyOneOf`; the write path skips `policy_id == 0` / `team_name == ""` and read-back mirrors only configured keys, so a `null` sibling never drifts). **Omit** `aggregation_interval`, `series_names`, `series_names_except` and `source_variable` on the alert: all `Optional+Computed`, and `aggregation_interval` is the one the API may snap to a bucket size and rewrite (perpetual diff).
   - `locals { monitor_send_failed_probe_rev = "1" }` — the probe's ONLY trigger. **The probe fires when `probe_rev` changes and never otherwise** (CTO finding: the SSH apply runs on every push to `main`; a per-run nonce would page ops@ on every merge). The honest contract, stated in the `.tf` header and runbook: *changed the SQL? bump the rev.* No predicate hash — the plan's first draft hashed the SQL, then conceded the sweeper cannot re-derive a heredoc hash under `env -i` and read `probe_rev` from the checkout instead; two keys where one does the job (plan-review: DHH, code-simplicity, Kieran #12 — a whitespace re-flow of the heredoc would otherwise page ops@ on a cosmetic merge). A rev bump performs zero Better Stack API writes, so re-verification never perturbs the alert under test.
3. **Predicate** (live-probed 2026-09-12 against the ClickHouse table; positive control returned real `SOLEUR_` rows incl. web-1 at PRIORITY 5; constant checks returned `skipped_matches=0, failed_matches=1, refused_matches=1`):

   ```sql
   SELECT {{time}} AS time, count(*) AS value
   FROM {{source}}
   WHERE time BETWEEN {{start_time}} AND {{end_time}}
     AND JSONExtractString(raw, 'PRIORITY') = '2'
     AND startsWith(JSONExtractString(raw, 'message'), 'SOLEUR_')
     AND multiSearchAny(JSONExtractString(raw, 'message'), ['_SEND_FAILED', '_REFUSED'])
   GROUP BY time
   ```

   `multiSearchAny` with literal needles (no `LIKE` wildcards) is what makes the SKIPPED exclusion mechanical and testable: `SOLEUR_X_SEND_SKIPPED …` contains neither needle. `{{time}}/{{source}}/{{start_time}}/{{end_time}}` are the Better Stack template variables the `logtail_exploration` docs use verbatim.
4. **Synthetic-row probe** in `server.tf`, immediately after `terraform_data.disk_monitor_install`:

   ```hcl
   resource "terraform_data" "send_failed_alert_probe" {
     triggers_replace = local.monitor_send_failed_probe_rev
     connection {
       type        = "ssh"
       host        = hcloud_server.web["web-1"].ipv4_address
       user        = "root"
       private_key = var.ci_ssh_private_key
       agent       = var.ci_ssh_private_key == null
     }
     lifecycle {
       precondition {
         condition     = can(regex("^[0-9]+$", local.monitor_send_failed_probe_rev))
         error_message = "monitor_send_failed_probe_rev must be digits only: it is interpolated into a root shell literal and a ClickHouse LIKE."
       }
     }
     provisioner "remote-exec" {
       inline = [
         "logger -p user.crit -t disk-monitor 'SOLEUR_DISK_MONITOR_SEND_FAILED channel=resend http_code=000 rc=7 synthetic=1 probe_rev=${local.monitor_send_failed_probe_rev}'",
       ]
     }
   }

   `locals` cannot carry `validation {}`, so the digits-only contract lives on the resource (security-sentinel); Guard 1 and the follow-through's `grep -oE '"[0-9]+"'` enforce the same regex.
   ```

   Ordering is by workflow step order, not `depends_on`: the main (non-SSH) apply (step "Terraform apply", ≈:1016) creates the exploration + alert; the SSH-provisioned apply (≈:1212) fires the probe minutes later. Both are steps of the same `apply` job and the SSH step's `if:` is a plain `steps.ssh_token_gate.outputs.ssh_apply_skip != 'true'` (no `always()`), so a failed main apply stops the job before the probe can fire and consume its trigger. The trigger is a literal `local`, not a reference to the `logtail_*` resources, so the SSH `-target` never drags a non-SSH resource into its plan (`-target` is transitive on references). The probe writes no filesystem destination, so the destination-keyed `web-host-provisioner-parity.test.sh` sees no new artifact to pair with a fresh-boot counterpart — but its resource floor is zero-slack (`FLOOR_RESOURCES = 16` today for 16 SSH-connected resources) and its mutation battery M1 asserts the exact post-deletion count, so both move 16 → 17 / `swept only 15` → `swept only 16` in the same PR (architecture-strategist).
5. **Readback follow-through** `scripts/followthroughs/send-failed-alert-probe-8097.sh` (secrets `BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD,BETTERSTACK_API_TOKEN` — all already wired in `scheduled-followthrough-sweeper.yml`), evaluated in this order so each verdict names ONE cause, and mapped onto the sweeper's exit contract (`scripts/sweep-followthroughs.sh`: 0 PASS closes the issue; 1 FAIL reopens a human-closed issue up to `REOPEN_MAX=3`; 2 NOT YET; 3 CANNOT ESTABLISH; 5 ACTION REQUIRED) — `pass`→0, `channel_dark`→3, `alert_absent`/`alert_paused`/`row_present_no_incident`→5, `row_absent`→5 with the enumerated candidate causes printed (SSH stage green-skipped by the `ssh_token_gate` #7539 arm; main apply failed after creating the exploration; journald PRIORITY/Vector Source-2 match fault on web-1 — web-1's Vector being dead outright is the `channel_dark` verdict, not this one) — the script cannot read the apply run without `GH_TOKEN` and says so rather than naming one cause; exit 1 is never used (spec-flow P1-1/P1-2): (1) `GET telemetry.betterstack.com/api/v2/alerts` → no alert named `soleur-monitor-send-failed-prd` ⇒ `alert_absent` (main apply never created it); `paused == true` ⇒ `alert_paused` (vendor rejected the query — `paused_reason` printed). This is the load-bearing self-health read AC9 names; the script runs it, not a person; (2) positive-control read scoped to WEB-1, over the SAME 14-day hot ∪ archive window as step (3): `SELECT count(), min(dt), max(dt) … WHERE JSONExtractString(raw,'host') = 'soleur-web-platform'` = 0 ⇒ `channel_dark host=soleur-web-platform` (observability-coverage-reviewer: source 2457081 is shared — a 40-min census showed `soleur-inngest` 3,202 rows vs `soleur-web-platform` 731 — so an unscoped control is satisfied by the inngest host while web-1's Vector is dead; ADR-197's second assertion also needs the control to cover the same window, so print `control_rows_web1`, `control_min_dt`, `control_max_dt`); (3) `SELECT dt, JSONExtractString(raw,'host') AS host, JSONExtractString(raw,'message') AS msg … WHERE dt >= now() - INTERVAL 14 DAY AND JSONExtractString(raw,'PRIORITY')='2' AND JSONExtractString(raw,'message') LIKE '%synthetic=1 probe_rev=<rev>%'` over `remote()` UNION ALL `s3Cluster()` (the hot window is ~40 min; the sweeper runs daily at 18:00 UTC so the first readback is up to 24 h post-merge — hot-only would fail by construction), where `<rev>` is read from the checkout: `grep -oE 'monitor_send_failed_probe_rev\s*=\s*"[0-9]+"' apps/web-platform/infra/betterstack-logs-alerts.tf` (digits only — empty match ⇒ exit 3) (spec-flow P0-1: the sweeper runs under `env -i` with no Terraform). Zero rows ⇒ `row_absent`; a row whose `host` ≠ `soleur-web-platform` ⇒ `row_present_host_mismatch` (reported, not failed on); (4) `GET uptime.betterstack.com/api/v2/incidents` (no `status` filter — resolved incidents are listed and count) → no incident whose `name` equals the alert name **or** whose `cause` equals the alert's `incident_cause` string, with `started_at` ≥ the matched row's `dt` − 600 s ⇒ `row_present_no_incident` (a PROJECTED incident list — `jq '.data[] | {id, name: .attributes.name, cause: .attributes.cause, started_at: .attributes.started_at, resolved_at: .attributes.resolved_at}'` — and the alert's `{name, paused, paused_reason}` are printed for attribution; never the raw objects, which carry `acknowledged_by`/`resolved_by`/screenshot URLs and the sweeper posts stdout verbatim into a public issue comment — security-sentinel); else `pass`. The row's own `dt` is the time anchor — the script never needs the merge time. Fields `name`, `cause`, `started_at`, `resolved_at` were verified on real monitor/heartbeat incidents this session; whether a Logs-alert incident carries the alert name in `name` is unproven, which is why `cause` (a string this plan controls) is the second key. The script also prints `nonsynthetic_rows=<n>` — matching rows in the window WITHOUT `synthetic=1` — so a real firing that masks the verdict is visible (spec-flow P1-7).
6. **Drift guard** `apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh` (Guard 1 below), wired into `infra-validation.yml` (the orphan-suite lint `scripts/lint-orphan-test-suites.test.sh` requires every `.test.sh` to be dispatched by a workflow).
7. **Docs:** runbook `monitor-send-failed-alert.md`; a row in `betterstack-log-query.md` §"Standing alarms over this source"; new ADR (provisional **ADR-218**) + ADR-096 amendment; `model.c4` `betterstack` element (:333), one clause.

## Technical Considerations

- **Architecture:** first Terraform-managed Better Stack Logs object; second Better Stack provider in the root sharing one credential. The exploration is an alert-only artifact (no dashboard); `team_name = "Your team"` mirrors `inngest.tf` / `uptime-alerts.tf` (case-sensitive literal).
- **Credential coverage (ADR-130 class):** read coverage of the global token on the Telemetry surface is probed (200 ×4, plus the known-granted control `uptime.betterstack.com/api/v2/monitors`); write coverage is documented ("Global API tokens and Telemetry API tokens accepted", `betterstack.com/docs/logs/api/getting-started/`) but only provable at apply. If the first apply returns 403 on `POST /api/v2/explorations`, the fallback is a Telemetry API token published to `prd_terraform` as a new no-default `TF_VAR_betterstack_telemetry_api_token` — a vendor-dashboard mint, `automation-status: UNVERIFIED — /work runs a Playwright attempt before any operator handoff` (the sequencing rule in this skill's Sharp Edges then applies: split the `.tf` change until the var exists).
- **Template SQL is not validatable offline.** `terraform validate` checks HCL, not the `{{…}}` query. The observable for a broken query is the created alert's read-only `paused_reason` ("complexity issues, too many failures") — AC9 reads it via `GET /api/v2/alerts/<id>` and requires it empty with `paused = false`.
- **`escalation_target` semantics**: verified against provider source (v11.2.0 `alert_shared.go`) — no `ExactlyOneOf`; nulls are skipped on write and not mirrored on read. Phase 0 still runs `terraform init -backend=false && terraform validate` on the exact block before anything else.
- **Lockfile:** the root locks **2 platforms** per provider (the `h1:` entries: `linux_amd64` for CI, `darwin_arm64` for a local workstation — the 13 `zh:` lines are the release's ziphashes, not platforms) and the apply workflow inits with `-lockfile=readonly` (≈:541), so CI cannot self-heal a missing provider entry. Phase 0 runs `cd apps/web-platform/infra && terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` (reads only `required_providers`; no backend creds) and commits the new `betterstackhq/logtail` block (`version = "11.2.0"`, 2 `h1:` + 13 `zh:`, siblings unchanged). Do not add other platforms — that would make the entry inconsistent with every sibling.
- **`-target` allowlists (#5566 coverage guard):** every resource in `*.tf` must be `-target`ed by a per-merge job or listed in `OPERATOR_APPLIED_EXCLUSIONS` (`plugins/soleur/test/terraform-target-parity.test.ts`). `logtail_exploration.*` and `logtail_exploration_alert.*` go in the main plan allowlist next to `betteruptime_team_member.ops`; `terraform_data.send_failed_alert_probe` goes in the SSH apply list next to `disk_monitor_install`. Data sources are not resources and need no target. `-target` is transitive, so the SSH probe references only `hcloud_server.web` (already in state) and a local. A declared `logtail_*` resource missing from the allow-list is already CI-red: the #5566 guard in `plugins/soleur/test/terraform-target-parity.test.ts` ("ALL managed resources are reachable", ≈:1448) enumerates every `resource "TYPE"` of any type — no new guard needed (the first draft of this plan asserted a gap here; Kieran + DHH corrected it against the repo).
- **Alert self-health detector — one arm in an existing poller, not a new step:** `plugins/soleur/scripts/reconcile-live-heartbeats.ts` already runs twice daily from `scheduled-terraform-drift.yml`'s `heartbeat-live-reconcile` job (≈:1315) with `BETTERSTACK_API_TOKEN_READONLY`, reads live Better Stack state, prints `SOLEUR_HEARTBEAT_RECONCILE_{OK,MISMATCH,UNREACHABLE,ERROR}` markers, and the workflow files/updates ONE deduped `heartbeat-reconcile-mismatch` issue from any `^SOLEUR_HEARTBEAT_RECONCILE_` line. Add one arm: `GET https://telemetry.betterstack.com/api/v2/alerts` through the SAME injected `fetchImpl` (so the test stubs by URL) and a SECOND exact-host constant in `plugins/soleur/lib/heartbeat-live-reconcile.ts` next to `isAllowedHeartbeatsUrl` (`uptime.betterstack.com` is pinned as an SSRF/exfil guard — never widen it to a suffix match); if `soleur-monitor-send-failed-prd` is absent or `paused == true`, print `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=soleur-monitor-send-failed-prd live=logs_alert reason=logs-alert-paused|logs-alert-absent detail="<paused_reason>"` — `reason` extends the closed `ViolationReason` union (`"fed-but-paused" | "absent-live"`) with two new members (`cq-union-widening-grep-three-patterns`: grep every consumer switch), free text only inside the quoted `detail=`, and one bullet added to the workflow's "Each marker discriminates the class" list. Combine rule: heartbeat verdict first, the arm is additive, exit = ERROR(1) > MISMATCH(2) > OK(0) — the workflow's issue path keys on `rc == 2`, so the arm MUST set rc=2 with its MISMATCH line (an `_OK`-only or `UNREACHABLE` run files nothing). No new label, dedup, or `fail_channel` (plan-review: DHH "remove", code-simplicity "fold"; folded because the per-merge re-arm makes the untargeted plan an unreliable detector between infra merges, and the arm is ~15 lines + one test case in `plugins/soleur/test/heartbeat-live-reconcile.test.ts`).
- **`-target`-scoped deletion is a no-op** (learning 2026-07-17): removing the alert later requires the `[ack-destroy]` procedure; the runbook says so.
- **Quota:** the probe adds one PRIORITY-2 row per `probe_rev` bump (~0 rows/day). The alert itself consumes no log quota. Free-tier Telemetry alert count cap is undocumented; one pre-existing paused onboarding alert ("Output utilization high", id 2536305877, dashboard 1025429) already exists and stays unmanaged (same class as the unmanaged monitor #7884).
- **Paging semantics:** `query_period = 300` ≥ the timers' 5-min cadence, so a persisting failure holds ONE open incident instead of flapping; `recovery_period = 600` gives a 10-min quiet window before auto-resolve; `on_missing_data = treat_as_zero` because a count query with no rows returns no bucket — that must read as healthy (0), never as "unknown", or an open incident could never observe recovery.
- **NFR register:** availability of the alerting path (independent vendor) — the change strengthens the "second source" property already recorded on the `betterstack -> founder` edge; no new latency-sensitive path.

## Hypotheses

The plan adds a resource whose definition carries `connection { type = "ssh" … }` applied by CI, so the network-outage checklist applies (`hr-ssh-diagnosis-verify-firewall`, telemetry emitted at plan time).

1. **L3 firewall allow-list (CI egress → web-1:22).** The probe uses the identical CF Tunnel SSH bridge + SSH-provisioned step that delivers the monitor scripts. [verified: run 34679740292, 2026-09-12T07:03Z — "CF Tunnel SSH bridge (gated): success" and the SSH-provisioned step: success; the bridge is Cloudflare Access-gated, not IP-allowlisted, so an admin-IP (`var.admin_ips`) rotation cannot affect it]
2. **L3 DNS/routing.** Not on the path: the bridge dials `hcloud_server.web["web-1"].ipv4_address` via cloudflared, not a hostname. [opt-out with artifact: same run]
3. **L7 TLS/proxy.** Telemetry API over HTTPS from the runner. [verified: four 200s this session from a workstation with the same token; runner egress to `telemetry.betterstack.com` is unproven until first apply — a 000/timeout there is the first thing the apply log shows]
4. **H2 — web-1's live `vector.toml` lacks Source 2 (co-located-era config, #6616 class).** [REFUTED by artifact, no SSH: `GET https://deploy.soleur.ai/hooks/deploy-status` (HMAC + CF Access, creds from Doppler `prd_terraform`, the `vector-redeliver.md` runbook's probe) on 2026-09-13 returned `vector: active`, `vector_config_identity: redis_allowlisted=yes sha256=6a36d8d32cacad301cfcca35ff16c7e4969e80307b76154094f811eedae5ccf5 mtime=1788955749`, and `sed 's|@@HOST_NAME@@|soleur-inngest-prd|g' apps/web-platform/infra/vector.toml | sha256sum` = `6a36d8d3…` — byte-identical to the CURRENT committed config rendered with the known stale host label. `vector_config_identity` is a FILE read (`sha256sum`/`stat`) and Vector loads config only at start (no `--watch-config`), so file-matches alone ≠ process-loaded; the gap closes by transitivity: web-1 ships Source-3 rows now (731 in a 40-min census, `dt` after the file's `mtime` 2026-09-09T12:09Z), Source 3 (#4773) and Source 4 postdate Source 2 (#4250, never removed), so the RUNNING config contains Source 2 (observability-coverage-reviewer).]
5. **H1 — web-1 emits no PRIORITY 0-2 rows because nothing CRIT has happened in 14 days.** [The only hypothesis left standing for the zero; consistent with web-1's SSH being tunnel-gated (no `sshd` crit noise, unlike `soleur-inngest`). ADR-197: still not "verified", just unrefuted.]
6. **What remains unmeasured:** that journald records `logger -p user.crit` as `PRIORITY=2` on web-1 and Source 2 ships it — the documented mechanism (identical config ships `soleur-inngest`'s `sshd` PRIORITY-2 rows). The synthetic probe proves this last link. `row_absent` with a positive control present now means a journald/Vector match fault on web-1, not a config-delivery gap; the follow-through verdict names it and #8097 stays open.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| GH-Actions cron poller → `action-required` issue + Sentry heartbeat (ADR-096 default) | Cannot page; self-liveness through Sentry, the vendor whose failure this alert must survive; ADR-096 explicitly exempts stateless per-bucket counts with an email surface. |
| REST-created alert via `POST /api/v2/explorations/{id}/alerts` + runbook (the issue's fallback) | A first-class TF resource exists; a REST object has state outside Terraform (bootstrap + drift + delete handling by hand). |
| CI direct-ingest POST as the verification row (ADR-172 pattern) | Bypasses web-1's Vector — the one unmeasured link (H2). Not retained anywhere (an earlier draft kept it as an optional runbook probe; it pages just the same and proves less). Not used pre-merge either: the alert does not exist before the merge apply, and the SQL predicate was already proven at plan time against the live table (positive control + constant checks). |
| Include `'_HALT'` as a third needle (`SOLEUR_<UNIT>_HALT reason=xtrace-credential-bound`, emitted at `user.crit` by all four units) | Outside the operator's stated scope; recorded as User-Challenge UC-1 in `specs/<branch>/decision-challenges.md` and as a deliberate exclusion in ADR-218 — a one-token change if the operator opts in. |
| Pin `SYSLOG_IDENTIFIER IN (four tags)` in the predicate | The issue asks for a convention-based rule; today's enumeration shows `PRIORITY = '2'` already excludes every non-unit `_REFUSED` marker; Guard 1 catches a future `user.crit` emitter outside the documented set instead. |
| Separate PR for the probe (fire after the alert has existed for a while) | The alert is created by the main apply ≥ several minutes before the SSH apply fires the probe in the same run; with `query_period = 300` and `check_period = 60` the first evaluation after creation sees the row. If the readback returns `row_present_no_incident`, a `probe_rev` bump re-fires the probe in a one-line follow-up without redesign. |
| `critical_alert = true` (bypass quiet hours) | No sibling sets it and no quiet hours are configured on the free tier; left `false` and named in the runbook as the knob to flip on the paid tier. |

## Implementation Phases

### Phase 0 — Preconditions (verify before any edit)

- [x] `gh issue view 8097 --json state` → `OPEN` (re-check at /work start).
- [x] `cd apps/web-platform/infra && terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` after adding the provider block; commit the lockfile diff (new block only); `terraform init -backend=false -input=false && terraform validate` green with the exact static `escalation_target` block written.
- [x] `terraform plan -target=logtail_exploration.monitor_send_failed -target=logtail_exploration_alert.monitor_send_failed` (via the canonical triplet: `export AWS_ACCESS_KEY_ID/SECRET` from Doppler `prd_terraform`, `terraform init -input=false`, `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan …`) shows exactly `2 to add, 0 to change, 0 to destroy`. No apply from the workstation — the merge-triggered workflow is the apply path.
- [x] ADR ordinal probe across ALL refs immediately before writing the ADR: `for r in $(git for-each-ref --format='%(refname)' refs/remotes/origin); do git ls-tree -r --name-only "$r" -- knowledge-base/engineering/architecture/decisions/; done | grep -oE 'ADR-[0-9]+' | sort -u -t- -k2 -n | tail -1` → highest today is ADR-217 ⇒ **ADR-218 provisional**; re-run at /ship.
- [x] Read `plugins/soleur/test/terraform-target-parity.test.ts` name list + `TEST_FLOOR` and `scripts/lint-orphan-test-suites.test.sh` before adding the test/workflow step.

### Phase 1 — RED: drift guard first (`cq-write-failing-tests-before`)

- [x] Write `apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh` per Guard 1 (seams `GUARD_TF`/`GUARD_SCRIPTS_DIR`/`GUARD_SERVER_TF`/`GUARD_VECTOR_TOML`, `=== Summary: $PASS passed, $FAIL failed ($CASES cases) ===`, `SEND_FAILED_ALERT_MIN_CASES=6`, string-aware comment stripping) and its battery `betterstack-send-failed-alert-mutation.test.sh`; run the guard → FAIL (no `.tf` yet). Wire it as a step in `.github/workflows/infra-validation.yml`'s `deploy-script-tests` job next to the provisioner parity guard (≈:770) — NOT in the `validate` matrix job, which runs once per changed root — and add `apps/web-platform/test/infra/**` to the workflow's two `paths:` filters (today only `apps/*/infra/**`) so editing the test itself triggers it; the orphan-suite lint then passes.

### Phase 2 — Terraform (alert)

- [x] `main.tf`: `required_providers.logtail` + `provider "logtail"` (comment: why the second provider, shared token, ADR-218).
- [x] `betterstack-logs-alerts.tf`: data source, exploration, alert, `locals.monitor_send_failed_sql` / `monitor_send_failed_probe_rev`, header comment with a purpose line, `# Plan: knowledge-base/project/plans/2026-09-12-feat-betterstack-send-failed-alert-rule-plan.md`, a runbook pointer, ADR-218, the SKIPPED-exclusion rationale from `cron-egress-alarm.sh` ("a future alert rule on SEND_FAILED never pages on configuration"), and a literal 5-line "to add another Logs alert" checklist (local SQL → exploration → alert → two `-target=` lines → standing-alarm row in `betterstack-log-query.md`; same-severity `SOLEUR_*` PRIORITY-2 classes opt in by adding a needle, not a new alert) — siblings carry runbook pointers in `.tf` comments (`uptime-alerts.tf`), and an engineer grepping `logtail_` lands here, not on ADR-218.
- [x] `.github/workflows/apply-web-platform-infra.yml` main plan allowlist: `-target=logtail_exploration.monitor_send_failed`, `-target=logtail_exploration_alert.monitor_send_failed` (adjacent to `-target=betteruptime_team_member.ops`).
- [x] Guard 1 → GREEN.

### Phase 3 — Terraform (probe) + parity

- [x] `server.tf`: `terraform_data.send_failed_alert_probe` (mirror `disk_monitor_install`'s connection block verbatim).
- [x] SSH apply list: `-target=terraform_data.send_failed_alert_probe` (adjacent to `disk_monitor_install`).
- [x] `plugins/soleur/test/terraform-target-parity.test.ts` needs no edit (`MIN_SSH_PROVISIONED = 17` is a `>=` floor); `bun test plugins/soleur/test/terraform-target-parity.test.ts` green; `apps/web-platform/infra/web-host-provisioner-parity.test.sh` `FLOOR_RESOURCES` 16 → 17 (+ header prose) and `web-host-provisioner-parity-mutation.test.sh` M1 string `swept only 15` → `swept only 16`; `infra-validation.yml` step name → 17; all three suites green.

### Phase 4 — Follow-through + runbook + ADR/C4

- [x] `scripts/followthroughs/send-failed-alert-probe-8097.sh` (+ `.test.sh` with a stubbed query function, mirroring `bwrap-probe-selfreport-8016.test.sh`'s shape): three exit paths (`pass`→0; `channel_dark`→3, also for any `curl` rc≠0 / non-2xx on the alerts GET (an unanswered read is never a verdict, ADR-192/197); every other verdict→5, printing the alert `{name,paused,paused_reason}`, matched rows and the PROJECTED incident list so a human reads the cause once), verdict labels kept as printed text (`alert_absent` / `alert_paused` / `row_absent` / `row_present_no_incident`; `host_mismatch` as a printed attribute). Conventions (pattern-recognition-specialist, 84/85 siblings): `set -uo pipefail` — never `-e`, an unguarded abort is exit 1 = FAIL to the sweeper; explicit empty-checks on each secret, never `${VAR:?}`; the #7797 xtrace guard (`case "$-" in *x*) … exit 78` when a credential is bound) + `export LC_ALL=C`; header with issue-first title, WHAT IT PROVES, the exit table `0 PASS / 3 CANNOT ESTABLISH / 5 ACTION REQUIRED / 78 xtrace refusal`, `Test seam: SEND_FAILED_PROBE_BQ overrides the betterstack-query.sh path`, `# Observability layer: 6 (sweeper workflow run log + the tracker issue comment)`, `# RETIREMENT:`, `# cq-test-fixtures-synthesized-only`; verdict line `printf 'SOLEUR_SEND_FAILED_ALERT_PROBE verdict=%s detail=%s\n'` with the k=v attributes inside `detail=` (the `betterstack-roundtrip-latency-7855.sh` shape) and `TRANSIENT:` / `ACTION REQUIRED:` prefixes on stderr lines. The `.test.sh` runs the script under `env -i PATH="$WORK/bin:/usr/bin:/bin" HOME=$WORK BETTERSTACK_*=dummy SEND_FAILED_PROBE_BQ=$MOCK` with a `$WORK/bin/curl` stub dispatching on URL (`/api/v2/alerts` vs `/api/v2/incidents`) and appending argv to `$WORK/calls.log` (precedent `anthropic-admin-key-6297.test.sh`), five cases: `pass`→0; `alert_paused`→5 asserting `! grep -q remote calls.log` (warehouse never queried — proves the ordering); `channel_dark`→3 (inngest-only control rows); `row_present_no_incident`→5 (the verdict the feature exists to produce); `curl` rc≠0 on the alerts GET→3 (test-design-reviewer). The ACTION REQUIRED comment the sweeper writes on exit 5 IS the operator artifact (`sweep-followthroughs.sh` writes a comment, not a label) — no script files a separate issue (none has `GH_TOKEN`; spec-flow P1-3).
- [x] Runbook `knowledge-base/engineering/operations/runbooks/monitor-send-failed-alert.md`: **step 0 for a non-technical operator is "paste the alert name into `/soleur:go`"** (the email cannot tell a synthetic page from a real one; only the readback can); **step 1 is the readback SQL** (a count alert's email carries no row text — `channel=`/`http_code=` are only in the warehouse; `doppler run -p soleur -c prd_terraform`, no SSH), then the decode table per `channel=` / `reason=` / `http_code=`; the unit table (the guard's crit set) and the named non-crit allowlist; `synthetic=1` means the probe fired after a predicate-touching merge or a `probe_rev` bump, and the row is otherwise indistinguishable from a real failure (same `-t disk-monitor` tag); `host` is authoritative, `host_name=soleur-inngest-prd` on web-1 is the #6616 stale render; auto-resolve after `recovery_period` ≠ fixed; `SOLEUR_<UNIT>_HALT` rows do NOT page (UC-1); the re-fire procedure (`probe_rev` bump — every re-verification pages ops@ exactly once, which is the intended cost); the `[ack-destroy]` deletion note; the `paused_reason` check and the `heartbeat-reconcile-mismatch` issue that carries `reason=logs-alert-paused|logs-alert-absent`; step 2 for pages is the API read, never the UI: `curl -s -H "Authorization: Bearer $BETTERSTACK_API_TOKEN_READONLY" https://uptime.betterstack.com/api/v2/incidents | jq '.data[] | select(.attributes.cause | test("SOLEUR_")) | {id, name: .attributes.name, cause: .attributes.cause, started_at: .attributes.started_at}'`. Shape (pattern-recognition-specialist): YAML frontmatter (`title/date/owners/category/tags/applies_to: [betterstack-logs-alerts.tf, server.tf, send-failed-alert-probe-8097.sh]/related_issues`), a bold `**TL;DR:**` naming the readback command, an "Alert name / Vendor / Means / Time to page" table as in `www-redirect-alarm.md`, and the phrase "Verify off-host — no SSH" over the decode table. The "optional rule-only CI-ingest probe" is NOT documented — it was cut in Phase 0.6b and would page just the same. No SSH command anywhere.
- [x] `betterstack-log-query.md` §"Standing alarms over this source": add the native-alert entry in that section's existing bullet shape and correct the "no log-alert resource" parenthetical.
- [x] ADR-218 via `/soleur:architecture` + ADR-096 amendment paragraph; `model.c4` :333 one clause; `./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` (from `apps/web-platform`) and `bash plugins/soleur/test/c4-count-parity.test.sh` green.
- [x] Issue #8097 body: append the `<!-- soleur:followthrough script=scripts/followthroughs/send-failed-alert-probe-8097.sh earliest=<merge time + 30 min> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD,BETTERSTACK_API_TOKEN -->` directive + `follow-through` label (`gh issue edit`). PR body uses **`Ref #8097`**, not `Closes` — closure is the follow-through's verdict, after the post-merge apply.

## Files to Create

- `apps/web-platform/infra/betterstack-logs-alerts.tf`
- `apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh`
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`
- `scripts/followthroughs/send-failed-alert-probe-8097.sh`
- `scripts/followthroughs/send-failed-alert-probe-8097.test.sh`
- `knowledge-base/engineering/operations/runbooks/monitor-send-failed-alert.md`
- `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md` (ordinal provisional)

## Files to Edit

- `apps/web-platform/infra/main.tf` — `required_providers.logtail`, `provider "logtail"`
- `apps/web-platform/infra/.terraform.lock.hcl` — logtail provider entry (2 `h1:` platform hashes — `linux_amd64`, `darwin_arm64` — matching the `better-uptime` sibling; the 13 `zh:` lines are release ziphashes, not platforms)
- `apps/web-platform/infra/server.tf` — `terraform_data.send_failed_alert_probe`
- `.github/workflows/apply-web-platform-infra.yml` — two `-target=` additions (main plan allowlist ≈:695-730; SSH apply list ≈:1239)
- `.github/workflows/scheduled-terraform-drift.yml` — `terraform init -input=false` (≈:82) gains `-lockfile=readonly` so the drift plan cannot silently resolve a provider outside the committed lockfile (security-sentinel; the apply workflow already does this at ≈:541)
- `.github/workflows/infra-validation.yml` — steps running the new guard AND its mutation battery in `deploy-script-tests` (registered explicitly, not globbed: "an unrun battery is a claim", ≈:699); `apps/web-platform/test/infra/**` added to both `paths:` filters; the provisioner-parity step name "(#7000 all 15 SSH provisioners)" (≈:770) → 17
- `plugins/soleur/scripts/reconcile-live-heartbeats.ts` + `plugins/soleur/lib/heartbeat-live-reconcile.ts` (second exact-host allow constant; `ViolationReason` widened by two members) + `plugins/soleur/test/heartbeat-live-reconcile.test.ts` + the `scheduled-terraform-drift.yml` issue-body decode list — one `logs_alert` arm (absent / paused → `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH` row, carried by the existing deduped issue)
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` — standing-alarm row + provider-gap correction
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` — amendment paragraph
- `apps/web-platform/infra/web-host-provisioner-parity.test.sh` — `FLOOR_RESOURCES` 16 → 17 (zero-slack doctrine; `server.tf` has 16 SSH-connected `terraform_data` today, the header's "15" is already stale) + header prose → 17
- `apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` — M1 expected string `swept only 15 SSH-connected` → `swept only 16 SSH-connected` (with 17 resources, deleting one leaves 16 and the floor-16 guard would stay GREEN → M1 fails; architecture-strategist)
- `knowledge-base/engineering/architecture/decisions/ADR-114-*.md` — the "(ADR-114 says 12; the real count … is 15)" remark is mechanized by the guard; optional one-line touch to 17
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `betterstack` element (:333), one clause
- `knowledge-base/INDEX.md`, `knowledge-base/kb-tags.txt` — regenerated by the KB lint at /ship (as #8073 did)

## Open Code-Review Overlap

- `apps/web-platform/infra/server.tf` ← #2197 (refactor(billing): SubscriptionStatus type + single-instance throttle doc): **Acknowledge** — #2197 concerns `count`/`for_each` on `hcloud_server.web` and in-memory rate limiters; this plan adds an unrelated `terraform_data` block and does not touch server cardinality.
- No other planned file appears in an open `code-review` issue body (65 open issues scanned).

## Infrastructure (IaC)

### Terraform changes

- Root: `apps/web-platform/infra/` (existing; no new root — `hr-every-new-terraform-root-must-include-an` not triggered).
- New provider: `BetterStackHQ/logtail` `~> 11.2` (docs verified from the provider repo at v11.2.0; `>= 10.9.3` is the provider's own floor, but v11.0.0 replaced chart-level variables with per-alert `variable_value`, so pin above it).
- New resources: `logtail_exploration.monitor_send_failed`, `logtail_exploration_alert.monitor_send_failed`, `terraform_data.send_failed_alert_probe`. No data source (see Proposed Solution 2).
- Sensitive variables: none new. `provider "logtail"` reuses `var.betterstack_api_token` (Doppler `prd_terraform` `BETTERSTACK_API_TOKEN`, already `TF_VAR_`-transformed by every apply job). (deepen-plan Phase 4.8 note: the `var.*_token` PAT-shaped regex matches this name; it is a Better Stack vendor token, not a GitHub credential, and the plan introduces no GitHub write — `hr-github-app-auth-not-pat` does not apply.)

### Apply path

(b) merge-triggered `apply-web-platform-infra.yml`: main plan/apply allowlist creates the exploration + alert; the SSH-provisioned apply over the CF Tunnel bridge fires the probe. Blast radius: zero host config change (the probe writes one journald line); zero downtime. Re-fire: bump `local.monitor_send_failed_probe_rev`, merge (no vendor write).

### Distinctness / drift safeguards

- `dev != prd`: the alert exists only in the prd root (there is one Better Stack team); no dev counterpart.
- State: `terraform.tfstate` gains only the exploration/alert objects (no secrets: the alert carries SQL, thresholds and routing). The ingest token stays where it is (`doppler_secret.inngest_betterstack_logs_token`, provider-marked Sensitive) — the plan deliberately avoids a `logtail_source` data-source read that would duplicate it unflagged.
- Drift: `scheduled-terraform-drift.yml` runs an UNTARGETED plan (no `-target` lines), so a dashboard edit to the alert shows as drift between merges. No `lifecycle.ignore_changes` — `paused` is deliberately managed (`false`), unlike sibling heartbeats whose `paused` is arm-gated; the per-merge re-arm is why the reconcile arm, not the plan, is the detector.

### Vendor-tier reality check

- Escalation policy: gated `count = var.betterstack_paid_tier ? 1 : 0` on the siblings; this alert's `escalation_target` follows the same ternary, so the free tier renders `team_name`, never a paid `policy_id`.
- Telemetry alert count cap on the free tier: undocumented; one alert exists today. If `POST …/alerts` returns a plan-limit error, the apply fails loudly in the workflow and the "Email ops on a non-green apply run" step reports it — the alert is then the expense-gated decision, not a silent skip.

## Architecture Decision (ADR/C4)

### ADR

- **Create ADR-218 (provisional)** — "Native Better Stack Logs alerts are Terraform-managed via the `BetterStackHQ/logtail` provider for stateless per-bucket signals". Decision: the ADR-096 poller pattern stays the default for stateful / newest-scoped signals; a native `logtail_exploration_alert` is the mechanism for pure per-bucket counts with an email-acceptable surface, and both providers share `var.betterstack_api_token`. Records the free-tier surface (team email) and the paid-tier `policy_id` ternary as the routing contract, the `treat_as_zero` rationale, the `probe_rev` probe trigger, the synthetic-probe-through-apply-path verification shape, and the **deliberate exclusion of the `SOLEUR_<UNIT>_HALT` PRIORITY-2 sibling class** (the issue's stated scope; challenged in `specs/<branch>/decision-challenges.md` UC-1), and one sentence reconciling ADR-096's rejection (2) ("the operator surface must be a digest-visible GitHub issue, not an ops@ email"): here email IS the surface because independence from GitHub/Sentry/Resend is the point of the signal, a firing is deliberately not digest-visible, and the reconcile arm covers only the alert's own health; and the **opt-in policy** for future classes: a same-severity `SOLEUR_*` PRIORITY-2 class joins by adding a needle + a guard row + a runbook decode row; a class needing different routing or severity gets its own alert (keeps the free-tier alert count at one).
- ADR-198 (≈:295, "no other Better Stack provider exists in the Terraform registry") is stale but is NOT amended here: one sentence in ADR-218 records it ("ADR-198's no-other-provider premise is stale; `logtail_source` reopens the per-source ingest-token gap and is tracked separately") plus a deferral issue — amending an ADR about a resource this plan does not adopt is text for its own sake (plan-review: DHH, code-simplicity).
- **Amend ADR-096** §"Reprovisioning path + alert recipient" and the §Consequences pattern paragraph: "the `better-uptime` provider has no log-alert resource" gains "— the sibling `logtail` provider does (`logtail_exploration_alert`, first used by ADR-218 / #8097); the poller pattern remains the default for the stateful signal class described here."

### C4 views

All three model files read (`model.c4`, `views.c4`, `spec.c4`). Enumeration: (a) external human actor — `founder` (already modeled, receives the page); (b) external system — `betterstack` (modeled, :333); (c) container/data store — none new; (d) actor↔surface relationship — `betterstack -> founder` (:667) already states the page-on-independent-vendor property ("the exit that survives a Sentry-side outage") and is left unchanged; the `betterstack` element description (:333) gains one clause: "Logs alerts are Terraform-managed via BetterStackHQ/logtail (ADR-218); the first, `soleur-monitor-send-failed-prd`, pages when a web-1 monitor unit's own Resend/Sentry send fails". No new element or edge → no `views.c4` include change. `plugins/soleur/test/c4-count-parity.test.sh` derives no Better Stack count (its `betterstack` row is "out of scope — narrative"), so no count moves; still run it green.

### Sequencing

The ADR is authored in this PR describing the target state; no soak gate on the decision itself. The #8097 closure (not the ADR) is what waits on the follow-through.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the failure mode is a page that does not arrive (status quo) or a page that arrives for a synthetic/SKIPPED row (noise to ops@). Worst case is a false sense of coverage: an alert that exists but is `paused_reason`-paused while the operator believes the send path is watched.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user data is on this path. The alert reads journald rows that carry only marker tokens, HTTP codes and curl return codes; the synthetic row is a fixed literal. The credential used is the existing global token, already in state and Doppler.
- **Brand-survival threshold:** `aggregate pattern` — a missed page compounds into a customer-visible outage only in combination with a second, independent failure (the monitored condition itself).

## Observability

```yaml
liveness_signal:
  what: "the alert object itself, read back: GET https://telemetry.betterstack.com/api/v2/alerts/<id> must return paused=false and empty paused_reason; the follow-through proves the whole chain once via the synthetic row + incident readback"
  cadence: "alert evaluation every 60s over a 300s window (check_period/query_period); follow-through sweeper daily until it passes; self-health read twice daily by the heartbeat-live-reconcile job"
  alert_target: "Better Stack team email (account owner + betteruptime_team_member.ops = ops@jikigai.com) on the free tier; betteruptime_policy.uptime escalation when var.betterstack_paid_tier"
  configured_in: "apps/web-platform/infra/betterstack-logs-alerts.tf (alert + exploration); apps/web-platform/infra/server.tf (probe); scripts/followthroughs/send-failed-alert-probe-8097.sh (readback)"

error_reporting:
  destination: "no Sentry on this path by design — the alert exists to survive a Sentry/Resend outage; apply-time failures surface through apply-web-platform-infra.yml's existing 'Email ops on a non-green apply run' step"
  fail_loud: "terraform apply non-zero on a 403/plan-limit from telemetry.betterstack.com; follow-through exit 5 (row_absent | row_present_no_incident | alert_absent | alert_paused) or exit 3 (channel_dark); exit 1 never used"

failure_modes:
  - mode: "alert created but the template SQL is rejected, or later auto-paused by Better Stack"
    detection: "follow-through step (1) → verdict alert_paused (one-shot); reconcile-live-heartbeats.ts logs_alert arm → SOLEUR_HEARTBEAT_RECONCILE_MISMATCH row (twice daily, survives the per-merge re-arm) — layer 6: scheduled-followthrough-sweeper.yml / scheduled-terraform-drift.yml workflow run log"
    alert_route: "sweeper ACTION REQUIRED comment on #8097 (no page — the operator reads the sweeper comment or the drift workflow's deduped heartbeat-reconcile-mismatch issue and files the .tf fix)"
  - mode: "web-1's live Vector does not ship PRIORITY-2 rows (H2)"
    detection: "follow-through verdict row_absent with the web-1-scoped positive control present (surface under test is layer 3, Vector Source 2; detection is layer 6: sweeper workflow run log + ACTION REQUIRED comment)"
    alert_route: "#8097 stays open; a vector.toml-delivery issue is filed with the readback evidence"
  - mode: "a SEND_SKIPPED, _HALT or foreign _REFUSED row pages"
    detection: "pre-merge: Guard 1 + its mutation battery — layer 6: infra-validation.yml workflow run log; post-merge: runbook step 1 readback SQL (betterstack-query.sh, layer 3 Vector row) names the marker — the count alert's email carries only the fixed incident_cause, never row text"
    alert_route: "CI red before merge; post-merge the email says the rule fired and the runbook's decode table names the fix"
  - mode: "global token lacks Telemetry write authority"
    detection: "apply step fails with HTTP 403 on POST /api/v2/explorations — layer 6: apply-web-platform-infra.yml workflow run log"
    alert_route: "non-green apply email; fallback path in Technical Considerations"
  - mode: "reconcile logs_alert arm UNREACHABLE (telemetry API 5xx/timeout twice daily)"
    detection: "SOLEUR_HEARTBEAT_RECONCILE_UNREACHABLE surface=logs_alert, rc 1 — layer 6: scheduled-terraform-drift.yml run log; the drift workflow keys an issue only on rc 2, so rc 1 is a red run, not an issue"
    alert_route: "no page; the red scheduled run is the signal (existing workflow-failure email); a persistent UNREACHABLE leaves the alert's pause state unobserved between infra merges"
  - mode: "SSH apply gate skips green (ssh_token_gate false) so the probe never fires"
    detection: "apply-web-platform-infra.yml notify-ops-email step on the skipped SSH job; follow-through verdict row_absent after the rev bump (control row present)"
    alert_route: "ops email from the apply run; sweeper ACTION REQUIRED comment on #8097 naming row_absent"
  - mode: "BETTERSTACK_API_TOKEN_READONLY / query secret unset or revoked for the sweeper"
    detection: "follow-through exit 3 channel_dark daily (paged_get refusal names the host only) — layer 6: scheduled-followthrough-sweeper.yml run log + CANNOT ESTABLISH comment"
    alert_route: "no page; #8097 stays open with a daily CANNOT ESTABLISH comment until the secret is restored"

logs:
  where: "Better Stack Logs source 2457081 (rows, read via betterstack-query.sh); Better Stack incidents via GET uptime.betterstack.com/api/v2/incidents with the READONLY token (pages — the runbook's step 2 curl, never the UI); apply-web-platform-infra.yml run log (provisioning)"
  retention: "warehouse hot window ~40 min, archive per source retention (betterstack-log-query.md); incidents indefinitely; workflow logs 90 days"

discoverability_test:
  command: bash apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh
  expected_output: "0 failed"
  # 2026-09-14 (#8097 ship, preflight Check 10): the command was YAML-double-quoted (parsed verbatim -> rc 127 in the sandbox) and expected_output carried a placeholder N; both corrected to the executable form. The guard prints `=== Summary: 58 passed, 0 failed (6 cases) ===` and reads only repo files.
```

## Encryption Posture

```yaml
at_rest:
  - store: "Terraform state, R2 bucket soleur-terraform-state (key web-platform/terraform.tfstate) — gains the exploration/alert objects only"
    mechanism: "provider-managed:Cloudflare R2 server-side encryption at rest (AES-256), https://developers.cloudflare.com/r2/reference/data-security/ retrieved_on 2026-09-12"
    evidence: "apps/web-platform/infra/main.tf backend \"s3\" block (pre-existing store; no new secret enters state — the plan rejected a logtail_source data-source read because the provider does not mark its token attribute Sensitive)"
    defends_against: "offline disclosure of the object store's physical media"
    does_not_defend: "a leaked AWS_ACCESS_KEY_ID/SECRET for the bucket (held only in Doppler prd_terraform); anyone with terraform state read can already read the ingest token via the pre-existing doppler_secret resource"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: R2 exposes no per-object encryption attestation endpoint"
  - store: "Better Stack Telemetry exploration + alert objects (vendor SaaS config; no log content stored by this change)"
    mechanism: "provider-managed:Better Stack security posture (encryption at rest for customer data), https://betterstack.com/security retrieved_on 2026-09-12"
    evidence: "apps/web-platform/infra/betterstack-logs-alerts.tf (objects carry only the SQL predicate, thresholds and routing; no secrets)"
    defends_against: "disclosure of the vendor's storage media"
    does_not_defend: "a leaked BETTERSTACK_API_TOKEN, which can read and rewrite every alert and monitor in the team"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: vendor attestation only"
in_transit:
  - connection: "GitHub Actions runner (terraform, logtail provider) -> https://telemetry.betterstack.com/api/v2 (create/read explorations + alerts)"
    enforced_at: "apps/web-platform/infra/main.tf provider \"logtail\" block; the provider's Go HTTP client uses the platform default TLS verification with no insecure flag exposed in its schema"
    tls: "HTTPS, TLS 1.2+"
    cert_verification: "on"
    does_not_defend: "the bearer token is a long-lived global R&W token; a compromised runner can act as the team on both Uptime and Telemetry APIs"
    disclosed_as: "not-publicly-claimed"
  - connection: "GitHub Actions runner (follow-through sweeper) -> https://<BETTERSTACK_QUERY_HOST> (ClickHouse HTTP, readback) and -> https://uptime.betterstack.com/api/v2/incidents (page readback)"
    enforced_at: "scripts/betterstack-query.sh run_sql() (curl https, basic auth); scripts/followthroughs/send-failed-alert-probe-8097.sh (curl https, bearer)"
    tls: "HTTPS, TLS 1.2+"
    cert_verification: "on (curl default)"
    does_not_defend: "the query credentials read every row in the warehouse, not only this marker"
    disclosed_as: "not-publicly-claimed"
  - connection: "GitHub Actions runner -> web-1:22 over the CF Tunnel SSH bridge (the probe's remote-exec)"
    enforced_at: ".github/actions/cf-tunnel-ssh-bridge (pre-existing; Cloudflare Access-gated), apps/web-platform/infra/server.tf connection block"
    tls: "SSH (ed25519 CI key from var.ci_ssh_private_key) inside a Cloudflare Tunnel TLS session"
    cert_verification: "off — the bridge action uses StrictHostKeyChecking=accept-new with UserKnownHostsFile=/dev/null (TOFU, non-persistent; .github/actions/cf-tunnel-ssh-bridge/action.yml) and the connection block sets no host_key; host identity rests on Cloudflare Access gating the tunnel. Pre-existing, unchanged by this plan"
    does_not_defend: "a compromised CI SSH key holder is root on web-1; a MITM inside the Cloudflare tunnel session on first connect — both unchanged by this plan"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "cert_verification is off on a PRE-EXISTING connection this plan reuses verbatim (every SSH-provisioned terraform_data in server.tf shares it); the Cloudflare Access service-token gate on the tunnel is the identity control, and pinning a host key in the bridge is out of this plan's scope."
  tracking_issue: "#8125 — host-key pinning in cf-tunnel-ssh-bridge / server.tf connection blocks (filed at /work Phase 4.7 alongside #8124, the logtail_source deferral; wg-when-deferring-a-capability-create-a)"
  reevaluate_when: "the bridge action gains a persisted known_hosts / host_key on the terraform_data connection blocks"
  expires_on: "2026-12-12"
```

## Guard Contract

### Guard 1 — betterstack-send-failed-alert drift guard

**Property.** The Terraform predicate that pages on `SOLEUR_*` send failures matches exactly PRIORITY 2 + the `SOLEUR_` prefix + the needle set `{_SEND_FAILED, _REFUSED}`; every `emit_refusal()` in the four documented web-1 monitor scripts (and the synthetic probe line) logs at `user.crit`; every FAILED/REFUSED marker those scripts emit matches a needle; no `SOLEUR_*SKIPPED*` or `SOLEUR_*_HALT*` marker in those scripts matches any needle (both are PRIORITY-2 classes that must never page — `cron-egress-alarm.sh` emits `SEND_SKIPPED` through `emit_refusal` at `user.crit`, so only the needle set stops it); the exploration's source id equals the sink id in `vector.toml`; and `probe_rev` is digits-only.

**Assembly.** Two chokepoints, both read after string-aware comment stripping (the `web-host-provisioner-parity.test.sh` convention). (1) The predicate: the single `sql_query` attribute of `resource "logtail_exploration" "monitor_send_failed"` in `apps/web-platform/infra/betterstack-logs-alerts.tf` — extracted by resource name after whitespace normalization, never by line; the needle list is parsed into a set; `local.vector_prd_source_id` is compared to the `s<id>.` host in `vector.toml`'s `[sinks.betterstack] uri`; `local.monitor_send_failed_probe_rev` must match `^"[0-9]+"$`. (2) The emitters: every `infra/*.sh` (non-test) that DEFINES `emit_refusal()` is discovered by grep — today the four units — and for each, the `emit_refusal()` body must contain `logger -p user.crit`, every `SOLEUR_[A-Z0-9_]*(_SEND_FAILED|_REFUSED)[A-Z0-9_]*` literal in the file must match a needle, and every `SOLEUR_[A-Z0-9_]*(SKIPPED|_HALT)[A-Z0-9_]*` literal must match none; plus the probe's `logger` line in `server.tf` (must carry `-p user.crit` and a needle-matching marker). Discovery by `emit_refusal()` definition (not a hard-coded four-file list) is what lets a compliant fifth unit join without a suite edit and a non-compliant one be found (test-design-reviewer). Non-crit `_REFUSED` emitters elsewhere (`inngest-cutover-flip.sh`, `resend-inbound-bootstrap.sh`) define no `emit_refusal()` that calls `logger -p user.crit` and cannot page through `PRIORITY = '2'`; they are outside the assembly by construction. The `-target` allow-list is NOT in this assembly: the #5566 guard in `terraform-target-parity.test.ts` already reddens on any untargeted resource of any type. Every assertion prints a distinct FAIL string (test-design-reviewer: "RED" is a symptom several assertions share); the floor is ≥ 6 DISTINCT markers across the discovered files.

**The matrix is a committed battery, not a PR-body ritual:** `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` (pristine-copy seams `GUARD_TF=` / `GUARD_SCRIPTS_DIR=` / `GUARD_SERVER_TF=` / `GUARD_VECTOR_TOML=`, `cmp` landed-check, unmutated control first, one expected FAIL string per row), registered in `infra-validation.yml`'s `deploy-script-tests` next to the guard — the `*-mutation.test.sh` convention at `infra-validation.yml` ≈:699 ("an unrun battery is a claim").

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `JSONExtractString(raw, 'PRIORITY') = '2'` from `sql_query` | RED `anchor absent: PRIORITY` |
| 2 | Add `'_SKIPPED'` (or `'_SEND_'`) to the needle list | RED `needle set {…} != {_SEND_FAILED,_REFUSED}` and `forbidden match: SOLEUR_CRON_EGRESS_ALARM_SEND_SKIPPED` |
| 3 | Downgrade `disk-monitor.sh`'s `emit_refusal()` from `logger -p user.crit` to `logger -p user.warning` (or the probe line in `server.tf` likewise) | RED `emitter not crit: disk-monitor.sh` / `probe line not crit` |
| 4 | Drop `'_REFUSED'` from the needle list | RED `needle set {_SEND_FAILED} != {_SEND_FAILED,_REFUSED}` and `crit marker matches no needle: SOLEUR_CONTAINER_RESTART_MONITOR_REFUSED` |
| 5 | Delete or rename `resource "logtail_exploration" "monitor_send_failed"` | RED `sql_query: expected exactly 1 extraction, got 0` (the suite's own dispatch) |
| 6 | Remove `startsWith(JSONExtractString(raw, 'message'), 'SOLEUR_')` | RED `anchor absent: SOLEUR_ prefix` |
| 7 | Add a fifth `infra/foo-monitor.sh` defining `emit_refusal()` with `logger -t foo` (no `-p user.crit`) and emitting `SOLEUR_FOO_SEND_FAILED` | RED `emitter not crit: foo-monitor.sh` — second member after four compliant ones, found by definition-discovery |
| 8 | Change `local.vector_prd_source_id` to `"2457082"` | RED `source id != vector.toml sink` |
| 9 | Set `monitor_send_failed_probe_rev = "1a"` | RED `probe_rev not digits` |

**Harness rows:**

| # | Suite edit / non-canonical input | Expected |
|---|---|---|
| H1a | Delete every `emit_refusal` call from scratch copies of the four scripts (suite unchanged) | RED `markers=0 < floor 6` |
| H1b | Remove the ≥ 6 floor from the suite, rerun H1a | GREEN — recorded as the vacuity the floor prevents (harness negative control; the battery asserts H1a RED and H1b GREEN so a silently-deleted floor is itself RED) |
| H2 | Reorder needles to `['_REFUSED', '_SEND_FAILED']` | must PASS — the needle list is compared as a set |
| H3 | Whitespace/newline re-flow of `sql_query` (HCL heredoc vs quoted string) | must PASS — anchors are matched after whitespace normalization |
| H4 | A fifth `infra/bar-monitor.sh` defining `emit_refusal()` WITH `logger -p user.crit` and emitting `SOLEUR_BAR_SEND_FAILED` | must PASS — a compliant member joins without a suite edit |

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1 `bash apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh` → `=== Summary: N passed, 0 failed (N cases) ===` with `SEND_FAILED_ALERT_MIN_CASES=6`; `bash apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` green (every RED row attributed by FAIL string — 36 rows as landed, `EXPECTED_ROWS` pinned in the battery; H1a RED, H1b GREEN, H2-H5 PASS) — a committed battery, not PR-body evidence.
- [x] AC2 `grep -c 'run: bash apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh' .github/workflows/infra-validation.yml` ≥ 1 and `bash scripts/lint-orphan-test-suites.test.sh` green.
- [x] AC3 `cd apps/web-platform/infra && terraform fmt -check -recursive . && terraform init -backend=false -input=false && terraform validate` green; `.terraform.lock.hcl` has a `registry.terraform.io/betterstackhq/logtail` block with `version = "11.2.0"` and exactly the same `h1:` platform count (2) as the `better-uptime` block; every sibling block is byte-unchanged (`git diff --stat -- apps/web-platform/infra/.terraform.lock.hcl` shows additions only).
- [x] AC4 `grep -c -- '-target=logtail_exploration_alert.monitor_send_failed' .github/workflows/apply-web-platform-infra.yml` = 1, same for `logtail_exploration.monitor_send_failed`; `grep -c -- '-target=terraform_data.send_failed_alert_probe'` = 1 and it sits inside the "Terraform apply (SSH-provisioned resources, over the bridge)" step; `bun test plugins/soleur/test/terraform-target-parity.test.ts` and `bash apps/web-platform/infra/web-host-provisioner-parity.test.sh` green.
- [x] AC5 The predicate in `betterstack-logs-alerts.tf` contains the three anchors `JSONExtractString(raw, 'PRIORITY') = '2'`, `startsWith(JSONExtractString(raw, 'message'), 'SOLEUR_')`, `multiSearchAny(`, its needle list parsed as a set equals `{_SEND_FAILED, _REFUSED}` (order-free), and it contains no `LIKE`; the alert has `on_missing_data = "treat_as_zero"`, `paused = false`, `value = 0`, the comparison attribute set to `"higher_than"`, `email = true`, and an `escalation_target` ternary on `var.betterstack_paid_tier`; `terraform_data.send_failed_alert_probe.triggers_replace` references `local.monitor_send_failed_probe_rev` and no `timestamp()`/`random_*`/per-run value (`grep -n 'timestamp()\|random_' apps/web-platform/infra/server.tf` adds no hit inside the probe block).
- [x] AC6 `scripts/followthroughs/send-failed-alert-probe-8097.test.sh` green (five `env -i` cases with a URL-dispatching `curl` stub + `SEND_FAILED_PROBE_BQ` seam: `pass`→0, `alert_paused`→5 with no warehouse call, `channel_dark`→3, `row_present_no_incident`→5, alerts-GET curl failure→3); `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` OK.
- [x] AC7 `git grep -n 'ADR-218' -- knowledge-base/engineering/architecture/decisions/ADR-096-*.md knowledge-base/engineering/operations/runbooks/betterstack-log-query.md knowledge-base/engineering/architecture/diagrams/model.c4 apps/web-platform/infra/betterstack-logs-alerts.tf` → ≥ 4 hits; the ADR file exists, `grep -c 'ADR-198' <ADR-218 file>` ≥ 1, and `bash scripts/check-adr-ordinals.sh` (the `adr-ordinals` required check) is green; `bash plugins/soleur/test/c4-count-parity.test.sh` and the two vitest C4 suites green.
- [x] AC8a `bun test plugins/soleur/test/heartbeat-live-reconcile.test.ts` green with two new cases: a stubbed `/api/v2/alerts` response with the alert `paused: true` yields `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH … reason=logs-alert-paused` and rc=2; an absent alert yields `reason=logs-alert-absent` and rc=2; a stubbed non-allowlisted host is refused; `actionlint .github/workflows/apply-web-platform-infra.yml .github/workflows/infra-validation.yml` clean.
- [ ] AC8 PR body carries `Ref #8097` (not `Closes`); issue #8097 body carries the follow-through directive and the `follow-through` label (`gh issue view 8097 --json labels,body`).

### Post-merge (automated — no operator step)

- [ ] AC9 `apply-web-platform-infra.yml` run for the merge commit (and the next untargeted drift-cron plan shows `0 to change` for both `logtail_*` resources — no Computed-attribute rewrite drift, terraform-architect #4): main apply shows `logtail_exploration.monitor_send_failed: Creation complete` and `logtail_exploration_alert.monitor_send_failed: Creation complete`; SSH apply shows `terraform_data.send_failed_alert_probe: Creation complete`. Then `curl -s -H "Authorization: Bearer $BETTERSTACK_API_TOKEN_READONLY" https://telemetry.betterstack.com/api/v2/alerts | jq '.data[] | select(.attributes.name == "soleur-monitor-send-failed-prd") | {paused: .attributes.paused, reason: .attributes.paused_reason}'` → `{"paused": false, "reason": null}`.
- [ ] AC10 The follow-through sweeper runs `send-failed-alert-probe-8097.sh` after `earliest=` and it exits 0 with `verdict=pass row_found=1 host=soleur-web-platform control_rows_web1>=1 nonsynthetic_rows=<n> incident_id=<n>`; the sweeper closes #8097. Any other verdict leaves #8097 open with the sweeper's ACTION REQUIRED (exit 5) or CANNOT ESTABLISH (exit 3) comment naming the cause set per `## Hypotheses` §6 — no script files a separate issue.

## Test Scenarios

- Given the `.tf` predicate as written, when the drift guard runs, then every anchor is found and every enumerated `SKIPPED` token fails the needle test.
- Given a scratch copy with the PRIORITY clause removed, when the guard runs, then it exits 1 naming the missing anchor.
- Given a fifth script defining `emit_refusal()` without `logger -p user.crit` and emitting `SOLEUR_FOO_SEND_FAILED`, when the guard runs, then it exits 1 with `emitter not crit: foo-monitor.sh`.
- Given a stubbed alerts list containing the unpaused alert, stubbed warehouse output containing the `synthetic=1 probe_rev=1` row (host `soleur-web-platform`) and one control row with host `soleur-web-platform`, and a stubbed incidents list with an incident whose `cause` equals the alert's `incident_cause` and `started_at` ≥ row `dt` − 600 s, when the follow-through runs, then it prints `verdict=pass` and exits 0.
- Given stubbed warehouse output with a web-1 control row but no `synthetic=1 probe_rev=1` row, when the follow-through runs, then it prints `verdict=row_absent` plus the three candidate causes and exits 5.
- Given stubbed warehouse output with rows only from host `soleur-inngest`, when the follow-through runs, then it prints `verdict=channel_dark host=soleur-web-platform` and exits 3 (never `row_absent`).
- Given a stubbed alerts list where the alert is `paused: true`, when the follow-through runs, then it prints `verdict=alert_paused` with the projected `paused_reason` and exits 5, and `calls.log` shows no warehouse or incidents call.
- Given the stubbed `curl` returns rc=7 on the alerts GET, when the follow-through runs, then it prints `TRANSIENT:` and exits 3 (never 5, never 1).
- Given a stubbed row + web-1 control but an incidents list with no match on `name` or `cause`, when the follow-through runs, then it prints `verdict=row_present_no_incident` with the projected incident list and exits 5.
- Given the merge-triggered apply, when the SSH step fires the probe, then the warehouse holds one PRIORITY-2 row with `host = soleur-web-platform` and `message LIKE '%synthetic=1 probe_rev=1%'`, and Better Stack lists one incident matching the alert by `name` or `cause`.
- **API verify (read-only):** `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh "SELECT count() AS n FROM (SELECT raw, dt FROM remote(\$BS_TABLE) WHERE dt >= now() - INTERVAL 14 DAY UNION ALL SELECT raw, dt FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE dt >= now() - INTERVAL 14 DAY) WHERE JSONExtractString(raw,'PRIORITY') = '2' AND JSONExtractString(raw,'host') = 'soleur-web-platform' AND JSONExtractString(raw,'message') LIKE '%synthetic=1 probe_rev=1%' FORMAT JSONEachRow"` expects `{"n":1}` after the apply.

## Success Metrics

- One incident observed for the synthetic row by the sweeper's first run after `earliest=` (chain proven; the sweeper cannot measure a 15-minute bound and does not try).
- Zero pages from `SEND_SKIPPED` or foreign `_REFUSED` rows over the following 30 days (Guard 1 + PRIORITY clause).
- `paused_reason` stays empty across the reconcile job's twice-daily reads.

## Dependencies & Risks

- **Write authority of the global token on the Telemetry API** — documented, read-probed, apply-proven only. Fallback named above.
- **Template SQL rejected by Better Stack** — surfaces as `paused_reason`; fix is a `.tf` edit + merge.
- **H2 (web-1 does not ship PRIORITY-2 rows)** — the probe discriminates; if H2, the fix is web-1's vector.toml delivery (#6616 class), filed with the evidence; this plan's alert still stands and pages the moment the row path works.
- **Provider maturity** — `logtail` v11.x is young (v11.0.0 on 2026-08-27 changed alert-variable semantics); pin `~> 11.2` and accept `terraform init -upgrade` as the bump path with a lockfile diff.
- **Same-run ordering** of alert creation vs. probe — mitigated by `query_period = 300`; re-fire by `probe_rev` bump if `row_present_no_incident`.

## Research Insights

**Premise Validation (Phase 0.6).** #8097 OPEN, no closing PR. #8073 MERGED 2026-09-12T00:42Z; the four emitters exist at `disk-monitor.sh:125`, `resource-monitor.sh:150`, `container-restart-monitor.sh:137-208`, `cron-egress-alarm.sh:102-171`, all through per-file `emit_refusal()` → `logger -p user.crit -t "$LOG_TAG"`. The post-#8073 apply runs (34662519329, 34679740292) succeeded including the SSH-provisioned step, so the emitters are live on web-1. `betterstack-query.sh --raw-only` exists and does what the caveat says. ADR corpus grep for the mechanism: ADR-096 records the poller-vs-native-alert decision and carves out this signal class; no ADR rejects a native Logs alert for a stateless count. Stale premises: "existing on-call policy" (none live) and "provider has no Logs alert" (true only for `better-uptime`).

**Property List (Phase 0.6b).**

- P1 A `SOLEUR_<UNIT>_SEND_FAILED` / `_REFUSED` row from any of the four web-1 units reaches the on-call within minutes, independently of Sentry and Resend.
- P2 `SOLEUR_*_SEND_SKIPPED` rows, and non-crit `_REFUSED` markers from other scripts, never page.
- P3 The rule is reproducible from the repo (IaC), not from dashboard state.
- P4 The whole chain (emit → journald PRIORITY 2 → web-1 Vector → source 2457081 → alert → page) is proven once by a row that traversed web-1, with no operator SSH.
- P5 Row-existence checks use a query shape that actually matches (`JSONExtractString`, not `--grep PRIORITY=2`).

**Cut List.** Runbook-documented REST request shape (issue fallback) → P3 → covered by the TF resource (cut; the runbook documents the TF re-fire and readback instead). Optional CI direct-ingest verification row (ADR-172) → P4 partial → cannot cover the web-1 link (kept only as an optional rule-only probe in the runbook, not a deliverable). Separate probe PR → P4 → same-run ordering suffices (cut). Tag pin in predicate → P2 → `PRIORITY = '2'` + Guard 1 cover it (cut).

**Relevant files.** `apps/web-platform/infra/vector.toml` (Source 2 at the `[sources.system_journald]` block; sink `[sinks.betterstack]` uri `s2457081.eu-fsn-3`); `apps/web-platform/infra/main.tf` (`required_providers`, `provider "betteruptime"`); `apps/web-platform/infra/uptime-alerts.tf` (`betteruptime_policy.uptime` ternary, `betteruptime_team_member.ops`, free-tier recipient rationale); `apps/web-platform/infra/server.tf` (`terraform_data.disk_monitor_install` pattern); `.github/workflows/apply-web-platform-infra.yml` (main allowlist near `betteruptime_team_member.ops`; SSH list near `terraform_data.disk_monitor_install`); `plugins/soleur/test/terraform-target-parity.test.ts` (#5566 coverage guard; FIX B anchor); `scripts/betterstack-query.sh`; `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh` (write-then-readback precedent); `.github/workflows/scheduled-followthrough-sweeper.yml` (BETTERSTACK_QUERY_* and BETTERSTACK_API_TOKEN already wired); `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`; ADR-096, ADR-172, ADR-197 (a zero is not absence), ADR-130 (credential coverage probe).

**Institutional learnings applied.** `2026-08-12-i-reused-a-monitored-marker-name-and-inherited-its-paging-severity.md` (the synthetic row deliberately reuses the real marker so it inherits the real routing — that IS the test; the `synthetic=1 probe_rev=…` suffix keeps it decodable); `2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop.md` (runbook deletion note); `2026-07-18-web-1-root-doppler-unit-needs-home-and-dedicated-token-and-vector-toml-has-no-running-host-delivery.md` (H2); `integration-issues/2026-06-02-docker-journald-driver-maps-stdout-to-priority-6-filter-by-pino-level.md` (PRIORITY is authoritative for systemd units, not containers — our emitters are units); `best-practices/2026-07-11-cron-egress-sentinel-needs-runbook-row-and-infra-glob-fires-apply.md` (any `infra/**` edit fires the apply; runbook row in the same PR); `2026-06-10-betterstack-quota-diagnosis-host-metrics-dominate-generic-http-sink.md` (Telemetry API sources endpoint as inventory truth); `2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md` (H1/H2 kept UNKNOWN; probe-first).

**External documentation.** `https://github.com/BetterStackHQ/terraform-provider-logtail/blob/main/docs/resources/exploration_alert.md` and `…/exploration.md`, `…/data-sources/source.md`, `…/docs/index.md` (auth: `api_token` / `LOGTAIL_API_TOKEN`); releases v11.2.0 (2026-09-04), v11.0.0 (2026-08-27, alert-variable change); `https://betterstack.com/docs/logs/api/getting-started/` (global tokens accepted); `https://betterstack.com/docs/logs/api/alerts/create/`. `better-uptime` provider `docs/resources/` at v0.22.0 (2026-09-10) still lists no Logs alert resource.

**Live probes this session (read-only).** `GET /api/v2/policies` → `[]`; `GET /api/v2/on-calls` → "Primary on-call schedule" (365422), no users; `GET /api/v2/monitors` → 4 monitors, all `policy_id: null, email: true`; `GET telemetry …/v1/sources` → 2457081 `table_name soleur_inngest_vector_prd_3`; `GET …/v2/alerts` → one pre-existing paused onboarding alert (`escalation_target: "current_team"`); ClickHouse predicate probe → 0 rows (36 h), positive control 8 groups incl. web-1 PRIORITY-5 `SOLEUR_INNGEST_SERVER_PROBE`; constant checks `skipped_matches=0 failed_matches=1 refused_matches=1`; 14-day PRIORITY 0-2 rows: only `soleur-inngest` (12 kernel, 9 sshd).

**Related issues/PRs.** #8073 (emitters), #7898 §2 (parent), #6616 (web-1 `host_name` stale render), #7884 (unmanaged Better Stack monitor precedent), #6291 (ADR-096 poller precedent), #5566 (coverage guard), #4844 (parity guard), #7539 (SSH-skip channel).

**CLAUDE.md / AGENTS conventions honored.** `hr-exhaust-all-automated-options-before`, `hr-never-label-any-step-as-manual-without`, `hr-all-infrastructure-provisioning-servers`, `hr-no-ssh-fallback-in-runbooks`, `hr-no-dashboard-eyeball-pull-data-yourself`, `hr-observability-as-plan-quality-gate`, `hr-verify-repo-capability-claim-before-assert` (provider claim re-verified against the provider repo, not ADR prose), `hr-menu-option-ack-not-prod-write-auth` (no Better Stack write at plan time), `wg-use-closes-n-in-pr-body-not-title-to` (`Ref`, closure by follow-through), `cq-write-failing-tests-before`.

**Advisor consult (Phase 4.5, semantic tier `advisor`).** Verdict: approach sound. Applied (all `mechanical`): resolve H2 before Phase 3 — done at plan time via the deploy-status webhook; separate `probe_rev` from the SQL text; six-state follow-through matching incidents on `name` OR `cause`; confirmed the SSH step cannot run after a failed main apply; `earliest` = merge + 30 min (`taste`, adopted).

**Deploy-status probe (2026-09-13, read-only, no SSH).** `services.vector = active`; `vector_config_identity.sha256 = 6a36d8d3…` == `sha256(vector.toml with @@HOST_NAME@@→soleur-inngest-prd)`; `journald_storage.persistent = true`.

**Functional overlap (Phase 1.5b).** Three registries queried; nothing covers Better Stack Logs alert-as-code via the logtail provider; all suggestions skipped, nothing installed.

**Skill-description budget (Phase 1.8).** No `SKILL.md` edit — skipped.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO re-verified the logtail provider premise independently (registry API: v11.2.0, `exploration`, `exploration_alert`, `source` resource + data source) and ranked nine risks; every rejected alternative held. Folded in: (1) **page-per-merge** — a per-run nonce would fire the probe on every push-triggered SSH apply; the trigger was first made a predicate hash and then, at plan-review, reduced to the literal `probe_rev` local so the probe fires only on an explicit bump. (2) **phantom alert** — a `logtail_*` resource absent from the main allow-list is planned as nothing on a green merge; plan-review then established the existing #5566 guard already covers every resource type, so no new assembly was added. (3) `-lockfile=readonly` makes the lockfile regeneration a hard apply blocker — Phase 0 precondition (terraform-architect corrected the platform count: 2 `h1:` platforms, not 13). (4) `SOLEUR_<UNIT>_HALT` at `user.crit` is an unaddressed sibling class — recorded as UC-1 (the issue's stated scope kept) and as an explicit exclusion in ADR-218. (5) ADR-198 :295 also carries the false "no other provider" premise — recorded in one ADR-218 sentence + a deferral issue; `logtail_source` adoption explicitly out of scope. (6) alert self-health — one arm in the existing `reconcile-live-heartbeats.ts` poller; first-run readback asserts `paused == false`. (7) 403 fallback path named up front. (8) the first-evaluation "race" is a poll budget, not a race — the sweeper's daily cadence makes the poll moot; the 14-day archive-inclusive readback is what matters. (9) `web-host-provisioner-parity.test.sh` prose count 15 → 16. Complexity: medium (1-2 days). New ADR (not amend-only) confirmed for three reasons: new provider in the root; instantiates the ADR-096 exception as a named, grep-findable pattern; two ADRs carry the stale premise. No capability gaps.

**Review agents applied at plan time (Phases 2.8, 3, 4.5):** `terraform-architect` (lockfile platform count 13→2 with the exact `providers lock` command; static `escalation_target` null-sibling block after reading provider source; omit `aggregation_interval`/`series_names*`/`source_variable`; `paused = false` is intent not detector; exact allow-list line positions; `triggers_replace` on a heredoc-derived local is plan-stable), `spec-flow-analyzer` (P0-1 probe key not derivable under the sweeper's `env -i` → `probe_rev` carried in the row and read from the checkout, archive-inclusive 14-day readback; P0-2 guard assembly by marker token with a named non-crit allowlist; P1-1/P1-2 six-verdict script on the sweeper's 0/3/5 exit contract, never exit 1; P1-3 no script files issues; P1-4 incidents matched on `name` OR `cause`, anchored on the row's `dt`; P1-6 positive-coverage mutation row; P1-7 `nonsynthetic_rows` printed; P2 per-merge re-arm masks pauses → drift-cron self-health step; runbook first step is the readback SQL), and the `advisor`-tier consult (see Research Insights). **plan-review panel (DHH, Kieran, code-simplicity, CTO-devex):** applied as Mechanical — Guard 1 shrunk to predicate anchors + needle set-equality + emitter crit/positive-coverage/SKIPPED checks (crit/non-crit classifier, runbook-table comparison, `PASS+FAIL` self-check and the duplicate `-target` assembly cut; Kieran + DHH established the #5566 guard already covers every resource type); probe trigger = `probe_rev` only (hash dropped); follow-through = three exit paths (five `env -i` test cases after deepen-plan); self-health folded into `reconcile-live-heartbeats.ts` as one `logs_alert` arm (no new step/label/dedup); ADR-198 amendment → one ADR-218 sentence + deferral issue; C4 edit → one element clause; runbook drops the ingest-probe section, gains a non-technical step-0 and the re-fire cost note; `incident_cause` carries a full GitHub URL; guard wired in `deploy-script-tests` with the `paths:` filter widened; AC6/AC7 commands corrected (`python3 …`, `bash scripts/check-adr-ordinals.sh`); `fail_loud`/label/"weekly" wording fixed; ADR-218 records the opt-in policy for future PRIORITY-2 classes (CTO-devex `taste`, adopted — one sentence). Standing check (plan-review's concurrent-sessions rule, migrated out of AGENTS.md by #8034): no AC asserts the absence of an ambient signal; AC9/AC10 read post-merge state produced by this change's own apply.

## References & Research

- Similar implementations: `apps/web-platform/infra/uptime-alerts.tf` (`betteruptime_policy.uptime` ternary + `betteruptime_team_member.ops`), `apps/web-platform/infra/server.tf` (`terraform_data.disk_monitor_install`), `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh`
- Best practices: logtail provider docs (URLs above); ADR-172 §2 readback rule; ADR-197
- Related PRs: #8073, #7898

**AC3 actionlint note (2026-09-13):** `actionlint` reports 14 shellcheck info/warning lines across the four touched workflows; the identical 14 appear on `origin/main`'s copies (none in this diff), and no CI job runs actionlint. Recorded, not fixed here.
