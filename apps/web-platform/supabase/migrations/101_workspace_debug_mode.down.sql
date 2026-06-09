-- 101_workspace_debug_mode.down.sql
-- Reverse 101: drop both RPCs and the column. Dropping the column resets all
-- toggle state (no debug-mode workspace survives the rollback — the safe
-- direction for an internal harness-stream flag).

DROP FUNCTION IF EXISTS public.set_workspace_debug_mode(uuid, boolean);
DROP FUNCTION IF EXISTS public.get_workspace_debug_mode(uuid);

ALTER TABLE public.workspaces
  DROP COLUMN IF EXISTS debug_mode;
