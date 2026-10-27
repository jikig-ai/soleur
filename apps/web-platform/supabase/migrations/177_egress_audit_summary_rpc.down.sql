-- 177_egress_audit_summary_rpc.down.sql
-- Reverse 177: drop the member read RPC. No data is touched; the rollup table and
-- its ingest/purge/erase functions (migration 162) are unaffected.

DROP FUNCTION IF EXISTS public.get_egress_audit_summary(uuid, integer, text);
