---
plan: ../../plans/2026-05-27-fix-sentry-cron-community-monitor-missed-checkin-plan.md
branch: feat-one-shot-fix-sentry-cron-community-monitor
lane: single-domain
---

# Tasks: fix Sentry cron monitor scheduled-community-monitor missed check-in

Derived from `2026-05-27-fix-sentry-cron-community-monitor-missed-checkin-plan.md`.

## Phase 1: Diagnose (operator-side)

- [ ] 1.1 Query Inngest function registry: verify `cron-community-monitor` is registered and total count matches expected ~39
- [ ] 1.2 Check Inngest server logs for OOM, restart, error, sync issues in the 2026-05-26 to 2026-05-27 window
- [ ] 1.3 Verify Sentry heartbeat env vars (SENTRY_INGEST_DOMAIN, SENTRY_PROJECT_ID, SENTRY_PUBLIC_KEY) are present in Doppler prd
- [ ] 1.4 Check Inngest run history for cron-community-monitor -- did it fire on May 26/27? What was the outcome?
- [ ] 1.5 Document confirmed root cause (Hypothesis A/B/C/D or new)

## Phase 2: Fix (based on diagnosis)

- [ ] 2.1 Apply the hypothesis-specific fix (restart Inngest server, adjust schedule, raise MemoryMax, or fix env vars)
- [ ] 2.2 Trigger manual community-monitor fire via Inngest event
- [ ] 2.3 Verify Sentry cron monitor shows successful check-in after manual trigger
- [ ] 2.4 Wait for next natural 08:00 UTC fire and verify issue creation

## Phase 3: Preventive Measures (code changes)

- [ ] 3.1 Create `apps/web-platform/test/server/inngest/function-registry-count.test.ts` -- assert expected function count matches route.ts registration array
- [ ] 3.2 Update `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` -- add H9 hypothesis for confirmed root cause
- [ ] 3.3 Write compound learning at `knowledge-base/project/learnings/bug-fixes/` documenting diagnosis and fix
