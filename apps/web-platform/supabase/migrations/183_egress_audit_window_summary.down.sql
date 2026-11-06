-- 183_egress_audit_window_summary.down.sql
-- Reverse 183: drop the windowed member read RPC only. No data is touched; migration 177's
-- get_egress_audit_summary and the rollup table are unaffected. Roll the app back first: an
-- app image that calls this function faults (PGRST202) once it is gone.

DROP FUNCTION IF EXISTS public.get_egress_audit_window_summary(uuid, integer, text, text);
