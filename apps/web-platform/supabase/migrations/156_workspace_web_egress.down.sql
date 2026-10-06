-- 156_workspace_web_egress.down.sql
-- Reverse 156: drop both RPCs and the column. Dropping the column resets all
-- grant state (no web-egress workspace survives the rollback — the safe
-- direction: it restores the default zero-egress posture for every
-- workspace).

DROP FUNCTION IF EXISTS public.set_workspace_web_egress(uuid, boolean);
DROP FUNCTION IF EXISTS public.get_workspace_web_egress(uuid);

ALTER TABLE public.workspaces
  DROP COLUMN IF EXISTS web_egress;
