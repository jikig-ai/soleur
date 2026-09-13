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
   - `data "logtail_source" "vector_prd" { table_name = "soleur_inngest_vector_prd_3" }` — binds to the existing source 2457081 by its table name (from `GET /api/v1/sources`) without hard-coding the id.
   - `locals { monitor_send_failed_sql = <<-SQL … SQL }` — the predicate below lives in ONE local consumed by both the exploration and the probe's trigger, so the two cannot drift.
   - `resource "logtail_exploration" "monitor_send_failed"` — `name = "soleur-monitor-send-failed-prd"` (Required), `chart { chart_type = "line_chart" }`, `query { query_type = "sql_expression", source_variable = "source", sql_query = local.monitor_send_failed_sql }`, `variable { name = "source", variable_type = "source", values = [data.logtail_source.vector_prd.id] }`, `team_name = "Your team"`.
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
     provisioner "remote-exec" {
       inline = [
         "logger -p user.crit -t disk-monitor 'SOLEUR_DISK_MONITOR_SEND_FAILED channel=resend http_code=000 rc=7 synthetic=1 probe_rev=${local.monitor_send_failed_probe_rev}'",
       ]
     }
   }
   ```

   Ordering is by workflow step order, not `depends_on`: the main (non-SSH) apply (step "Terraform apply", ≈:1016) creates the exploration + alert; the SSH-provisioned apply (≈:1212) fires the probe minutes later. Both are steps of the same `apply` job and the SSH step's `if:` is a plain `steps.ssh_token_gate.outputs.ssh_apply_skip != 'true'` (no `always()`), so a failed main apply stops the job before the probe can fire and consume its trigger. The trigger is a literal `local`, not a reference to the `logtail_*` resources, so the SSH `-target` never drags a non-SSH resource into its plan (`-target` is transitive on references). The probe writes no filesystem destination, so the destination-keyed `web-host-provisioner-parity.test.sh` sees no new artifact to pair with a fresh-boot counterpart — its "15 provisioners" prose count moves to 16 and must be updated in the same PR.
5. **Readback follow-through** `scripts/followthroughs/send-failed-alert-probe-8097.sh` (secrets `BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD,BETTERSTACK_API_TOKEN` — all already wired in `scheduled-followthrough-sweeper.yml`), evaluated in this order so each verdict names ONE cause, and mapped onto the sweeper's exit contract (`scripts/sweep-followthroughs.sh`: 0 PASS closes the issue; 1 FAIL reopens a human-closed issue up to `REOPEN_MAX=3`; 2 NOT YET; 3 CANNOT ESTABLISH; 5 ACTION REQUIRED) — `pass`→0, `channel_dark`→3, `alert_absent`/`alert_paused`/`row_present_no_incident`→5, `row_absent`→5 with the enumerated candidate causes printed (SSH stage green-skipped by the `ssh_token_gate` #7539 arm; main apply failed after creating the exploration; journald/Vector match fault on web-1) — the script cannot read the apply run without `GH_TOKEN` and says so rather than naming one cause; exit 1 is never used (spec-flow P1-1/P1-2): (1) `GET telemetry.betterstack.com/api/v2/alerts` → no alert named `soleur-monitor-send-failed-prd` ⇒ `alert_absent` (main apply never created it); `paused == true` ⇒ `alert_paused` (vendor rejected the query — `paused_reason` printed). This is the load-bearing self-health read AC9 names; the script runs it, not a person; (2) positive-control read: zero rows on the source in the last 40 min ⇒ `channel_dark` (ADR-172 §2 — never `row_absent`); (3) `SELECT dt, JSONExtractString(raw,'host') AS host, JSONExtractString(raw,'message') AS msg … WHERE dt >= now() - INTERVAL 14 DAY AND JSONExtractString(raw,'PRIORITY')='2' AND JSONExtractString(raw,'message') LIKE '%synthetic=1 probe_rev=<rev>%'` over `remote()` UNION ALL `s3Cluster()` (the hot window is ~40 min; the sweeper runs daily at 18:00 UTC so the first readback is up to 24 h post-merge — hot-only would fail by construction), where `<rev>` is read from the checkout: `grep -oE 'monitor_send_failed_probe_rev\s*=\s*"[^"]+"' apps/web-platform/infra/betterstack-logs-alerts.tf` (spec-flow P0-1: the sweeper runs under `env -i` with no Terraform). Zero rows ⇒ `row_absent`; a row whose `host` ≠ `soleur-web-platform` ⇒ `row_present_host_mismatch` (reported, not failed on); (4) `GET uptime.betterstack.com/api/v2/incidents` (no `status` filter — resolved incidents are listed and count) → no incident whose `name` equals the alert name **or** whose `cause` equals the alert's `incident_cause` string, with `started_at` ≥ the matched row's `dt` − 600 s ⇒ `row_present_no_incident` (the raw incident list and the alert's `paused`/`paused_reason` are printed for attribution); else `pass`. The row's own `dt` is the time anchor — the script never needs the merge time. Fields `name`, `cause`, `started_at`, `resolved_at` were verified on real monitor/heartbeat incidents this session; whether a Logs-alert incident carries the alert name in `name` is unproven, which is why `cause` (a string this plan controls) is the second key. The script also prints `nonsynthetic_rows=<n>` — matching rows in the window WITHOUT `synthetic=1` — so a real firing that masks the verdict is visible (spec-flow P1-7).
6. **Drift guard** `apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh` (Guard 1 below), wired into `infra-validation.yml` (the orphan-suite lint `scripts/lint-orphan-test-suites.test.sh` requires every `.test.sh` to be dispatched by a workflow).
7. **Docs:** runbook `monitor-send-failed-alert.md`; a row in `betterstack-log-query.md` §"Standing alarms over this source"; new ADR (provisional **ADR-218**) + ADR-096 amendment; `model.c4` `betterstack` element (:333), one clause.

## Technical Considerations

- **Architecture:** first Terraform-managed Better Stack Logs object; second Better Stack provider in the root sharing one credential. The exploration is an alert-only artifact (no dashboard); `team_name = "Your team"` mirrors `inngest.tf` / `uptime-alerts.tf` (case-sensitive literal).
- **Credential coverage (ADR-130 class):** read coverage of the global token on the Telemetry surface is probed (200 ×4, plus the known-granted control `uptime.betterstack.com/api/v2/monitors`); write coverage is documented ("Global API tokens and Telemetry API tokens accepted", `betterstack.com/docs/logs/api/getting-started/`) but only provable at apply. If the first apply returns 403 on `POST /api/v2/explorations`, the fallback is a Telemetry API token published to `prd_terraform` as a new no-default `TF_VAR_betterstack_telemetry_api_token` — a vendor-dashboard mint, `automation-status: UNVERIFIED — /work runs a Playwright attempt before any operator handoff` (the sequencing rule in this skill's Sharp Edges then applies: split the `.tf` change until the var exists).
- **Template SQL is not validatable offline.** `terraform validate` checks HCL, not the `{{…}}` query. The observable for a broken query is the created alert's read-only `paused_reason` ("complexity issues, too many failures") — AC9 reads it via `GET /api/v2/alerts/<id>` and requires it empty with `paused = false`.
- **`escalation_target` semantics**: verified against provider source (v11.2.0 `alert_shared.go`) — no `ExactlyOneOf`; nulls are skipped on write and not mirrored on read. Phase 0 still runs `terraform init -backend=false && terraform validate` on the exact block before anything else.
- **Lockfile:** the root locks **2 platforms** per provider (the `h1:` entries: `linux_amd64` for CI, `darwin_arm64` for a local workstation — the 13 `zh:` lines are the release's ziphashes, not platforms) and the apply workflow inits with `-lockfile=readonly` (≈:541), so CI cannot self-heal a missing provider entry. Phase 0 runs `cd apps/web-platform/infra && terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` (reads only `required_providers`; no backend creds) and commits the new `betterstackhq/logtail` block (`version = "11.2.0"`, 2 `h1:` + 13 `zh:`, siblings unchanged). Do not add other platforms — that would make the entry inconsistent with every sibling.
- **`-target` allowlists (#5566 coverage guard):** every resource in `*.tf` must be `-target`ed by a per-merge job or listed in `OPERATOR_APPLIED_EXCLUSIONS` (`plugins/soleur/test/terraform-target-parity.test.ts`). `logtail_exploration.*` and `logtail_exploration_alert.*` go in the main plan allowlist next to `betteruptime_team_member.ops`; `terraform_data.send_failed_alert_probe` goes in the SSH apply list next to `disk_monitor_install`. Data sources are not resources and need no target. `-target` is transitive, so the SSH probe references only `hcloud_server.web` (already in state) and a local. A declared `logtail_*` resource missing from the allow-list is already CI-red: the #5566 guard in `plugins/soleur/test/terraform-target-parity.test.ts` ("ALL managed resources are reachable", ≈:1448) enumerates every `resource "TYPE"` of any type — no new guard needed (the first draft of this plan asserted a gap here; Kieran + DHH corrected it against the repo).
- **Alert self-health detector — one arm in an existing poller, not a new step:** `plugins/soleur/scripts/reconcile-live-heartbeats.ts` already runs twice daily from `scheduled-terraform-drift.yml`'s `heartbeat-live-reconcile` job (≈:1315) with `BETTERSTACK_API_TOKEN_READONLY`, reads live Better Stack state, prints `SOLEUR_HEARTBEAT_RECONCILE_{OK,MISMATCH,UNREACHABLE,ERROR}` markers, and the workflow files/updates ONE deduped `heartbeat-reconcile-mismatch` issue from any `^SOLEUR_HEARTBEAT_RECONCILE_` line. Add one arm: `GET https://telemetry.betterstack.com/api/v2/alerts`; if `soleur-monitor-send-failed-prd` is absent or `paused == true`, print `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH kind=logs_alert name=soleur-monitor-send-failed-prd paused=<bool> reason=<paused_reason>`; the existing issue path carries it. No new label, dedup, or `fail_channel` (plan-review: DHH "remove", code-simplicity "fold"; folded because the per-merge re-arm makes the untargeted plan an unreliable detector between infra merges, and the arm is ~15 lines + one test case in `plugins/soleur/test/heartbeat-live-reconcile.test.ts`).
- **`-target`-scoped deletion is a no-op** (learning 2026-07-17): removing the alert later requires the `[ack-destroy]` procedure; the runbook says so.
- **Quota:** the probe adds one PRIORITY-2 row per `probe_rev` bump (~0 rows/day). The alert itself consumes no log quota. Free-tier Telemetry alert count cap is undocumented; one pre-existing paused onboarding alert ("Output utilization high", id 2536305877, dashboard 1025429) already exists and stays unmanaged (same class as the unmanaged monitor #7884).
- **Paging semantics:** `query_period = 300` ≥ the timers' 5-min cadence, so a persisting failure holds ONE open incident instead of flapping; `recovery_period = 600` gives a 10-min quiet window before auto-resolve; `on_missing_data = treat_as_zero` because a count query with no rows returns no bucket — that must read as healthy (0), never as "unknown", or an open incident could never observe recovery.
- **NFR register:** availability of the alerting path (independent vendor) — the change strengthens the "second source" property already recorded on the `betterstack -> founder` edge; no new latency-sensitive path.

## Hypotheses

The plan adds a resource whose definition carries `connection { type = "ssh" … }` applied by CI, so the network-outage checklist applies (`hr-ssh-diagnosis-verify-firewall`, telemetry emitted at plan time).

1. **L3 firewall allow-list (CI egress → web-1:22).** The probe uses the identical CF Tunnel SSH bridge + SSH-provisioned step that delivers the monitor scripts. [verified: run 34679740292, 2026-09-12T07:03Z — "CF Tunnel SSH bridge (gated): success" and the SSH-provisioned step: success; the bridge is Cloudflare Access-gated, not IP-allowlisted, so an admin-IP (`var.admin_ips`) rotation cannot affect it]
2. **L3 DNS/routing.** Not on the path: the bridge dials `hcloud_server.web["web-1"].ipv4_address` via cloudflared, not a hostname. [opt-out with artifact: same run]
3. **L7 TLS/proxy.** Telemetry API over HTTPS from the runner. [verified: four 200s this session from a workstation with the same token; runner egress to `telemetry.betterstack.com` is unproven until first apply — a 000/timeout there is the first thing the apply log shows]
4. **H2 — web-1's live `vector.toml` lacks Source 2 (co-located-era config, #6616 class).** [REFUTED by artifact, no SSH: `GET https://deploy.soleur.ai/hooks/deploy-status` (HMAC + CF Access, creds from Doppler `prd_terraform`, the `vector-redeliver.md` runbook's probe) on 2026-09-13 returned `vector: active`, `vector_config_identity: redis_allowlisted=yes sha256=6a36d8d32cacad301cfcca35ff16c7e4969e80307b76154094f811eedae5ccf5 mtime=1788955749`, and `sed 's|@@HOST_NAME@@|soleur-inngest-prd|g' apps/web-platform/infra/vector.toml | sha256sum` = `6a36d8d3…` — byte-identical to the CURRENT committed config rendered with the known stale host label. Source 2 (`[sources.system_journald]`, PRIORITY 0-2) is therefore live on web-1.]
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

