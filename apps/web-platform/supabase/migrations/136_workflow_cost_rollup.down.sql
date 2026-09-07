-- 136_workflow_cost_rollup.down.sql
-- Drops the new aggregate ONLY.
--
-- This deliberately does NOT restore `sum_user_mtd_cost` to its 027 shape. The
-- repin in the forward migration is body-identical -- only `search_path` changes
-- -- so there is nothing to roll back, and a "027-shaped restore" would silently
-- re-introduce the missing `pg_temp` that migration 136 exists to fix.
-- `loadForwardCorpus` excludes `.down.sql`, so nothing would have reddened.

DROP FUNCTION IF EXISTS public.sum_user_mtd_cost_by_workflow(UUID, TIMESTAMPTZ);
