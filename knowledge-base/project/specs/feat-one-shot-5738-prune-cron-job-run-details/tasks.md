---
title: "Tasks: prune + throttle pg_cron cron.job_run_details"
issue: 5738
lane: single-domain
plan: knowledge-base/project/plans/2026-06-30-perf-prune-throttle-cron-job-run-details-plan.md
---

# Tasks — perf(db): prune + throttle `cron.job_run_details`

## Phase 0 — Preconditions (/work)

- [ ] 0.1 Live-probe (dev, Supabase MCP `execute_sql`): confirm
  `DELETE FROM cron.job_run_details WHERE COALESCE(end_time,start_time) < now() - interval '7 days'`
  runs without a permission error.
- [ ] 0.2 Confirm latest migration prefix is still `113` (else renumber to next free).
- [ ] 0.3 Re-read migration `038`'s slots-DELETE body to copy it byte-identically.
- [ ] 0.4 Precedent-diff: open `103_github_events_retention_7day.sql` as the shape template.

## Phase 1 — Forward migration

- [ ] 1.1 Create `apps/web-platform/supabase/migrations/114_prune_cron_job_run_details.sql`.
- [ ] 1.2 Statement A: idempotent reschedule of `user_concurrency_slots_sweep` to
  `0 * * * *` (DELETE body + `120 seconds` interval unchanged from 038).
- [ ] 1.3 Statement B: idempotent `cron.schedule('cron_job_run_details_retention',
  '0 4 * * *', $$DELETE FROM cron.job_run_details WHERE COALESCE(end_time,start_time) < now() - interval '7 days'$$)`.
- [ ] 1.4 Statement C: one-time purge with the same predicate.
- [ ] 1.5 Header comment: cite #5738, the investigation learning, 96→24 delta, R1
  safety rationale, 103 precedent, COALESCE rationale.

## Phase 2 — Down migration

- [ ] 2.1 Create `114_prune_cron_job_run_details.down.sql`: reschedule slots sweep
  back to `*/15 * * * *`; `cron.unschedule('cron_job_run_details_retention')` (guarded).

## Phase 3 — Verify

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green (no app code changed).
- [ ] 3.2 Apply on dev; assert idempotency (apply twice → one row each).
- [ ] 3.3 `SELECT jobname, schedule FROM cron.job ORDER BY jobname` → slots sweep
  `0 * * * *`, retention job present.
- [ ] 3.4 Prune correctness on dev: old rows gone, in-flight (NULL end_time, recent
  start_time) rows retained.

## Phase 4 — Ship

- [ ] 4.1 PR body uses `Ref #5738` (NOT `Closes` — verification is post-merge).
- [ ] 4.2 Post-merge: re-measure run-rate (~128→~56/day) via MCP; then `gh issue close 5738`.
