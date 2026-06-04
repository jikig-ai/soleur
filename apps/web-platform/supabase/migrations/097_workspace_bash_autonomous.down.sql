-- 097_workspace_bash_autonomous.down.sql
-- Reverse 097: drop both RPCs and the column. Dropping the column resets all
-- toggle state (no autonomous workspace survives the rollback — the safe
-- direction for an approval-bypass flag).

DROP FUNCTION IF EXISTS public.set_workspace_bash_autonomous(uuid, boolean);
DROP FUNCTION IF EXISTS public.get_workspace_bash_autonomous(uuid);

ALTER TABLE public.workspaces
  DROP COLUMN IF EXISTS bash_autonomous;
