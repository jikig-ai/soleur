-- 187_workspace_kb_sync_held_files.sql
-- #12714 (rulings W1, W2, D29(1)/(3)/(10), D39, D42, D45(c) in
-- knowledge-base/project/specs/feat-one-shot-12600-syncpush-owner-approval/decision-challenges.md and review-ext-rulings.md):
-- Owners and members see how many code files the KB-only sync holds back from the repository's main branch.
--
-- Amended in place by D42: this migration had not been applied anywhere (PR #12704 draft, task 10.4 open), so the third
-- column joins it here instead of a new migration number.
--
-- Adds three display-only columns to workspaces:
--   * kb_sync_held_files      integer NULL, 0..10000 (named check). The count of non-KB files on HEAD and on any
--                             set-aside branch (recovered kb-sync branches and rescued store tips) that are not on the
--                             remote default branch, computed token-free. NULL = unknown (no merge base, a git failure,
--                             or never computed): nothing is shown. 0: nothing is shown. 10000 is a clamp and means
--                             "10000 or more" (D39(e)); the copy renders it as a lower bound.
--   * kb_sync_held_checked_at timestamptz NULL. The instant the sync read the remote tip the count was computed against
--                             (the agent line's "as of" time). The writer only moves it forward (D39(f)).
--   * kb_sync_pull_blocked    text NULL, 'merge_conflict_precheck' | 'untracked_collision' (named check). Why the
--                             self-heal cannot bring the workspace up to date (D42); NULL = not blocked or unknown.
-- None is read by a gate, an approval or a push decision (a readers census test pins the readers).
--
-- LAWFUL_BASIS: contract (Art. 6(1)(b)). A display-only aggregate of the workspace's own repository state (a file
--   count, a timestamp and a closed reason code), with no path, content or per-person identifier. Cleared on disconnect
--   and reconnect, dropped with the workspace row. No new purpose, category, recipient or sub-processor.
--
-- Grants. This file carries NO GRANT or REVOKE on workspaces, and that is deliberate:
--   * `authenticated` SELECT on workspaces is column-split (migration 174 re-issues the column list), so the new
--     columns are NOT readable by `authenticated`. Settings reads them through the service client; the cc agent line
--     reads them through the member-checked RPC below.
--   * `anon` keeps the table-level SELECT that 174 grants it (pre-existing), so it covers these columns too. RLS is the
--     anon barrier: the only workspaces policy (053 workspaces_select_for_members) is TO authenticated, so anon matches
--     no policy and reads zero rows. verify/187 asserts that no workspaces policy names anon or PUBLIC. Narrowing
--     anon's table grant is follow-up FU-6.
--   * the table-level INSERT/UPDATE that 174 grants `authenticated` remains; RLS (053: a SELECT-for-members policy
--     and no UPDATE policy) is the barrier for writes, as for every other workspaces column. The writers are the
--     service client (the held-count path, disconnect, setup).
--   * verify/187_workspace_kb_sync_held_files.sql checks the live privileges (run by hand, like verify/186).
--
-- Deploy order (D29(2)): this migration applies BEFORE the code that writes the columns. Rollback is the code first,
-- then 187_workspace_kb_sync_held_files.down.sql. Every statement is idempotent, so a failed apply (the lock timeout
-- below) is retried as is.

-- The ALTERs take ACCESS EXCLUSIVE on workspaces, which nearly every request reads: fail fast instead of queueing
-- every reader behind a long-running transaction (migration 159 precedent).
SET LOCAL lock_timeout = '5s';

ALTER TABLE public.workspaces
  ADD COLUMN IF NOT EXISTS kb_sync_held_files integer
    CONSTRAINT workspaces_kb_sync_held_files_range
    CHECK (kb_sync_held_files >= 0 AND kb_sync_held_files <= 10000);

ALTER TABLE public.workspaces
  ADD COLUMN IF NOT EXISTS kb_sync_held_checked_at timestamptz;

ALTER TABLE public.workspaces
  ADD COLUMN IF NOT EXISTS kb_sync_pull_blocked text
    CONSTRAINT workspaces_kb_sync_pull_blocked_values
    CHECK (kb_sync_pull_blocked IN ('merge_conflict_precheck', 'untracked_collision'));

COMMENT ON COLUMN public.workspaces.kb_sync_held_files IS
  '#12714: number of non-KB files in this workspace (HEAD plus recovered kb-sync branches and rescued store tips) '
  'that are not on the repository main branch, clamped to 0..10000 (10000 = "10000 or more"); NULL = unknown. '
  'Workspace scope, display-only: never read by a gate, approval or push decision. Written by the service client; '
  'read by Settings (service client) and get_workspace_kb_sync_held (member-checked).';

COMMENT ON COLUMN public.workspaces.kb_sync_held_checked_at IS
  '#12714: when the remote tip that kb_sync_held_files was computed against was read for this workspace; the writer '
  'only moves it forward. Workspace scope, display-only. NULL = never computed (no agent line, nothing shown).';

COMMENT ON COLUMN public.workspaces.kb_sync_pull_blocked IS
  '#12714 (D42): why the self-heal cannot update this workspace from GitHub (merge_conflict_precheck or '
  'untracked_collision); NULL = not blocked or unknown. Workspace scope, display-only: read by the cc agent line '
  'through get_workspace_kb_sync_held, never by a gate.';

-- READ for the cc agent line (D29(3), D42): member-checked, mirroring get_workspace_web_egress (158). A non-member or an
-- unauthenticated caller gets zero rows (is_workspace_member(NULL, ...) and (..., NULL) are FALSE), which the caller
-- reads as null: no line. LANGUAGE sql with qualified column names, so the OUT columns of RETURNS TABLE cannot
-- shadow the table's columns.
CREATE OR REPLACE FUNCTION public.get_workspace_kb_sync_held(p_workspace_id uuid)
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
