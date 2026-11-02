---
title: Alert ingest map — what the 19 logtail_exploration_alert rules consume
date: 2026-10-29
---

# Alert ingest map

**All 19 `logtail_exploration` queries read ONE source: `2457081`
(`local.vector_prd_source_id`)** — the Vector prd sink carrying journald
rows (tagged by SYSLOG_IDENTIFIER) and `host_metrics` shipped as log rows.

## What the alerts actually consume: journald content only

Every alert is a journald-emitter probe (per file-header: "disk-monitor /
resource-monitor / container-restart-monitor / cron-egress-alarm emit a
PRIORITY-2 journald row `SOLEUR_<UNIT>_SEND_FAILED…`"). None of the 19 query
`host_metrics` fields. Groups:

- **Emit-path pagers**: `monitor_send_failed` (SOLEUR_*_SEND_FAILED rows)
- **LUKS/volume probes**: `inngest_luks_wrong_volume`,
  `inngest_luks_key_probe_fail`, `inngest_luks_wrong_volume`/`_luks_key_probe`,
  `luks_monitor_host_timer_dark`, `workspaces_luks_deadman_fired`
- **Registry/zot**: `registry_clientip_not_rfc1918`,
  `registry_store_not_luks`, `registry_zot_log_credential_shape`,
  `ghcr_hostsfile_deny_lost`
- **Egress guards**: `egress_gw_deny_spike`, `egress_gw_probe_fail`,
  `egress_gw_probe_silent`
- **Cost/sandbox**: `claude_cost_capture_dark`, `claude_cost_daily_burn`,
  `agent_sandbox_bash_denial`, `faithful_canary_sandbox_broken`,
  `web_nic_guard_unpinned_url`, `inngest_step_524`

## Consequence for the ingest cut (#7577)

- **`host_metrics` is safe to trim to zero or a heavily-sampled remainder**
  for this alert set — no alert consumes it. It was >99% of ingest at the
  2026-06 quota near-miss. Any residual need for host CPU/disk trending is a
  dashboard convenience, not an alert dependency. (Verify no Better Stack
  dashboard depends on it before full removal; sampling to 5–15 min
  intervals is the conservative first cut.)
- **Multi-line compaction (`app_container_journald`, ~75% of ingest)** must
  join continuation lines BEFORE the `pii_scrub_*` transforms so redaction
  still sees complete messages — and must not merge across SYSLOG_IDENTIFIER
  boundaries (alert predicates match per-emitter rows).
- `sinks.betterstack` and the `host_scripts_journald` 31-tag allowlist are
  the chokepoint for any source-level drops.

## Verified-by-grep anchors

- `apps/web-platform/infra/betterstack-logs-alerts.tf` — all 19 queries use
  `values = [local.vector_prd_source_id]` = source 2457081
- `apps/web-platform/infra/vector.toml` — 6 sources; alert-relevant rows come
  from the journald sources, `host_metrics` from the dedicated source block
