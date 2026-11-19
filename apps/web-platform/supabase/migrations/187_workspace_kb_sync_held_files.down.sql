-- 187_workspace_kb_sync_held_files.down.sql
-- Reverse 187. Revert the code first: the session-sync held-files write, the Settings select, the disconnect and
-- setup routes and the cc agent line all name these columns or the RPC, so dropping them under live code breaks
-- those reads and writes (D29(2): rollback is the code first, then this file).
--
-- Dropping the columns drops the named range check with them. The values are display-only and recomputed at every
-- sync, so nothing needs to be preserved.

DROP FUNCTION IF EXISTS public.get_workspace_kb_sync_held(uuid);

ALTER TABLE public.workspaces
  DROP COLUMN IF EXISTS kb_sync_held_checked_at;

ALTER TABLE public.workspaces
  DROP COLUMN IF EXISTS kb_sync_held_files;