- [ ] `gh issue view 8097 --json state` → `OPEN` (re-check at /work start).
- [ ] `cd apps/web-platform/infra && terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` after adding the provider block; commit the lockfile diff (new block only); `terraform init -backend=false -input=false && terraform validate` green with the exact static `escalation_target` block written.
- [ ] `terraform plan -target=logtail_exploration.monitor_send_failed -target=logtail_exploration_alert.monitor_send_failed` (via the canonical triplet: `export AWS_ACCESS_KEY_ID/SECRET` from Doppler `prd_terraform`, `terraform init -input=false`, `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan …`) shows exactly `2 to add, 0 to change, 0 to destroy` and the data source resolving `id = "2457081"`. No apply from the workstation — the merge-triggered workflow is the apply path.
- [ ] ADR ordinal probe across ALL refs immediately before writing the ADR: `for r in $(git for-each-ref --format='%(refname)' refs/remotes/origin); do git ls-tree -r --name-only "$r" -- knowledge-base/engineering/architecture/decisions/; done | grep -oE 'ADR-[0-9]+' | sort -u -t- -k2 -n | tail -1` → highest today is ADR-217 ⇒ **ADR-218 provisional**; re-run at /ship.
- [ ] Read `plugins/soleur/test/terraform-target-parity.test.ts` name list + `TEST_FLOOR` and `scripts/lint-orphan-test-suites.test.sh` before adding the test/workflow step.

