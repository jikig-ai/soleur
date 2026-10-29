---
title: Tasks — Right-size observability spend
feature: feat-observability-vendor-eval
plan: knowledge-base/project/plans/2026-10-29-feat-observability-vendor-eval-plan.md
status: pending
---

# Tasks

## Phase 1 — Enumerate

- [x] 1.1 Static live-vs-declared diff done → `monitor-prune-inventory.md` (67 declared, ~all have producers; only `cron-egress-resolve` unmatched — verify live slug before any delete). **Remaining: live-API pass** — `sentry-monitors-audit.sh` + `reconcile-live-heartbeats.ts` with `SENTRY_IAC_AUTH_TOKEN`
- [x] 1.2 Resolved via live Sentry API pass — audit + 90d `/stats/` per monitor; verdict: 24 KEEP / 43 PRUNE with per-row surviving-signal citations in `monitor-prune-inventory.md`
- [x] 1.3 Write `alert-ingest-map.md` — all 19 alerts read journald on source 2457081; **none consume host_metrics** → safe aggressive trim

## Phase 2 — Sentry prune (#6590)

- [x] 2.1 ADR-031 amended (Amendment 2026-10-29 — monitor-per-cron → monitored-where-silence-undetectable, new-cron opt-in)
- [ ] 2.2 **PR-B (follow-up):** delete 43 `sentry_cron_monitor` blocks + unrouted entries + README-listed removal edits (`NON_INNGEST_MONITORS`, `[ack-destroy]` trailer, count citations). PR-A unbinds via `cron_monitor_alert_unrouted` (two-PR removal rule)
- [ ] 2.3 PR-B: apply via `apply-sentry-infra.yml`; verify destroys land in plan output pre-merge

## Phase 3 — Better Stack ingest cut (#7577)

- [x] 3.1 `transforms.app_container_compaction` added (reduce, group_by SYSLOG_IDENTIFIER+CONTAINER_NAME, concat_newline) — joins before `pii_scrub_drop_userdata` inputs
- [x] 3.2 host_metrics 300s→900s, collectors → [memory, filesystem] (zero alert consumers per alert-ingest-map)
- [ ] 3.3 vector.toml deploys via `terraform_data` file-provisioner + reload on web-1 apply
- [ ] 3.4 24–48 h `betterstack-query.sh` row-rate verification
- [x] 3.5 expenses.md updated w/ Sentry post-prune projection (~$50.94) + ingest-cut note; Better Stack tier verify remains per existing verify_by=2026-11-12 marker (no usage/billing API — measured 404s today)

## Phase 4 — Verify and record

- [ ] 4.1 Fire-test: one retained cron monitor, `app_health` pager, redirect-health, one `logtail_exploration_alert`, send-failed pager, incident mirror → GH issue
- [ ] 4.2 Comment execution evidence on #6590 + #7577
- [ ] 4.3 gdpr-gate at work Phase 2 exit (vector.toml is a regulated-data surface)

## Acceptance Criteria

- [ ] AC1 Sentry projected invoice ≤ ~$40/mo
- [ ] AC2 Better Stack projected ≤ ~$40/mo
- [ ] AC3 Zero coverage regressions (fire-test pass)
- [ ] AC4 ADR-031 amendment committed; issue comments recorded
