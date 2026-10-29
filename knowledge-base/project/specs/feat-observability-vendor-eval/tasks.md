---
title: Tasks — Right-size observability spend
feature: feat-observability-vendor-eval
plan: knowledge-base/project/plans/2026-10-29-feat-observability-vendor-eval-plan.md
status: pending
---

# Tasks

## Phase 1 — Enumerate

- [x] 1.1 Static live-vs-declared diff done → `monitor-prune-inventory.md` (67 declared, ~all have producers; only `cron-egress-resolve` unmatched — verify live slug before any delete). **Remaining: live-API pass** — `sentry-monitors-audit.sh` + `reconcile-live-heartbeats.ts` with `SENTRY_IAC_AUTH_TOKEN`
- [ ] 1.2 Resolve `needs-verdict` rows using #6591 catch-value evidence (needs Sentry API incident history); dead-man/self-watch monitors = KEEP — KEEP candidates shortlisted in inventory
- [x] 1.3 Write `alert-ingest-map.md` — all 19 alerts read journald on source 2457081; **none consume host_metrics** → safe aggressive trim

## Phase 2 — Sentry prune (#6590)

- [ ] 2.1 Amend `ADR-031-*` (monitor-per-cron → monitored-where-silence-undetectable)
- [ ] 2.2 Delete pruned `sentry_cron_monitor` blocks in `infra/sentry/cron-monitors.tf`
- [ ] 2.3 Apply via `apply-sentry-infra.yml`; verify destroys land in plan output pre-merge

## Phase 3 — Better Stack ingest cut (#7577)

- [ ] 3.1 `vector.toml` compaction transform for multi-line `app_container_journald` (join BEFORE `pii_scrub_*` ordering preserved)
- [ ] 3.2 `host_metrics` interval raise + family filter to alert-map consumers only
- [ ] 3.3 `vector validate` in CI; apply via infra path
- [ ] 3.4 24–48 h `betterstack-query.sh` row-rate verification
- [ ] 3.5 Verify ~$68 plan name/tier; downgrade if fits; update `expenses.md:49-50`

## Phase 4 — Verify and record

- [ ] 4.1 Fire-test: one retained cron monitor, `app_health` pager, redirect-health, one `logtail_exploration_alert`, send-failed pager, incident mirror → GH issue
- [ ] 4.2 Comment execution evidence on #6590 + #7577
- [ ] 4.3 gdpr-gate at work Phase 2 exit (vector.toml is a regulated-data surface)

## Acceptance Criteria

- [ ] AC1 Sentry projected invoice ≤ ~$40/mo
- [ ] AC2 Better Stack projected ≤ ~$40/mo
- [ ] AC3 Zero coverage regressions (fire-test pass)
- [ ] AC4 ADR-031 amendment committed; issue comments recorded
