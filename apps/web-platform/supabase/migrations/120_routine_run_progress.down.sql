-- 120_routine_run_progress.down.sql
-- Reverts 120: drops the mutable live-state sidecar. The policy, index, and
-- REVOKE grants are all attached to the table and drop with it. No WORM trigger
-- / RPC / FK to unwind (attribution-free, non-WORM by design).

DROP TABLE IF EXISTS public.routine_run_progress CASCADE;
