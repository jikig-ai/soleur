---
plan: ../../plans/2026-05-27-fix-sentry-cron-community-monitor-missed-checkin-plan.md
branch: feat-one-shot-fix-sentry-cron-community-monitor
lane: single-domain
---

# Tasks: fix Sentry cron monitor scheduled-community-monitor missed check-in

Derived from `2026-05-27-fix-sentry-cron-community-monitor-missed-checkin-plan.md`.

## Phase 1: Diagnose (operator-side) — Deferred to #4533

- [ ] 1.1 Cross-cron health check — Tracks #4533
- [ ] 1.2 Query Inngest function registry — Tracks #4533
- [ ] 1.3 Check Inngest server logs — Tracks #4533
- [ ] 1.4 Check Inngest run history — Tracks #4533
- [x] 1.5 Verify Sentry heartbeat env vars — **DONE: All 3 present in Doppler prd. Hypothesis D eliminated.**
- [ ] 1.6 Document confirmed root cause — Tracks #4533

## Phase 2: Fix (based on diagnosis) — Deferred to #4533

- [ ] 2.1–2.7 — Tracks #4533

## Phase 3: Preventive Measures (code changes)

- [x] 3.1 Create `apps/web-platform/test/server/inngest/function-registry-count.test.ts`:
  - [x] 3.1.1 Assert function count in route.ts matches expected 40
  - [x] 3.1.2 Assert every `cron-*.ts` file has a corresponding route.ts entry
  - [x] 3.1.3 Assert every cron function's SENTRY_MONITOR_SLUG has a matching `cron-monitors.tf` resource
- [x] 3.2 Update `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` — added H9 (Inngest server desync after deploy churn)
- [x] 3.3 Write compound learning at `knowledge-base/project/learnings/bug-fixes/` documenting timeline, diagnosis, and fix
