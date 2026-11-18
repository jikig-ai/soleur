-- 188_workspace_kb_sync_pull_blocked.sql
-- #12714 (rulings D39, D42, D45(c) in knowledge-base/project/specs/feat-one-shot-12600-syncpush-owner-approval/
-- review-ext-rulings.md): why the self-heal cannot bring a workspace up to date from GitHub, for the cc agent line.
--
-- A NEW migration, not an amendment of 187: CI's tenant-integration run applied 187 to the shared dev project, and a
-- migration applied to dev is as immutable as a merged one (#8583, #8521; the dev-ledger parity gate pins 187's blob).
--
-- Adds one display-only column to workspaces, next to 187's two:
--   * kb_sync_pull_blocked    text NULL, 'merge_conflict_precheck' | 'untracked_collision' (named check). Why the
--                             self-heal cannot bring the workspace up to date (D42); NULL = not blocked or unknown.
-- and widens 187's member-checked read get_workspace_kb_sync_held to return it. RETURNS TABLE cannot change shape under
-- CREATE OR REPLACE (42P13), so the function is dropped and created again, with 187's SECURITY DEFINER, STABLE,
-- search_path, member check and grants, in this file's one transaction (callers never see it missing).
-- None of the three held columns is read by a gate, an approval or a push decision (a readers census test pins the
-- readers).
--
-- LAWFUL_BASIS: contract (Art. 6(1)(b)). Covers 187's kb_sync_held_files and kb_sync_held_checked_at and this file's
--   kb_sync_pull_blocked: a display-only aggregate of the workspace's own repository state (a file count, a timestamp
--   and a closed reason code), with no path, content or per-person identifier. Cleared on disconnect and reconnect,
--   dropped with the workspace row. No new purpose, category, recipient or sub-processor.
--
-- Grants. This file carries NO GRANT or REVOKE on workspaces, and that is deliberate:
--   * `authenticated` SELECT on workspaces is column-split (migration 174 re-issues the column list), so the new
--     column is NOT readable by `authenticated`. The cc agent line reads it through the member-checked RPC below.
--   * `anon` keeps the table-level SELECT that 174 grants it (pre-existing), so it covers this column too. RLS is the
--     anon barrier: the only workspaces policy (053 workspaces_select_for_members) is TO authenticated, so anon matches
--     no policy and reads zero rows. verify/187 asserts that no workspaces policy names anon or PUBLIC. Narrowing
--     anon's table grant is follow-up FU-6.
--   * the table-level INSERT/UPDATE that 174 grants `authenticated` remains; RLS (053: a SELECT-for-members policy
--     and no UPDATE policy) is the barrier for writes, as for every other workspaces column. The writers are the
--     service client (the self-heal and the sync paths, disconnect, setup).
--   * verify/188_workspace_kb_sync_pull_blocked.sql checks the live privileges (run by hand, like verify/187).
--
-- Deploy order (D29(2)): this migration applies BEFORE the code that writes the column or reads the third RPC column.
-- Rollback is the code first, then 188_workspace_kb_sync_pull_blocked.down.sql (which restores 187's two-column RPC).
-- Re-applying is safe: the column add is IF NOT EXISTS and the function is DROP IF EXISTS, then CREATE.

-- The ALTER takes ACCESS EXCLUSIVE on workspaces, which nearly every request reads: fail fast instead of queueing every
-- reader behind a long-running transaction (migration 159 precedent).
SET LOCAL lock_timeout = '5s';

ALTER TABLE public.workspaces
  ADD COLUMN IF NOT EXISTS kb_sync_pull_blocked text
    CONSTRAINT workspaces_kb_sync_pull_blocked_values
    CHECK (kb_sync_pull_blocked IN ('merge_conflict_precheck', 'untracked_collision'));

COMMENT ON COLUMN public.workspaces.kb_sync_pull_blocked IS
  '#12714 (D42): why the self-heal cannot update this workspace from GitHub (merge_conflict_precheck or '
  'untracked_collision); NULL = not blocked or unknown. Workspace scope, display-only: read by the cc agent line '
  'through get_workspace_kb_sync_held, never by a gate.';

-- 187's columns, described as the code now writes them (D39(d)/(e)/(f)).
COMMENT ON COLUMN public.workspaces.kb_sync_held_files IS
  '#12714: number of non-KB files in this workspace (HEAD plus recovered kb-sync branches and rescued store tips) '
  'that are not on the repository main branch, clamped to 0..10000 (10000 = "10000 or more"); NULL = unknown. '
  'Workspace scope, display-only: never read by a gate, approval or push decision. Written by the service client; '
  'read by Settings (service client) and get_workspace_kb_sync_held (member-checked).';

COMMENT ON COLUMN public.workspaces.kb_sync_held_checked_at IS
  '#12714: when the remote tip that kb_sync_held_files was computed against was read for this workspace; the writer '
  'only moves it forward, and a disconnect or setup clear stamps it with a null count. Workspace scope, display-only. '
  'NULL = never computed (no agent line, nothing shown).';

-- READ for the cc agent line (D29(3), D42): member-checked, mirroring get_workspace_web_egress (158). A non-member or an
-- unauthenticated caller gets zero rows (is_workspace_member(NULL, ...) and (..., NULL) are FALSE), which the caller
-- reads as null: no line. LANGUAGE sql with qualified column names, so the OUT columns of RETURNS TABLE cannot
-- shadow the table's columns. Dropped first: 187 created it with two OUT columns, and RETURNS TABLE cannot change shape
-- under CREATE OR REPLACE.
DROP FUNCTION IF EXISTS public.get_workspace_kb_sync_held(uuid);

CREATE FUNCTION public.get_workspace_kb_sync_held(p_workspace_id uuid)
  RETURNS TABLE (kb_sync_held_files integer, kb_sync_held_checked_at timestamptz, kb_sync_pull_blocked text)
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  SELECT w.kb_sync_held_files, w.kb_sync_held_checked_at, w.kb_sync_pull_blocked
  FROM public.workspaces w
  WHERE w.id = p_workspace_id
    AND public.is_workspace_member(p_workspace_id, auth.uid());
$$;

REVOKE ALL ON FUNCTION public.get_workspace_kb_sync_held(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_workspace_kb_sync_held(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.get_workspace_kb_sync_held(uuid) IS
  '#12714: member-checked read of workspaces.kb_sync_held_files, kb_sync_held_checked_at and kb_sync_pull_blocked '
  'for the cc agent line. Zero rows for a non-member or an unauthenticated caller. Display-only.';
