-- 115_prune_cron_job_run_details.sql
--
-- Cut the residual prod WAL from pg_cron's cron.job_run_details (issue #5738).
--
-- Why (2026-06-30 Supabase Disk-IO-budget investigation, see
--   knowledge-base/project/learnings/2026-06-30-supabase-disk-io-budget-diagnosis-and-management-api-config.md):
--   On prod soleur-web-platform (Micro, 1 GB RAM) the 46 MB DB is 100% cached,
--   so Disk-IO is write-dominated (~12 GB/day WAL). The #1 source (63%,
--   GitHub-webhook dedup) shipped in PR #5736 (merged). This migration targets a
--   residual: INSERT INTO cron.job_run_details = ~4.7% of WAL. pg_cron logs one
--   row per scheduled run and NEVER auto-prunes, so two facts shape the fix:
--     1. The WAL is the INSERTs, not the table size — a retention prune bounds the
--        (unbounded-since-inception) table but does NOT reduce per-INSERT WAL. The
--        lever that measurably cuts WAL going forward is FEWER runs.
--     2. The run population is dominated by one job: user_concurrency_slots_sweep
--        at */15 (96 runs/day ≈ 75% of all cron runs). Throttling it to hourly
--        (96 → 24 runs/day) is the single biggest WAL lever for this table.
--   Net: total cron runs ~128/day → ~56/day (~56% fewer job_run_details INSERTs),
--   and the table stops growing forever.
--
-- Statement 1 — Throttle user_concurrency_slots_sweep */15 → hourly (0 * * * *).
--   The slots DELETE body + 120 s freshness threshold are UNCHANGED from migration
--   038 (only the cadence changes). Throttle safety (verified, R1):
--     * The acquire path self-reaps: acquire_concurrency_slot RPC
--       (093_acquire_slot_workspace_id.sql:79-81) deletes the caller's own stale
--       slots inline (last_heartbeat_at < now()-120s) BEFORE the per-user count, so
--       sweep cadence cannot gate slot acquisition (093:77 calls cron a backup).
--     * The only un-freshness-filtered slot consumer — the cap-drift self-evict
--       count at ws-handler.ts:768 — is fixed in the same PR (#5738) by adding
--       .gte("last_heartbeat_at", liveCutoff), mirroring its two siblings
--       (:526 divergence, :2013 sibling-slot). Without that, slower reaping would
--       widen a false-eviction window ~4x; with it, the throttle is user-safe.
--   Hourly vs */15 also issues ~75% fewer DELETEs against user_concurrency_slots
--   (a second, smaller WAL saving).
--
-- Statement 2 — Add a daily retention prune (0 4 * * *) of cron.job_run_details
--   older than 7 days. Uses COALESCE(end_time, start_time) because in-flight rows
--   have end_time = NULL; a bare `end_time <` predicate would never reap
--   crash-orphaned NULL-end_time rows. 7-day floor preserves the ≥7-day cron
--   observability AC for incident triage — do NOT lower below 7 days.
--   The prune's own DELETE is WAL-logged, so the prune is a disk/cache-pressure
--   play, not a WAL play — Statement 1 is the WAL lever. The first daily run drains
--   the unbounded backlog (~28k rows on dev, ~97% older than 7d, live-probed
--   2026-06-30) IN ISOLATION — NOT coupled to this migration's transaction, so a
--   slow first drain cannot roll back the throttle. No one-time purge here (it would
--   be a non-sargable seq scan under --single-transaction); see plan §2.
--
-- Atomicity: run-migrations.sh runs each file under `psql --single-transaction`,
-- so both reschedules commit/rollback as one unit. `EXCEPTION WHEN duplicate_object`
-- is belt-and-suspenders on top of the cron.unschedule guard.
--
-- Idempotent: cron.unschedule guard before cron.schedule, EXCEPTION WHEN
-- duplicate_object — same shape as 103 (closest precedent: github_events
-- retention), and 094/076/102. Like 103, omits 102's `WHEN undefined_table` guard
-- because the apply target (web-platform-release.yml#migrate → run-migrations.sh)
-- always has pg_cron.
--
-- See: knowledge-base/project/plans/2026-06-30-perf-prune-throttle-cron-job-run-details-plan.md
-- Issue: #5738

-- =====================================================================
-- 1. Throttle the slots sweep */15 → hourly (body unchanged from 038)
-- =====================================================================

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'user_concurrency_slots_sweep') THEN
    PERFORM cron.unschedule('user_concurrency_slots_sweep');
  END IF;
  PERFORM cron.schedule(
    'user_concurrency_slots_sweep',
    '0 * * * *',  -- was */15 (mig 038); hourly. 120 s freshness threshold unchanged.
    $sweep$delete from public.user_concurrency_slots where last_heartbeat_at < now() - interval '120 seconds';$sweep$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron_block$;

-- =====================================================================
-- 2. Add the daily retention prune (NEW job; drains backlog in isolation)
-- =====================================================================

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cron_job_run_details_retention') THEN
    PERFORM cron.unschedule('cron_job_run_details_retention');
  END IF;
  PERFORM cron.schedule(
    'cron_job_run_details_retention',
    '0 4 * * *',
    $$DELETE FROM cron.job_run_details WHERE COALESCE(end_time, start_time) < now() - interval '7 days'$$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron_block$;