### Phase 1 — RED: drift guard first (`cq-write-failing-tests-before`)

- [ ] Write `apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh` per Guard 1; run it → FAIL (no `.tf` yet). Wire it as a step in `.github/workflows/infra-validation.yml`'s `deploy-script-tests` job next to the provisioner parity guard (≈:770) — NOT in the `validate` matrix job, which runs once per changed root — and add `apps/web-platform/test/infra/**` to the workflow's two `paths:` filters (today only `apps/*/infra/**`) so editing the test itself triggers it; the orphan-suite lint then passes.

### Phase 2 — Terraform (alert)

- [ ] `main.tf`: `required_providers.logtail` + `provider "logtail"` (comment: why the second provider, shared token, ADR-218).
- [ ] `betterstack-logs-alerts.tf`: data source, exploration, alert, `locals.monitor_send_failed_sql` / `monitor_send_failed_probe_rev`, header comment citing ADR-218, the SKIPPED-exclusion rationale from `cron-egress-alarm.sh` ("a future alert rule on SEND_FAILED never pages on configuration"), and a literal 5-line "to add another Logs alert" checklist (local SQL → exploration → alert → two `-target=` lines → standing-alarm row in `betterstack-log-query.md`; same-severity `SOLEUR_*` PRIORITY-2 classes opt in by adding a needle, not a new alert) — siblings carry runbook pointers in `.tf` comments (`uptime-alerts.tf`), and an engineer grepping `logtail_` lands here, not on ADR-218.
- [ ] `.github/workflows/apply-web-platform-infra.yml` main plan allowlist: `-target=logtail_exploration.monitor_send_failed`, `-target=logtail_exploration_alert.monitor_send_failed` (adjacent to `-target=betteruptime_team_member.ops`).
- [ ] Guard 1 → GREEN.

