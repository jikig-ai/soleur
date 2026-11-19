-- 188_workspace_kb_sync_pull_blocked.down.sql
-- Reverse 188: back to 187's state. Revert the code first: the self-heal's pull-blocked write, the disconnect and setup
-- clears and the cc agent line name the column or the RPC's third column, so dropping them under live code breaks those
-- reads and writes (D29(2): rollback is the code first, then this file).
--
-- The RPC goes back to 187's two-column shape (DROP, then CREATE: RETURNS TABLE cannot change shape under CREATE OR
-- REPLACE) with 187's grants, before the column it reads is dropped. Dropping the column drops its named check with it.
-- The value is display-only and rewritten at every self-heal, so nothing needs to be preserved.

SET LOCAL lock_timeout = '5s';

DROP FUNCTION IF EXISTS public.get_workspace_kb_sync_held(uuid);

CREATE FUNCTION public.get_workspace_kb_sync_held(p_workspace_id uuid)
  RETURNS TABLE (kb_sync_held_files integer, kb_sync_held_checked_at timestamptz)
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  SELECT w.kb_sync_held_files, w.kb_sync_held_checked_at
  FROM public.workspaces w
  WHERE w.id = p_workspace_id
    AND public.is_workspace_member(p_workspace_id, auth.uid());
$$;

REVOKE ALL ON FUNCTION public.get_workspace_kb_sync_held(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_workspace_kb_sync_held(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.get_workspace_kb_sync_held(uuid) IS
  '#12714: member-checked read of workspaces.kb_sync_held_files and kb_sync_held_checked_at for the cc agent '
  'line. Zero rows for a non-member or an unauthenticated caller. Display-only.';

ALTER TABLE public.workspaces
  DROP COLUMN IF EXISTS kb_sync_pull_blocked;

COMMENT ON COLUMN public.workspaces.kb_sync_held_files IS
  '#12714: number of non-KB files in this workspace (HEAD plus recovered kb-sync branches) that are not on the '
  'repository main branch, clamped to 0..10000; NULL = unknown. Workspace scope, display-only: never read by a '
  'gate, approval or push decision. Written by the service client at every sync; read by Settings (service '
  'client) and get_workspace_kb_sync_held (member-checked).';

COMMENT ON COLUMN public.workspaces.kb_sync_held_checked_at IS
  '#12714: when kb_sync_held_files was last computed for this workspace. Workspace scope, display-only. NULL = '
  'never computed (no agent line, nothing shown).';
