-- 062_workspace_member_removals_and_remove_rpc_update.down.sql
-- Reverts migration 062 in FK-cascade-safe order.
--
-- Includes a verbatim copy of remove_workspace_member's pre-change
-- body (058:267-326) so the down migration restores the function
-- definition that existed before 062 landed. This duplication is
-- load-bearing; AC1 includes a parity test that diffs this body
-- against 058's source.

-- 0. Non-empty table guard (data-integrity-guardian P2-1, PR #4294 review).
--    DROP TABLE silently destroys rows because the BEFORE-DELETE WORM
--    trigger is dropped first at step 3 below. For a rollback against
--    a table that has accumulated removal-event rows, the silent destroy
--    loses GDPR Art. 30(1)(g) audit lineage. Convert to a loud
--    fail-stop; operator must explicitly anonymise + truncate before
--    invoking the down migration.
DO $$
DECLARE v_count int;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'workspace_member_removals'
  ) THEN
    EXECUTE 'SELECT count(*) FROM public.workspace_member_removals' INTO v_count;
    IF v_count > 0 THEN
      RAISE EXCEPTION 'Refusing to drop public.workspace_member_removals: % audit rows present. Anonymise + truncate first, OR escalate to CLO.', v_count
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
END $$;

-- 1. Unschedule the retention sweep.
DO $$
BEGIN
  PERFORM cron.unschedule('workspace-member-removals-retention-sweep');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

-- 2. Restore remove_workspace_member to its 058:267-326 pre-change
--    body (DELETE without the workspace_member_removals INSERT).
CREATE OR REPLACE FUNCTION public.remove_workspace_member(
  p_workspace_id uuid,
  p_user_id      uuid
) RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_user_id uuid := auth.uid();
  v_is_owner       boolean;
  v_target_role    text;
  v_rows           int;
BEGIN
  IF v_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;

  -- Authorize: caller must be an owner of the target workspace.
  SELECT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = v_caller_user_id
      AND role         = 'owner'
  ) INTO v_is_owner;

  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'caller is not an owner of workspace %', p_workspace_id
      USING ERRCODE = '42501';
  END IF;

  -- AC-FLOW4: owner cannot remove themselves.
  IF v_caller_user_id = p_user_id THEN
    RAISE EXCEPTION 'owner cannot remove themselves; use account-delete to cascade-anonymise instead'
      USING ERRCODE = '22023';
  END IF;

  -- AC-FLOW4 part 2: cannot remove another owner role (preserve
  -- workspace-has-at-least-one-owner invariant). Member-only removal.
  SELECT role INTO v_target_role
  FROM public.workspace_members
  WHERE workspace_id = p_workspace_id AND user_id = p_user_id;

  IF v_target_role IS NULL THEN
    RETURN 0;  -- already not a member; idempotent
  END IF;

  IF v_target_role = 'owner' THEN
    RAISE EXCEPTION 'cannot remove another owner; only members can be removed'
      USING ERRCODE = '22023';
  END IF;

  DELETE FROM public.workspace_members
  WHERE workspace_id = p_workspace_id AND user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.remove_workspace_member(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.remove_workspace_member(uuid, uuid)
  TO authenticated;

-- 3. Drop triggers (no-op if already absent).
DROP TRIGGER IF EXISTS workspace_member_removals_no_update ON public.workspace_member_removals;
DROP TRIGGER IF EXISTS workspace_member_removals_no_delete ON public.workspace_member_removals;

-- 4. Drop trigger function.
DROP FUNCTION IF EXISTS public.workspace_member_removals_no_mutate();

-- 5. Drop anonymise RPC.
DROP FUNCTION IF EXISTS public.anonymise_workspace_member_removals(uuid);

-- 6. Drop policy + index + table.
DROP POLICY IF EXISTS removals_select_for_members ON public.workspace_member_removals;
DROP INDEX IF EXISTS public.workspace_member_removals_workspace_idx;
DROP TABLE IF EXISTS public.workspace_member_removals;