### Phase 3 — Terraform (probe) + parity

- [ ] `server.tf`: `terraform_data.send_failed_alert_probe` (mirror `disk_monitor_install`'s connection block verbatim).
- [ ] SSH apply list: `-target=terraform_data.send_failed_alert_probe` (adjacent to `disk_monitor_install`).
- [ ] `plugins/soleur/test/terraform-target-parity.test.ts`: add the name to the pinned SSH-resource list if the list is exact; `bun test plugins/soleur/test/terraform-target-parity.test.ts` and `bash apps/web-platform/infra/web-host-provisioner-parity.test.sh` green.

### Phase 4 — Follow-through + runbook + ADR/C4

- [ ] `scripts/followthroughs/send-failed-alert-probe-8097.sh` (+ `.test.sh` with a stubbed query function, mirroring `bwrap-probe-selfreport-8016.test.sh`'s shape): three exit paths (`pass`→0; `channel_dark`→3; every other verdict→5, printing the alert state, matched rows and the raw incident list so a human reads the cause once), verdict labels kept as printed text (`alert_absent` / `alert_paused` / `row_absent` / `row_present_no_incident`; `host_mismatch` as a printed attribute); the `.test.sh` covers the three exit paths from stubbed `curl`/query output (DHH: a six-arm test for a run-once script is ceremony; 14 of 71 follow-throughs carry a test, so one small one is the convention). The ACTION REQUIRED comment the sweeper writes on exit 5 IS the operator artifact (`sweep-followthroughs.sh` writes a comment, not a label) — no script files a separate issue (none has `GH_TOKEN`; spec-flow P1-3).
- [ ] Runbook `knowledge-base/engineering/operations/runbooks/monitor-send-failed-alert.md`: **step 0 for a non-technical operator is "paste the alert name into `/soleur:go`"** (the email cannot tell a synthetic page from a real one; only the readback can); **step 1 is the readback SQL** (a count alert's email carries no row text — `channel=`/`http_code=` are only in the warehouse; `doppler run -p soleur -c prd_terraform`, no SSH), then the decode table per `channel=` / `reason=` / `http_code=`; the unit table (the guard's crit set) and the named non-crit allowlist; `synthetic=1` means the probe fired after a predicate-touching merge or a `probe_rev` bump, and the row is otherwise indistinguishable from a real failure (same `-t disk-monitor` tag); `host` is authoritative, `host_name=soleur-inngest-prd` on web-1 is the #6616 stale render; auto-resolve after `recovery_period` ≠ fixed; `SOLEUR_<UNIT>_HALT` rows do NOT page (UC-1); the re-fire procedure (`probe_rev` bump — every re-verification pages ops@ exactly once, which is the intended cost); the `[ack-destroy]` deletion note; the `paused_reason` check and the `heartbeat-reconcile-mismatch` issue that carries `kind=logs_alert`. The "optional rule-only CI-ingest probe" is NOT documented — it was cut in Phase 0.6b and would page just the same. No SSH command anywhere.
- [ ] `betterstack-log-query.md` §"Standing alarms over this source": add the native-alert row and correct the "no log-alert resource" parenthetical.
- [ ] ADR-218 via `/soleur:architecture` + ADR-096 amendment paragraph; `model.c4` :333 one clause; `./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` (from `apps/web-platform`) and `bash plugins/soleur/test/c4-count-parity.test.sh` green.
- [ ] Issue #8097 body: append the `<!-- soleur:followthrough script=scripts/followthroughs/send-failed-alert-probe-8097.sh earliest=<merge time + 30 min> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD,BETTERSTACK_API_TOKEN -->` directive + `follow-through` label (`gh issue edit`). PR body uses **`Ref #8097`**, not `Closes` — closure is the follow-through's verdict, after the post-merge apply.

## Files to Create

- `apps/web-platform/infra/betterstack-logs-alerts.tf`
- `apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh`
- `scripts/followthroughs/send-failed-alert-probe-8097.sh`
- `scripts/followthroughs/send-failed-alert-probe-8097.test.sh`
- `knowledge-base/engineering/operations/runbooks/monitor-send-failed-alert.md`
- `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md` (ordinal provisional)

## Files to Edit

- `apps/web-platform/infra/main.tf` — `required_providers.logtail`, `provider "logtail"`
- `apps/web-platform/infra/.terraform.lock.hcl` — logtail provider entry (2 `h1:` platform hashes — `linux_amd64`, `darwin_arm64` — matching the `better-uptime` sibling; the 13 `zh:` lines are release ziphashes, not platforms)
- `apps/web-platform/infra/server.tf` — `terraform_data.send_failed_alert_probe`
- `.github/workflows/apply-web-platform-infra.yml` — two `-target=` additions (main plan allowlist ≈:695-730; SSH apply list ≈:1239)
- `.github/workflows/infra-validation.yml` — step running the new test in `deploy-script-tests`; `apps/web-platform/test/infra/**` added to both `paths:` filters; the provisioner-parity step name "(#7000 all 15 SSH provisioners)" (≈:770) → 16
- `plugins/soleur/scripts/reconcile-live-heartbeats.ts` + `plugins/soleur/test/heartbeat-live-reconcile.test.ts` — one `logs_alert` arm (absent / paused → `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH` row, carried by the existing deduped issue)
- `plugins/soleur/test/terraform-target-parity.test.ts` — SSH-resource name list / floor
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` — standing-alarm row + provider-gap correction
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` — amendment paragraph
- `apps/web-platform/infra/web-host-provisioner-parity.test.sh` — header prose count 15 → 16 (destination-keyed logic needs no change; run it to confirm)
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `betterstack` element (:333), one clause
- `knowledge-base/INDEX.md`, `knowledge-base/kb-tags.txt` — regenerated by the KB lint at /ship (as #8073 did)

## Open Code-Review Overlap

- `apps/web-platform/infra/server.tf` ← #2197 (refactor(billing): SubscriptionStatus type + single-instance throttle doc): **Acknowledge** — #2197 concerns `count`/`for_each` on `hcloud_server.web` and in-memory rate limiters; this plan adds an unrelated `terraform_data` block and does not touch server cardinality.
- No other planned file appears in an open `code-review` issue body (65 open issues scanned).

## Infrastructure (IaC)

### Terraform changes

- Root: `apps/web-platform/infra/` (existing; no new root — `hr-every-new-terraform-root-must-include-an` not triggered).
- New provider: `BetterStackHQ/logtail` `~> 11.2` (docs verified from the provider repo at v11.2.0; `>= 10.9.3` is the provider's own floor, but v11.0.0 replaced chart-level variables with per-alert `variable_value`, so pin above it).
- New resources: `logtail_exploration.monitor_send_failed`, `logtail_exploration_alert.monitor_send_failed`, `terraform_data.send_failed_alert_probe`; data source `logtail_source.vector_prd`.
- Sensitive variables: none new. `provider "logtail"` reuses `var.betterstack_api_token` (Doppler `prd_terraform` `BETTERSTACK_API_TOKEN`, already `TF_VAR_`-transformed by every apply job).

### Apply path

(b) merge-triggered `apply-web-platform-infra.yml`: main plan/apply allowlist creates the exploration + alert; the SSH-provisioned apply over the CF Tunnel bridge fires the probe. Blast radius: zero host config change (the probe writes one journald line); zero downtime. Re-fire: bump `local.monitor_send_failed_probe_rev`, merge (no vendor write).

### Distinctness / drift safeguards

- `dev != prd`: the alert exists only in the prd root (there is one Better Stack team); no dev counterpart.
- State: `terraform.tfstate` gains the exploration/alert objects and the `logtail_source` data-source read (its `token` attribute is the ingest token already present in state via `doppler_secret.inngest_betterstack_logs_token`; no new secret class).
- Drift: `scheduled-terraform-drift.yml` runs an UNTARGETED plan (no `-target` lines), so a dashboard edit to the alert shows as drift between merges. No `lifecycle.ignore_changes` — `paused` is deliberately managed (`false`), unlike sibling heartbeats whose `paused` is arm-gated; the per-merge re-arm is why the reconcile arm, not the plan, is the detector.

### Vendor-tier reality check

- Escalation policy: gated `count = var.betterstack_paid_tier ? 1 : 0` on the siblings; this alert's `escalation_target` follows the same ternary, so the free tier renders `team_name`, never a paid `policy_id`.
- Telemetry alert count cap on the free tier: undocumented; one alert exists today. If `POST …/alerts` returns a plan-limit error, the apply fails loudly in the workflow and the "Email ops on a non-green apply run" step reports it — the alert is then the expense-gated decision, not a silent skip.

## Architecture Decision (ADR/C4)

### ADR

- **Create ADR-218 (provisional)** — "Native Better Stack Logs alerts are Terraform-managed via the `BetterStackHQ/logtail` provider for stateless per-bucket signals". Decision: the ADR-096 poller pattern stays the default for stateful / newest-scoped signals; a native `logtail_exploration_alert` is the mechanism for pure per-bucket counts with an email-acceptable surface, and both providers share `var.betterstack_api_token`. Records the free-tier surface (team email) and the paid-tier `policy_id` ternary as the routing contract, the `treat_as_zero` rationale, the predicate-hash probe trigger, the synthetic-probe-through-apply-path verification shape, and the **deliberate exclusion of the `SOLEUR_<UNIT>_HALT` PRIORITY-2 sibling class** (the issue's stated scope; challenged in `specs/<branch>/decision-challenges.md` UC-1), and the **opt-in policy** for future classes: a same-severity `SOLEUR_*` PRIORITY-2 class joins by adding a needle + a guard row + a runbook decode row; a class needing different routing or severity gets its own alert (keeps the free-tier alert count at one).
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
    detection: "follow-through step (1) → verdict alert_paused (one-shot); reconcile-live-heartbeats.ts logs_alert arm → SOLEUR_HEARTBEAT_RECONCILE_MISMATCH row (twice daily, survives the per-merge re-arm)"
    alert_route: "sweeper ACTION REQUIRED comment on #8097; the existing deduped heartbeat-reconcile-mismatch issue"
  - mode: "web-1's live Vector does not ship PRIORITY-2 rows (H2)"
    detection: "follow-through verdict row_absent with positive control present"
    alert_route: "#8097 stays open; a vector.toml-delivery issue is filed with the readback evidence"
  - mode: "a SEND_SKIPPED or foreign _REFUSED row pages"
    detection: "Guard 1 (predicate anchors + emitter enumeration) at CI; the incident's message in the email names the marker"
    alert_route: "CI red before merge; post-merge the email itself is the signal and the runbook's decode table names the fix"
  - mode: "global token lacks Telemetry write authority"
    detection: "apply step fails with HTTP 403 on POST /api/v2/explorations"
    alert_route: "non-green apply email; fallback path in Technical Considerations"

logs:
  where: "Better Stack Logs source 2457081 (rows); Better Stack incidents list (pages); apply-web-platform-infra.yml run log (provisioning)"
  retention: "warehouse hot window ~40 min, archive per source retention (betterstack-log-query.md); incidents indefinitely; workflow logs 90 days"

discoverability_test:
  command: "bash apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh"
  expected_output: "=== Summary: N passed, 0 failed === with the predicate anchors, the four emitter files and the SKIPPED-exclusion constant check all PASS (no credentials: the suite reads repo files only)"
```

## Encryption Posture

```yaml
at_rest:
  - store: "Terraform state, R2 bucket soleur-terraform-state (key web-platform/terraform.tfstate) — gains the exploration/alert objects and the logtail_source data-source read"
    mechanism: "provider-managed:Cloudflare R2 server-side encryption at rest (AES-256), https://developers.cloudflare.com/r2/reference/data-security/ retrieved_on 2026-09-12"
    evidence: "apps/web-platform/infra/main.tf backend \"s3\" block (pre-existing store; no new secret class — the data source's token attribute is the ingest token already present via doppler_secret.inngest_betterstack_logs_token)"
    defends_against: "offline disclosure of the object store's physical media"
    does_not_defend: "a leaked AWS_ACCESS_KEY_ID/SECRET for the bucket (held only in Doppler prd_terraform); anyone with terraform state read can read the ingest token"
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
    cert_verification: "on (host key pinned by the bridge action; pre-existing)"
    does_not_defend: "a compromised CI SSH key holder is root on web-1 — unchanged by this plan"
    disclosed_as: "not-publicly-claimed"
```

## Guard Contract

### Guard 1 — betterstack-send-failed-alert drift guard

**Property.** The Terraform predicate that pages on `SOLEUR_*` send failures matches exactly PRIORITY 2 + the `SOLEUR_` prefix + the needle set `{_SEND_FAILED, _REFUSED}`; every `emit_refusal()` in the four documented web-1 monitor scripts (and the synthetic probe line) logs at `user.crit`; every FAILED/REFUSED marker those scripts emit matches a needle; and no `SOLEUR_*SKIPPED*` marker in those scripts matches any needle — so a `SEND_SKIPPED` row can never page and a documented failure can never fail to.

**Assembly.** Two chokepoints. (1) The predicate: the single `sql_query` attribute of `resource "logtail_exploration" "monitor_send_failed"` in `apps/web-platform/infra/betterstack-logs-alerts.tf` — extracted by resource name after whitespace normalization, never by line; the needle list is parsed into a set. (2) The emitters: the four scripts named in the suite (`disk-monitor.sh`, `resource-monitor.sh`, `container-restart-monitor.sh`, `cron-egress-alarm.sh`) — for each, the `emit_refusal()` body must contain `logger -p user.crit`, and every `SOLEUR_[A-Z0-9_]*(_SEND_FAILED|_REFUSED)[A-Z0-9_]*` and `SOLEUR_[A-Z0-9_]*SKIPPED[A-Z0-9_]*` literal in the file is tested against the needle set (match required / match forbidden); plus the probe's `logger` line in `server.tf` (must carry `-p user.crit` and a needle-matching marker). Non-crit `_REFUSED` emitters elsewhere in `infra/*.sh` cannot page through `PRIORITY = '2'` by construction and are NOT enumerated — an earlier draft's crit/non-crit classifier with a named allowlist was cut at plan-review as a static analyzer defending a three-line predicate. The `-target` allow-list is NOT in this assembly: the #5566 guard in `terraform-target-parity.test.ts` already reddens on any untargeted resource of any type.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `JSONExtractString(raw, 'PRIORITY') = '2'` from `sql_query` | RED — predicate anchor absent |
| 2 | Add `'_SKIPPED'` (or `'_SEND_'`) to the needle list | RED — needle set ≠ `{_SEND_FAILED, _REFUSED}`, and `SOLEUR_CRON_EGRESS_ALARM_SEND_SKIPPED` now matches a needle |
| 3 | Downgrade `disk-monitor.sh`'s `emit_refusal()` from `logger -p user.crit` to `logger -p user.warning` (or the probe line in `server.tf` likewise) | RED — an enumerated emitter no longer logs at PRIORITY 2 |
| 4 | Drop `'_REFUSED'` from the needle list | RED — set inequality, and `SOLEUR_CONTAINER_RESTART_MONITOR_REFUSED` matches no needle (positive coverage) |
| 5 | Delete or rename `resource "logtail_exploration" "monitor_send_failed"` | RED — the suite's own dispatch: `sql_query` extraction must yield exactly one non-empty string and the emitter walk must enumerate ≥ 6 FAILED/REFUSED markers (floor pattern: `MIN_SSH_PROVISIONED` in `terraform-target-parity.test.ts`) |
| 6 | Remove `startsWith(JSONExtractString(raw, 'message'), 'SOLEUR_')` | RED — predicate anchor absent |

**Harness rows:**

| # | Suite edit / non-canonical input | Expected |
|---|---|---|
| H1 | Remove the ≥ 6 marker floor from the suite, then delete every `emit_refusal` call from a scratch copy of the four scripts | RED — without the floor the walk enumerates 0 markers and the per-marker assertions never run; the floor is what makes silence RED |
| H2 | Reorder needles to `['_REFUSED', '_SEND_FAILED']` | must PASS — the needle list is compared as a set |
| H3 | Whitespace/newline re-flow of `sql_query` (HCL heredoc vs quoted string) | must PASS — anchors are matched after whitespace normalization |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `bash apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh` → `0 failed`, ≥ 6 cases; all six mutation rows reproduced RED on a scratch copy and rows H2-H3 GREEN (evidence pasted in the PR body).
- [ ] AC2 `grep -c 'run: bash apps/web-platform/test/infra/betterstack-send-failed-alert.test.sh' .github/workflows/infra-validation.yml` ≥ 1 and `bash scripts/lint-orphan-test-suites.test.sh` green.
- [ ] AC3 `cd apps/web-platform/infra && terraform fmt -check -recursive . && terraform init -backend=false -input=false && terraform validate` green; `.terraform.lock.hcl` has a `registry.terraform.io/betterstackhq/logtail` block with `version = "11.2.0"` and exactly the same `h1:` platform count (2) as the `better-uptime` block; every sibling block is byte-unchanged (`git diff --stat -- apps/web-platform/infra/.terraform.lock.hcl` shows additions only).
- [ ] AC4 `grep -c -- '-target=logtail_exploration_alert.monitor_send_failed' .github/workflows/apply-web-platform-infra.yml` = 1, same for `logtail_exploration.monitor_send_failed`; `grep -c -- '-target=terraform_data.send_failed_alert_probe'` = 1 and it sits inside the "Terraform apply (SSH-provisioned resources, over the bridge)" step; `bun test plugins/soleur/test/terraform-target-parity.test.ts` and `bash apps/web-platform/infra/web-host-provisioner-parity.test.sh` green.
- [ ] AC5 The predicate in `betterstack-logs-alerts.tf` contains the three anchors `JSONExtractString(raw, 'PRIORITY') = '2'`, `startsWith(JSONExtractString(raw, 'message'), 'SOLEUR_')`, `multiSearchAny(`, its needle list parsed as a set equals `{_SEND_FAILED, _REFUSED}` (order-free), and it contains no `LIKE`; the alert has `on_missing_data = "treat_as_zero"`, `paused = false`, `value = 0`, the comparison attribute set to `"higher_than"`, `email = true`, and an `escalation_target` ternary on `var.betterstack_paid_tier`; `terraform_data.send_failed_alert_probe.triggers_replace` references `local.monitor_send_failed_probe_rev` and no `timestamp()`/`random_*`/per-run value (`grep -n 'timestamp()\|random_' apps/web-platform/infra/server.tf` adds no hit inside the probe block).
- [ ] AC6 `scripts/followthroughs/send-failed-alert-probe-8097.test.sh` green (stubbed alerts + query + incidents responses drive the three exit paths — `pass`→0, `channel_dark`→3, one exit-5 verdict); `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` OK.
- [ ] AC7 `git grep -n 'ADR-218' -- knowledge-base/engineering/architecture/decisions/ADR-096-*.md knowledge-base/engineering/operations/runbooks/betterstack-log-query.md knowledge-base/engineering/architecture/diagrams/model.c4 apps/web-platform/infra/betterstack-logs-alerts.tf` → ≥ 4 hits; the ADR file exists, `grep -c 'ADR-198' <ADR-218 file>` ≥ 1, and `bash scripts/check-adr-ordinals.sh` (the `adr-ordinals` required check) is green; `bash plugins/soleur/test/c4-count-parity.test.sh` and the two vitest C4 suites green.
- [ ] AC8a `bun test plugins/soleur/test/heartbeat-live-reconcile.test.ts` green with a new case: a stubbed `/api/v2/alerts` response with the alert `paused: true` yields a `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH kind=logs_alert` line, and an absent alert yields the same with `paused=absent`; `actionlint .github/workflows/apply-web-platform-infra.yml .github/workflows/infra-validation.yml` clean.
- [ ] AC8 PR body carries `Ref #8097` (not `Closes`); issue #8097 body carries the follow-through directive and the `follow-through` label (`gh issue view 8097 --json labels,body`).

### Post-merge (automated — no operator step)

- [ ] AC9 `apply-web-platform-infra.yml` run for the merge commit (and the next untargeted drift-cron plan shows `0 to change` for both `logtail_*` resources — no Computed-attribute rewrite drift, terraform-architect #4): main apply shows `logtail_exploration.monitor_send_failed: Creation complete` and `logtail_exploration_alert.monitor_send_failed: Creation complete`; SSH apply shows `terraform_data.send_failed_alert_probe: Creation complete`. Then `curl -s -H "Authorization: Bearer $BETTERSTACK_API_TOKEN_READONLY" https://telemetry.betterstack.com/api/v2/alerts | jq '.data[] | select(.attributes.name == "soleur-monitor-send-failed-prd") | {paused: .attributes.paused, reason: .attributes.paused_reason}'` → `{"paused": false, "reason": null}`.
- [ ] AC10 The follow-through sweeper runs `send-failed-alert-probe-8097.sh` after `earliest=` and it exits 0 with `verdict=pass row_found=1 host=soleur-web-platform control_rows>=1 nonsynthetic_rows=<n> incident_id=<n>`; the sweeper closes #8097. Any other verdict leaves #8097 open with the sweeper's ACTION REQUIRED (exit 5) or CANNOT ESTABLISH (exit 3) comment naming the cause set per `## Hypotheses` §6 — no script files a separate issue.

## Test Scenarios

- Given the `.tf` predicate as written, when the drift guard runs, then every anchor is found and every enumerated `SKIPPED` token fails the needle test.
- Given a scratch copy with the PRIORITY clause removed, when the guard runs, then it exits 1 naming the missing anchor.
- Given a fifth script emitting `SOLEUR_FOO_SEND_FAILED` at `user.notice`, when the guard runs, then it exits 1 naming the file and the missing `-p user.crit`.
- Given a stubbed alerts list containing the unpaused alert, stubbed warehouse output containing the `synthetic=1 probe_rev=1` row (host `soleur-web-platform`) and one control row, and a stubbed incidents list with an incident whose `cause` equals the alert's `incident_cause` and `started_at` ≥ row `dt` − 600 s, when the follow-through runs, then it prints `verdict=pass` and exits 0.
- Given stubbed warehouse output with a control row but no `synthetic=1 probe_rev=1` row, when the follow-through runs, then it prints `verdict=row_absent` plus the three candidate causes and exits 5.
- Given stubbed warehouse output with no rows at all, when the follow-through runs, then it prints `verdict=channel_dark` and exits 3 (never `row_absent`).
- Given a stubbed alerts list where the alert is absent or `paused: true`, when the follow-through runs, then it prints `verdict=alert_absent` / `verdict=alert_paused reason=…` and exits 5 before any warehouse read (one stubbed case in the `.test.sh` covers the exit-5 path).
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
**Assessment:** CTO re-verified the logtail provider premise independently (registry API: v11.2.0, `exploration`, `exploration_alert`, `source` resource + data source) and ranked nine risks; every rejected alternative held. Folded in: (1) **page-per-merge** — a per-run nonce would fire the probe on every push-triggered SSH apply; the trigger is now `sha256(local.monitor_send_failed_sql)` so the probe fires only when the predicate is created or changed. (2) **phantom alert** — a `logtail_*` resource absent from the main allow-list is planned as nothing on a green merge; plan-review then established the existing #5566 guard already covers every resource type, so no new assembly was added. (3) `-lockfile=readonly` makes the lockfile regeneration a hard apply blocker — Phase 0 precondition (terraform-architect corrected the platform count: 2 `h1:` platforms, not 13). (4) `SOLEUR_<UNIT>_HALT` at `user.crit` is an unaddressed sibling class — recorded as UC-1 (the issue's stated scope kept) and as an explicit exclusion in ADR-218. (5) ADR-198 :295 also carries the false "no other provider" premise — recorded in one ADR-218 sentence + a deferral issue; `logtail_source` adoption explicitly out of scope. (6) alert self-health — one arm in the existing `reconcile-live-heartbeats.ts` poller; first-run readback asserts `paused == false`. (7) 403 fallback path named up front. (8) the first-evaluation "race" is a poll budget, not a race — the sweeper's daily cadence makes the poll moot; the 14-day archive-inclusive readback is what matters. (9) `web-host-provisioner-parity.test.sh` prose count 15 → 16. Complexity: medium (1-2 days). New ADR (not amend-only) confirmed for three reasons: new provider in the root; instantiates the ADR-096 exception as a named, grep-findable pattern; two ADRs carry the stale premise. No capability gaps.

**Review agents applied at plan time (Phases 2.8, 3, 4.5):** `terraform-architect` (lockfile platform count 13→2 with the exact `providers lock` command; static `escalation_target` null-sibling block after reading provider source; omit `aggregation_interval`/`series_names*`/`source_variable`; `paused = false` is intent not detector; exact allow-list line positions; `triggers_replace` on a heredoc-derived local is plan-stable), `spec-flow-analyzer` (P0-1 probe key not derivable under the sweeper's `env -i` → `probe_rev` carried in the row and read from the checkout, archive-inclusive 14-day readback; P0-2 guard assembly by marker token with a named non-crit allowlist; P1-1/P1-2 six-verdict script on the sweeper's 0/3/5 exit contract, never exit 1; P1-3 no script files issues; P1-4 incidents matched on `name` OR `cause`, anchored on the row's `dt`; P1-6 positive-coverage mutation row; P1-7 `nonsynthetic_rows` printed; P2 per-merge re-arm masks pauses → drift-cron self-health step; runbook first step is the readback SQL), and the `advisor`-tier consult (see Research Insights). **plan-review panel (DHH, Kieran, code-simplicity, CTO-devex):** applied as Mechanical — Guard 1 shrunk to predicate anchors + needle set-equality + emitter crit/positive-coverage/SKIPPED checks (crit/non-crit classifier, runbook-table comparison, `PASS+FAIL` self-check and the duplicate `-target` assembly cut; Kieran + DHH established the #5566 guard already covers every resource type); probe trigger = `probe_rev` only (hash dropped); follow-through = three exit paths with a three-case test; self-health folded into `reconcile-live-heartbeats.ts` as one `logs_alert` arm (no new step/label/dedup); ADR-198 amendment → one ADR-218 sentence + deferral issue; C4 edit → one element clause; runbook drops the ingest-probe section, gains a non-technical step-0 and the re-fire cost note; `incident_cause` carries a full GitHub URL; guard wired in `deploy-script-tests` with the `paths:` filter widened; AC6/AC7 commands corrected (`python3 …`, `bash scripts/check-adr-ordinals.sh`); `fail_loud`/label/"weekly" wording fixed; ADR-218 records the opt-in policy for future PRIORITY-2 classes (CTO-devex `taste`, adopted — one sentence). Standing check `cq-ac-must-not-depend-on-concurrent-sessions`: no AC asserts the absence of an ambient signal; AC9/AC10 read post-merge state produced by this change's own apply.

## References & Research

- Similar implementations: `apps/web-platform/infra/uptime-alerts.tf` (`betteruptime_policy.uptime` ternary + `betteruptime_team_member.ops`), `apps/web-platform/infra/server.tf` (`terraform_data.disk_monitor_install`), `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh`
- Best practices: logtail provider docs (URLs above); ADR-172 §2 readback rule; ADR-197
- Related PRs: #8073, #7898
