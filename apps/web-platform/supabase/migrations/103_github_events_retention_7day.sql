-- 103_github_events_retention_7day.sql
--
-- Shorten the processed_github_events retention window from 90 days (set by
-- migration 094) to 7 days, and purge the already-stale rows once at deploy.
--
-- Why (2026-06-14 prod Disk-IO recurrence, issue #5225):
--   Migration 094 scheduled processed_github_events_retention (daily 0 4 * * *)
--   with a 90-day window, copied verbatim from the processed_stripe_events
--   sibling where 90d = Stripe's replay horizon. But processed_github_events is
--   a GitHub-webhook delivery dedup table whose replay need is hours-to-days,
--   NOT 90 days:
--     * GitHub deletes webhook delivery logs after 3 DAYS on github.com, so no
--       redelivery is possible past 3 days (the documented hard ceiling;
--       GitHub does not auto-redeliver — it is a manual/scripted action, itself
--       bounded by that 3-day log retention).
--     * A second independent layer — the Inngest 24h event.id dedup window
--       (app/api/webhooks/github/route.ts) — covers the first 24h regardless.
--     * releaseDedupRow (route.ts) DELETEs the row on a 5xx and the redelivery
--       re-INSERTs with received_at = now(), so a row's received_at always
--       reflects its most recent claim — a 7-day purge can never delete a row
--       inside an active redelivery cycle.
--   So the 90-day sweep ran successfully every night yet always reported
--   DELETE 0 (the table's oldest row never reached 90 days). The table bloated
--   toward a ~450k-row steady state (~5k inserts/day x 90d) and the resulting
--   INSERT + index write IO depleted the prod Disk-IO budget. The monitor
--   (migration 095) fired correctly at 123,416 rows on 2026-06-12 — the lever
--   it pointed at (the retention WINDOW) is the real defect, not a stopped cron.
--
--   7 days clears github.com's 3-day ceiling with >2x margin while keeping the
--   table small (~35k-row steady state, well under the monitor's 100k ceiling).
--   NEVER go below 3 days — that is the documented replay window and the
--   load-bearing double-processing lever (a webhook redelivered after its dedup
--   row was purged would be double-processed). github.com is the operative
--   bound here; GitHub Enterprise Server's horizon is 7 days (a future GHES
--   onboarding would need to revisit this — Soleur has no GHES code path today).
--
-- Atomicity: run-migrations.sh runs each file under `psql --single-transaction`,
-- so the cron re-schedule AND the one-time purge commit/rollback as one unit.
-- The `EXCEPTION WHEN duplicate_object` guard is belt-and-suspenders on top.
--
-- Idempotent: cron.unschedule guard before cron.schedule, EXCEPTION WHEN
-- duplicate_object — same shape as 094 (and 076's workspace_activity_purge).
--
-- See: knowledge-base/project/plans/2026-06-14-fix-supabase-disk-io-github-events-retention-window-plan.md

-- =====================================================================
-- 1. Re-schedule the daily sweep with a 7-day window (was 90d in 094)
-- =====================================================================

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'processed_github_events_retention') THEN
    PERFORM cron.unschedule('processed_github_events_retention');
  END IF;
  PERFORM cron.schedule(
    'processed_github_events_retention',
    '0 4 * * *',
    $$DELETE FROM public.processed_github_events WHERE received_at < now() - interval '7 days'$$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron_block$;

-- =====================================================================
-- 2. One-time purge so relief lands at deploy (not on the next 04:00 run)
-- =====================================================================
-- ~91k rows are already older than 7 days. Index-backed by
-- processed_github_events_received_at_idx (received_at DESC); a sub-second-to-
-- low-seconds index-range delete at this scale — no chunking, no CONCURRENTLY,
-- no VACUUM. ROW EXCLUSIVE on the table does not conflict with a concurrent
-- live webhook INSERT (different delivery_id PK).

DELETE FROM public.processed_github_events WHERE received_at < now() - interval '7 days';

-- =====================================================================
-- 3. Correct the stale retention comment that misled 094
-- =====================================================================
-- 052_multi_source_dedup.sql claimed retention was "Postgres autovacuum +
-- 30-day partition rotation (natural cleanup; no TTL daemon)" — factually
-- wrong (this table is NOT partitioned and has no autovacuum-driven TTL). That
-- stale claim is what led 094 to copy the Stripe 90-day window. Restate the
-- actual mechanism so the next retention change does not re-derive it wrongly.

COMMENT ON TABLE public.processed_github_events IS
  'Webhook delivery_id dedup for GitHub App webhook. PR-H (#3244). '
  'Mirror of processed_stripe_events (#2772). Service-role-only via '
  'createServiceClient(). Plain .insert() at webhook entry; catch '
  'PG_UNIQUE_VIOLATION (23505) -> 200 duplicate. On any 5xx after '
  'INSERT succeeds, DELETE the row (releaseDedupRow pattern) so the '
  'GitHub redelivery can re-process. Retention: daily pg_cron job '
  'processed_github_events_retention (0 4 * * *) deletes rows older '
  'than 7 days (migration 103; was 90d in 094). 7d clears github.com''s '
  '3-day webhook-delivery-log retention horizon with >2x margin. No '
  'partitioning, no TTL daemon.';
