-- 162_workspace_egress_audit_rollup.down.sql
-- Reverts 162: unschedule the retention job, drop the four functions, then the table.
DO $$
BEGIN
  PERFORM cron.unschedule('egress-audit-rollup-retention');
EXCEPTION WHEN OTHERS THEN
  NULL; -- job absent (never scheduled or already removed)
END $$;

DROP FUNCTION IF EXISTS public.erase_egress_audit_rollup_for_requester(uuid, uuid);
DROP FUNCTION IF EXISTS public.erase_egress_audit_rollup(uuid);
DROP FUNCTION IF EXISTS public.purge_egress_audit_rollup(interval, int);
DROP FUNCTION IF EXISTS public.ingest_egress_audit_rollup(jsonb);

DROP INDEX IF EXISTS public.workspace_egress_audit_rollup_last_seen_idx;
DROP TABLE IF EXISTS public.workspace_egress_audit_rollup;
