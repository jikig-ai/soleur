# Tasks: #7884 health monitor keyword import + live Better Stack inventory reconcile

Plan: `knowledge-base/project/plans/2026-09-15-fix-health-monitor-supabase-keyword-import-plan.md`

## Phase 0: Preconditions

- [ ] 0.1 Re-read live monitor 4226366 + monitor/heartbeat lists (READONLY token); stop the monitor half if gone or not `status`
- [ ] 0.2 Keyword probe (merge gate): orphan sweep, one transient `soleur-probe-7884` keyword monitor, `up` reading, PATCH to never-matching keyword, `down` reading, trap delete + 404; record in PR body; apply the decision rule (keyword vs status branch)
- [ ] 0.3 Targeted read-only plan for `betteruptime_monitor.app_health` (mirrors the apply job; dummy ssh key var); require `1 to import, 0 to add, 1 to change, 0 to destroy`, no `-/+`, limited attribute diff
- [ ] 0.4 ADR-222 ordinal probe across all `origin/*` refs (repeat before merge)

## Phase 1: Monitor import + keyword

- [ ] 1.1 RED: `apps/web-platform/test/server/health-keyword-monitor-contract.test.ts` (Guard 1 rows 1-8, H1-H4, branch-aware)
- [ ] 1.2 `variables.tf` `adopt_app_health_monitor`; tftest override `false`; gated `import {}` + `betteruptime_monitor.app_health` in `uptime-alerts.tf`
- [ ] 1.3 `-target=betteruptime_monitor.app_health` in the per-merge apply job
- [ ] 1.4 Rewrite `uptime-alerts.tf` quota header and #7884 bullet; repoint the apex "10 monitors" sentence
- [ ] 1.5 GREEN: fmt, validate, `terraform test`, contract test, target-parity, canonicalizer + mutation, seo-config-rules test

## Phase 2: Reconcile

- [ ] 2.1 RED: Guard 2 rows 1-14, H1-H6 in `heartbeat-live-reconcile.test.ts`; update the "no logtail declared" `seen` list; real-infra-dir resolution test
- [ ] 2.2 Lib: `resolveInfraVariables`, exact `for_each`/`count` resolution, discriminated violation union, `reconcileMonitors`, `findUnmanagedHeartbeats`, `null`/`""` keyword equality
- [ ] 2.2.1 Script: monitors arm (always runs), row id mapping, url-less row error, marker vocabulary, `resource=` appended, INVENTORY marker, markers before code combine
- [ ] 2.3 Workflow (existing steps only): fail-closed lookup, `(resource|id)=` escalation key with boundary, decode list, `infra-drift` label, per-class sentences + subjects, failure-triggered email/Sentry; actionlint + `bash -n` extracted bodies
- [ ] 2.4 Local read-only live run; paste output (no `${each.key}`, `matched=` has 4226366, INVENTORY, zero unmanaged)

## Phase 3: Records

- [ ] 3.1 ADR-222 via `/soleur:architecture` (pager contract + declared-or-reported rule; residual gaps; `adopting` on status branch)
- [ ] 3.2 ADR-117 amendment (exact resolution, `resource=` field, one-time re-escalation)
- [ ] 3.3 ADR-204 Residual gap + Consequences
- [ ] 3.4 ADR-149 INVENTORY pointer
- [ ] 3.5 Runbook `app-database-readiness-alarm.md` (no SSH; service-role-key cause; H-F remedy; post-mortem path inline)
- [ ] 3.6 C4 edges; `scripts/regenerate-c4-model.sh`; freshness + count-parity tests
- [ ] 3.7 Prose sweep of heartbeats-only descriptions (ADR-141, sentry cron-monitors.tf, function-registry-count test)

## Phase 4: Issue housekeeping

- [ ] 4.1 File the undeclared Logs alert issue (`Output utilization high`)
- [ ] 4.2 Close #8140 as duplicate of #6645 with comments on both
- [ ] 4.3 Status branch only: keyword follow-up issue (`Phase 4: Validate + Scale`, `priority/p1-high`)

## Phase 5: Ship-time checks

- [ ] 5.1 PR body: `Ref #7884`; Phase 0.2/0.3/2.4 outputs; decision challenges rendered
- [ ] 5.2 Post-merge: AC17 apply + read-back (≥360 s, `last_checked_at`), AC18 reconcile run, AC19 close or comment on #7884
