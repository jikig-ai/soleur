---
title: The soleur-monitor-send-failed-prd alert fired (a web-1 monitor could not send, or the Inngest TLS terminator refused)
date: 2026-09-13
owners: engineering/ops
category: infrastructure
tags: [better-stack, logs-alert, logtail, monitors, resend, sentry, journald, vector, paging]
applies_to:
  - apps/web-platform/infra/betterstack-logs-alerts.tf
  - apps/web-platform/infra/server.tf
  - scripts/followthroughs/send-failed-alert-probe-8097.sh
  - plugins/soleur/scripts/reconcile-live-heartbeats.ts
related_issues: [8097, 8073, 7898]
---

# Runbook: `soleur-monitor-send-failed-prd` fired

**TL;DR:** the email cannot say which unit or why — a count alert carries only its fixed
`incident_cause`. Step 0 is to paste the alert name into `/soleur:go`; the agent then runs
step 1, the readback SQL below, which names the marker, the channel and the HTTP code. Verify
off-host — no SSH is needed at any step.

## What this alert is

| Alert name | Vendor | Means | Time to page |
|---|---|---|---|
| `soleur-monitor-send-failed-prd` | Better Stack (Logs alert, `logtail_exploration_alert`) | One of the four web-1 monitor units, or (since #8706) the LUKS probe's emit helper, tried to page (Resend email or Sentry event) and the send **failed** or was **refused**. The monitored condition itself (disk / memory / container restart / cron egress / LUKS at-rest drift) may be live and unreported. **Since #10136 it also carries a marker that is not a send failure and does not come from web-1**: `SOLEUR_INNGEST_TLS_REFUSED`, logged by the dedicated Inngest host when its TLS terminator is down or its certificate is within 90 days of expiry (decode row below). | ≤ ~6 min (check every 60 s over a 300 s window) |

The email's `cause` line is fixed text in `betterstack-logs-alerts.tf` (`incident_cause`). It is host-neutral since #10136: it names
"a host monitor unit", either a web-1 monitor's own send failure or the Inngest host's `SOLEUR_INNGEST_TLS_REFUSED`. Incidents opened
before that wording change carry the older text ("from a web-1 monitor unit"), which is inaccurate for the Inngest marker. For
`SOLEUR_INNGEST_TLS_REFUSED` the emitter is `soleur-inngest-tls-health.service` on the Inngest host (the readback's `host` column says
so), never web-1.

It reads Better Stack Logs source `2457081` for PRIORITY-2 journald rows whose message starts
with `SOLEUR_` and contains `_SEND_FAILED` or `_REFUSED` (predicate in
`betterstack-logs-alerts.tf`). It pages by email to the team surface every sibling monitor uses;
on the paid tier it escalates to `betteruptime_policy.uptime`. It auto-resolves after a 10-minute
quiet window (`recovery_period = 600`) — **resolved ≠ fixed**; a unit that fails to send once
every 5 minutes holds the incident open, one that failed once lets it resolve.

Decision record: [ADR-218](../../architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md).

## Step 0 — non-technical path

Paste `soleur-monitor-send-failed-prd` into `/soleur:go`. Nothing in the email distinguishes a
synthetic verification page from a real one; only the readback does.

## Step 1 — the readback (what actually fired)

```bash
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  "SELECT dt, JSONExtractString(raw,'host') AS host, JSONExtractString(raw,'SYSLOG_IDENTIFIER') AS unit,
          JSONExtractString(raw,'message') AS msg
   FROM (SELECT dt, raw FROM remote(\$BS_TABLE) WHERE dt >= now() - INTERVAL 1 DAY
         UNION ALL
         SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1 AND dt >= now() - INTERVAL 1 DAY)
   WHERE JSONExtractString(raw,'PRIORITY') = '2'
     AND startsWith(JSONExtractString(raw,'message'), 'SOLEUR_')
     AND multiSearchAny(JSONExtractString(raw,'message'), ['_SEND_FAILED', '_REFUSED'])
   ORDER BY dt DESC LIMIT 50 FORMAT JSONEachRow"
```

Never `--grep PRIORITY=2`: `--grep` compiles to `raw LIKE '%…%'` over the double-encoded `raw`
column and cannot see a field. `JSONExtractString(raw, …)` is the field read. `host` is
authoritative for which machine emitted the row; `host_name` on web-1 still carries the stale
`soleur-inngest-prd` render (#6616) and must not be read.
(Measured 2026-09-27, #8706: web-1's `web-git-data-probe` rows read `host_name` and `host` both
`soleur-web-platform`, so the stale render may be gone. `host` stays the field to read here.)

### Decode the marker

| Marker | Unit | Channel | Read it as |
|---|---|---|---|
| `SOLEUR_DISK_MONITOR_SEND_FAILED channel=resend http_code=<c> rc=<r>` | `disk-monitor` | Resend | The `[CRIT]/[WARN]` disk email did not go out. `http_code=000 rc=7` = no connection (egress / DNS); `4xx` = key or payload rejected; `5xx` = Resend-side. |
| `SOLEUR_RESOURCE_MONITOR_SEND_FAILED channel=resend …` | `resource-monitor` | Resend | Same decode; the memory/CPU-pressure email. |
| `SOLEUR_CONTAINER_RESTART_MONITOR_SEND_FAILED channel=sentry\|resend …` | `container-restart-monitor` | Sentry or Resend | `channel=sentry reason=jq` = jq missing on the host; `http_code=` = the ingest/API refused. |
| `SOLEUR_CONTAINER_RESTART_MONITOR_REFUSED channel=sentry reason=<token>` | `container-restart-monitor` | Sentry | The Sentry destination was refused **before** any send (a DSN that is not the pinned host, a malformed DSN). Configuration, not a network fault. |
| `SOLEUR_CRON_EGRESS_ALARM_SEND_FAILED channel=sentry\|resend …` | `cron-egress-alarm` | Sentry or Resend | The cron-egress firewall alarm could not page. |
| `SOLEUR_CRON_EGRESS_ALARM_REFUSED channel=sentry reason=<token>` | `cron-egress-alarm` | Sentry | As above: refused destination. |
| `SOLEUR_WORKSPACES_LUKS_SEND_FAILED reason=<r> drift_reason=<slug>` | `luks-monitor` (emitter `apps/web-platform/infra/workspaces-luks-emit.sh`, #8706) | Sentry | A LUKS at-rest drift event was lost. `<r>` is `no_dsn` or `send_failed`. `no_dsn` = no `SOLEUR_SENTRY_DSN=` line resolved on the host; `send_failed` = the Sentry POST failed (ingest or egress). `drift_reason` is the lost event's reason. Decode: [the cutover runbook's host-timer section](./workspaces-luks-cutover-6604.md#host-timer-liveness-alert-8706), step D. |
| `SOLEUR_INNGEST_TLS_REFUSED reason=<r>[,<r>] unit=<state> fetch_rc=<n> nrestarts=<n> notafter_days=<n>` | `inngest-tls-health` (the Inngest host's `soleur-inngest-tls-health.timer`, every 5 min; script `soleur-inngest-tls` in `cloud-init-inngest.yml`, #10136) | none (host-local check) | Not a send failure: the Inngest link TLS listener is unhealthy. `reason=listener_down` = nothing is bound on `10.0.1.40:8443` (`unit=` is the stunnel unit state, `nrestarts=` its restart count). `fetch_rc` separates the causes: `0` = key and cert were fetched, so stunnel itself failed (port busy, bad config); `91`/`92` = runtime directory or temp dir; `93`/`94` = the `INNGEST_TLS_KEY`/`INNGEST_TLS_CERT` read from Doppler failed or the env file was missing (`90` surfaces as `93`); `95` = the key does not match the cert, or either is unparseable; `96` = publishing the pair failed. `reason=cert_expiring` = `notafter_days` is under 90 (a re-mint is a certificate publish, an Inngest host replace and a flip, see [`inngest-server.md`](./inngest-server.md) "Link TLS (#10136)"); a row with `notafter_days=0` and a non-zero `fetch_rc` is a certificate that was never installed, not an expiry (the day count is computed from an empty date). Both reasons can appear in one row (`listener_down,cert_expiring`). Read the periodic `stage=tls-health` row in the same window for the rest (`served_sha256` against `cert_sha256`, the nft counters): `--grep stage=tls-health --since 1h`. |
| `… synthetic=1 probe_rev=<n>` on any of the above | `disk-monitor` tag | — | **The verification probe.** Not a real failure — see [Synthetic rows](#synthetic-rows). |

Rows that **never** page, by construction (a `SOLEUR_*_SEND_SKIPPED` or `SOLEUR_*_HALT` row in the
same window is context, not the cause):

- `SOLEUR_<UNIT>_SEND_SKIPPED channel=… reason=unset|cooldown|jq|token_shape` — a deliberate skip (a channel's
  env unset, cooldown, jq missing, or — `container-restart-monitor` / `cron-egress-alarm` only, which still
  have the Sentry channel — a Resend key that fails the token-shape guard, #9597). Configuration; the alert's
  needles cannot match it. Fix a `token_shape` skip by re-setting `RESEND_API_KEY` in Doppler `prd` (a stray
  space, quote or newline), never via SSH.
- `SOLEUR_DISK_MONITOR_REFUSED` / `SOLEUR_RESOURCE_MONITOR_REFUSED channel=resend reason=token_shape` — **does
  page** (it matches the `_REFUSED` needle): those two units have no second channel, so a Resend key that
  fails the token-shape guard is an unusable alert path, the same condition a 401 `SEND_FAILED` reported
  before the key moved onto curl's stdin config (#9597). Same fix: re-set `RESEND_API_KEY` in Doppler `prd`.
- `SOLEUR_<UNIT>_HALT reason=xtrace-credential-bound issue=7797` — the unit refused to run under
  shell tracing with a credential bound. Deliberately outside this alert's scope
  (decision-challenges UC-1 in the #8097 spec; ADR-218). Opting in is one more needle.
- `SOLEUR_INNGEST_CUTOVER_SEAM_REFUSED` (PRIORITY 5) and `SOLEUR_RESEND_INBOUND_BOOTSTRAP_REFUSED`
  (never enters journald) — foreign `_REFUSED` markers the `PRIORITY = '2'` clause excludes.

### Then fix the send path, not the alert

The monitored condition may still be live. In order: (1) read the unit's own row for the
underlying condition (`… --grep 'SOLEUR_DISK_MONITOR'` etc. over the same window, or the
`disk-monitor.sh` / `resource-monitor.sh` / `container-restart-monitor.sh` /
`cron-egress-alarm.sh` bodies for what each sends); (2) for `channel=resend` check the Resend
status page and the `RESEND_API_KEY` in Doppler `prd`; (3) for `channel=sentry` check the DSN the
unit reads (`/etc/default/<unit>` on the host is written by `server.tf`'s provisioner from
`var.*`) and Sentry's ingest status. A fix that changes a provisioned file lands through
`apply-web-platform-infra.yml` on merge — never through an SSH session.

## Step 2 — the incident record (pages, never the UI)

```bash
curl -s -H "Authorization: Bearer $(doppler secrets get BETTERSTACK_API_TOKEN_READONLY -p soleur -c prd_terraform --plain)" \
  'https://uptime.betterstack.com/api/v2/incidents?page=1' \
  | jq '.data[] | select(.attributes.cause | test("SOLEUR_")) | {id, name: .attributes.name, cause: .attributes.cause, started_at: .attributes.started_at, resolved_at: .attributes.resolved_at}'
```

The list is newest-first, 10 per page; `page=1` is the most recent incidents. Walk
`pagination.next` only when the incident predates the first page.

## Synthetic rows

`terraform_data.send_failed_alert_probe` (`server.tf`) writes one
`SOLEUR_DISK_MONITOR_SEND_FAILED channel=resend http_code=000 rc=7 synthetic=1 probe_rev=<n>` row
through web-1's real journald → Vector → Logs path whenever `local.monitor_send_failed_probe_rev`
(`betterstack-logs-alerts.tf`) changes — and never otherwise. It reuses the real marker on purpose
so it inherits the real routing: that *is* the test. The row is otherwise indistinguishable from a
real failure (same `-t disk-monitor` tag), so a page carrying `synthetic=1` is expected exactly
once per rev bump. The follow-through `scripts/followthroughs/send-failed-alert-probe-8097.sh`,
run daily by `scheduled-followthrough-sweeper.yml`, reads the row and its incident back and is
what closes #8097 (`verdict=pass`), or names the one cause that stopped the chain (`alert_absent`,
`alert_paused`, `channel_dark`, `row_absent`, `row_present_no_incident`).

**Re-verification = bump the rev and merge.** Change `monitor_send_failed_probe_rev = "1"` to
`"2"` (digits only; a `lifecycle.precondition` refuses anything else) and merge. Every
re-verification pages once — the intended cost. Changed the SQL? Bump the rev. A rev bump performs
zero Better Stack API writes, so it never perturbs the alert under test. One re-fire without a
bump: a failed provisioner (SSH down mid-apply) taints the resource, and the next apply re-runs it
at the same rev — a page carrying the old `probe_rev` right after a red apply run is that retry.

## Alert self-health

Better Stack auto-pauses an alert whose query it rejects (`paused_reason` "complexity issues" /
"too many failures"). Two readers, no dashboard:

- The follow-through's first check is `paused == false` (`alert_paused` verdict otherwise).
- `plugins/soleur/scripts/reconcile-live-heartbeats.ts` (twice daily from
  `scheduled-terraform-drift.yml`) carries a `logs_alert` arm: a paused or absent declared alert
  prints `SOLEUR_HEARTBEAT_RECONCILE_MISMATCH name=soleur-monitor-send-failed-prd live=logs_alert
  reason=logs-alert-paused|logs-alert-absent`, followed by the routing tokens `resource=` and
  `route=` and, last, `detail="…"`, and lands in the existing deduped
  `heartbeat-reconcile-mismatch` issue. The untargeted drift plan is **not** the detector: the
  per-merge apply re-arms `paused = false` silently, so a vendor pause only shows in the plan
  between infra merges.

A rejected query is a `.tf` edit + merge (the apply re-arms the alert); an absent alert means the
merge apply failed before creating it — read the run.

## Deleting or changing the alert

The per-merge apply is `-target`-scoped (`apply-web-platform-infra.yml` main plan allowlist), so
removing `logtail_exploration.monitor_send_failed` / `logtail_exploration_alert.monitor_send_failed`
from the `.tf` is a silent no-op live until the `[ack-destroy]` procedure runs (learning
2026-07-17, `target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop`). Attribute
edits apply on merge. `critical_alert = false` is the knob that would bypass quiet hours on the
paid tier; no sibling sets it.

## Adding another Logs alert

Five steps, listed in `betterstack-logs-alerts.tf`'s header (predicate local → exploration → alert
→ two `-target=` lines → a standing-alarm row in
[`betterstack-log-query.md`](./betterstack-log-query.md)). A same-severity `SOLEUR_*` PRIORITY-2
class joins **this** alert by adding a needle (+ a guard row + a decode row above), not a new alert.
