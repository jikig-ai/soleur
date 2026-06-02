-- 094_dedup_tables_retention.sql
--
-- Add the daily pg_cron retention sweeps that migrations 052 and 030 both
-- deferred "to a follow-up issue" but never landed. This is that follow-up.
--
-- Context (2026-06-02 prod Disk-IO recurrence remediation):
--   * public.processed_github_events (delivery_id dedup, written by
--     app/api/webhooks/github/route.ts) had 65,240 live rows, 0 deletes, and
--     was the #3 prod Disk-IO consumer (unbounded INSERT growth, ~150 rows/day
--     from CI webhook traffic). Migration 052 created it with the same
--     "prunable; sweep deferred" note as the Stripe sibling.
--   * public.processed_stripe_events (event_id dedup) is the same prunable
--     class — migration 030 explicitly said "A pg_cron-based sweep is tracked
--     separately (follow-up issue)". 1 live row today (<10 rows/day), but
--     unbounded. Folded in here so the same debt is closed once.
--
-- Replay windows (verified): both 90d.
--   * GitHub: app/api/webhooks/github/route.ts:347 — the DB dedup must cover
--     "GitHub's redelivery limit"; 90d is safely above GitHub's hours-scale
--     auto-retry horizon.
--   * Stripe: migration 030 comment — "rows older than Stripe's replay window
--     (90d) are prunable".
--
-- Column names (verified against the create migrations):
--   * processed_github_events.received_at  (migration 052:128; index
--     processed_github_events_received_at_idx already backs the DELETE)
--   * processed_stripe_events.processed_at (migration 030; index
--     idx_processed_stripe_events_processed_at already backs the DELETE)
--
-- Both sweeps run ONCE daily at 04:00 UTC. Two daily runs add ~6
-- cron.job_run_details writes/day total — negligible vs. the unbounded INSERT
-- growth they bound (a net Disk-IO win). NOT per-minute, so this does not
-- re-introduce the cron-plumbing churn that migration 038 removed.
--
-- Idempotent: cron.unschedule guard before cron.schedule, EXCEPTION WHEN
-- duplicate_object — copied verbatim from migration 076's workspace_activity_purge
-- (the closest daily-retention-cron precedent).
--
-- See: knowledge-base/project/plans/2026-06-02-fix-supabase-disk-io-recurrence-and-sentry-monitor-plan.md Phase 2

-- =====================================================================
-- 1. processed_github_events — daily 90-day retention sweep
-- =====================================================================

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'processed_github_events_retention') THEN
    PERFORM cron.unschedule('processed_github_events_retention');
  END IF;
  PERFORM cron.schedule(
    'processed_github_events_retention',
    '0 4 * * *',
    $$DELETE FROM public.processed_github_events WHERE received_at < now() - interval '90 days'$$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron_block$;

-- =====================================================================
-- 2. processed_stripe_events — daily 90-day retention sweep
-- =====================================================================

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'processed_stripe_events_retention') THEN
    PERFORM cron.unschedule('processed_stripe_events_retention');
  END IF;
  PERFORM cron.schedule(
    'processed_stripe_events_retention',
    '0 4 * * *',
    $$DELETE FROM public.processed_stripe_events WHERE processed_at < now() - interval '90 days'$$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron_block$;
