-- 187_workspace_kb_sync_held_files.sql
-- #12714 (rulings W1, W2, D29(1)/(3)/(10) in
-- knowledge-base/project/specs/feat-one-shot-12600-syncpush-owner-approval/decision-challenges.md):
-- Owners and members see how many code files the KB-only sync holds back from the repository's main branch.
--
-- Adds two display-only columns to workspaces:
--   * kb_sync_held_files     integer NULL, 0..10000 (named check). The count of non-KB files on HEAD and on any
--                            recovered kb-sync branch that are not on the remote default branch, computed token-free
--                            at the end of every syncPull / syncPush. NULL = unknown (no merge base, a git failure,
--                            or never computed): nothing is shown. 0: nothing is shown.
--   * kb_sync_held_checked_at timestamptz NULL. When that count was computed (the agent line's "as of" time).
-- Neither is read by a gate, an approval or a push decision (a readers census test pins the readers).
--
-- Grants. This file carries NO GRANT or REVOKE on workspaces, and that is deliberate:
--   * `authenticated` SELECT on workspaces is column-split (migration 174 re-issues the column list), so the two new
--     columns are NOT readable by `authenticated`. Settings reads them through the service client; the cc agent line
--     reads them through the member-checked RPC below.
--   * the table-level INSERT/UPDATE that 174 grants `authenticated` remains; RLS (053: a SELECT-for-members policy
--     and no UPDATE policy) is the barrier for writes, as for every other workspaces column. The writers are the
--     service client (session-sync, disconnect, setup).
--   * verify/187_workspace_kb_sync_held_files.sql checks the live privileges (run by hand, like verify/186).
--
-- Deploy order (D29(2)): this migration applies BEFORE the code that writes the columns. Rollback is the code first,
-- then 187_workspace_kb_sync_held_files.down.sql.

ALTER TABLE public.workspaces
  ADD COLUMN IF NOT EXISTS kb_sync_held_files integer
    CONSTRAINT workspaces_kb_sync_held_files_range
    CHECK (kb_sync_held_files >= 0 AND kb_sync_held_files <= 10000);

ALTER TABLE public.workspaces
  ADD COLUMN IF NOT EXISTS kb_sync_held_checked_at timestamptz;

COMMENT ON COLUMN public.workspaces.kb_sync_held_files IS
  '#12714: number of non-KB files in this workspace (HEAD plus recovered kb-sync branches) that are not on the '
  'repository main branch, clamped to 0..10000; NULL = unknown. Workspace scope, display-only: never read by a '
  'gate, approval or push decision. Written by the service client at every sync; read by Settings (service '
  'client) and get_workspace_kb_sync_held (member-checked).';

COMMENT ON COLUMN public.workspaces.kb_sync_held_checked_at IS
  '#12714: when kb_sync_held_files was last computed for this workspace. Workspace scope, display-only. NULL = '
  'never computed (no agent line, nothing shown).';

-- READ for the cc agent line (D29(3)): member-checked, mirroring get_workspace_web_egress (158). A non-member or an
-- unauthenticated caller gets zero rows (is_workspace_member(NULL, ...) and (..., NULL) are FALSE), which the caller
-- reads as null: no line. LANGUAGE sql with qualified column names, so the OUT columns of RETURNS TABLE cannot
-- shadow the table's columns.
CREATE OR REPLACE FUNCTION public.get_workspace_kb_sync_held(p_workspace_id uuid)
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
