-- 124_prune_auth_flow_state.down.sql
--
-- Reverse 124: remove the auth.flow_state retention cron.
--   1. Unschedule auth_flow_state_retention (guarded by IF EXISTS).
--
-- Not restorable: the rows deleted by the up migration's one-time backlog purge
-- (Statement 2) and by every scheduled run are IRREVERSIBLE BY DESIGN — they were
-- expired/abandoned flow_state rows (auth code never issued or long past the ~10-min
-- exchange floor), so they are not restorable and safe not to restore. A down
-- migration only tears down the scheduling mechanism, not the data hygiene it
-- performed.
--
-- Idempotent + atomic, same guard shape as the up migration.
-- See: 124_prune_auth_flow_state.sql · Issue: #5739

-- =====================================================================
-- 1. Remove the retention prune job
-- =====================================================================

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'auth_flow_state_retention') THEN
    PERFORM cron.unschedule('auth_flow_state_retention');
  END IF;
END $cron_block$;
