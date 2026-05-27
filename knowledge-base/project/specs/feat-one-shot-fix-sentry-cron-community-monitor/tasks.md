---
plan: ../../plans/2026-05-27-fix-sentry-cron-community-monitor-missed-checkin-plan.md
branch: feat-one-shot-fix-sentry-cron-community-monitor
lane: single-domain
---

# Tasks: fix Sentry cron monitor scheduled-community-monitor missed check-in

Derived from `2026-05-27-fix-sentry-cron-community-monitor-missed-checkin-plan.md`.

## Phase 1: Diagnose (operator-side)

- [ ] 1.1 Cross-cron health check: read `/var/lib/inngest/cron-fires/scheduled-daily-triage.json` + `scheduled-bug-fixer.json` + `scheduled-community-monitor.json` to determine if failure is community-monitor-specific or systemic
- [ ] 1.2 Query Inngest function registry: verify `cron-community-monitor` is registered with cron trigger and total count matches expected 40
- [ ] 1.3 Check Inngest server logs for OOM, restart, error, sync issues in the 2026-05-26 to 2026-05-27 window
- [ ] 1.4 Check Inngest run history for cron-community-monitor -- did it fire on May 26/27? What was the outcome? (Distinguishes Hypothesis A from E)
- [ ] 1.5 Verify Sentry heartbeat env vars (SENTRY_INGEST_DOMAIN, SENTRY_PROJECT_ID, SENTRY_PUBLIC_KEY) are present in Doppler prd and in the running container
- [ ] 1.6 Document confirmed root cause (Hypothesis A/B/C/D/E or new)

## Phase 2: Fix (based on diagnosis)

- [ ] 2.1 If Hypothesis A or E: restart `inngest-server.service` then restart web-platform container to force clean function sync + cron re-plan
- [ ] 2.2 If Hypothesis B: stagger community-monitor schedule from `0 8` to `30 8` in both `cron-community-monitor.ts` and `cron-monitors.tf`
- [ ] 2.3 If Hypothesis C: raise `MemoryMax` from `512M` to `768M` in `inngest-bootstrap.sh`
- [ ] 2.4 If Hypothesis D: verify + re-inject Sentry env vars in Doppler prd, restart container
- [ ] 2.5 Trigger manual community-monitor fire via Inngest event
- [ ] 2.6 Verify Sentry cron monitor shows successful check-in after manual trigger
- [ ] 2.7 Wait for next natural 08:00 UTC fire and verify issue creation

## Phase 3: Preventive Measures (code changes)

- [ ] 3.1 Create `apps/web-platform/test/server/inngest/function-registry-count.test.ts`:
  - [ ] 3.1.1 Assert function count in route.ts matches expected 40
  - [ ] 3.1.2 Assert every `cron-*.ts` file has a corresponding route.ts entry
  - [ ] 3.1.3 Assert every cron function's SENTRY_MONITOR_SLUG has a matching `cron-monitors.tf` resource
- [ ] 3.2 Update `knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md` -- add new hypothesis for confirmed root cause
- [ ] 3.3 Write compound learning at `knowledge-base/project/learnings/bug-fixes/` documenting timeline, diagnosis, and fix
