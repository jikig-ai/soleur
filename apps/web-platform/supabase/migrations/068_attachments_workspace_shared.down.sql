-- 068_attachments_workspace_shared.down.sql
-- Reverses 068_attachments_workspace_shared.sql.
-- Drops the four new policies + helper + two cascade RPCs, then restores
-- the mig 045 single FOR ALL policy and the mig 067 remove_workspace_member
-- body verbatim. Idempotent (DROP ... IF EXISTS; CREATE OR REPLACE).
--
-- Down-only invariant: the restored remove_workspace_member body's
-- executable SQL (whitespace-normalised, comment-stripped) matches
-- mig 067:117-206. Drift would silently invert AC-FLOW4 guards on
-- rollback. The migration-shape lint asserts this equivalence.
--
-- Transaction wrapping: this body has NO top-level BEGIN/COMMIT — see
-- the matching note in the up-migration. Recovery semantics: a partial
-- failure of the down-apply (e.g., DROP FUNCTION fails because a sibling
-- depends on it) rolls back via psql --single-transaction. Note that
-- rolling back to mig 045's FOR ALL USING policy re-collapses reads
-- AND writes under one policy (per security-issues/2026-04-18-rls-for-
-- all-using-applies-to-writes.md). This is the pre-mig-068 baseline
-- semantics and is the correct rollback target.

-- 1. Drop the four new storage.objects policies and restore mig 045 FOR ALL.
DROP POLICY IF EXISTS "Users read own + co-member attachment objects" ON storage.objects;
DROP POLICY IF EXISTS "Users write own attachment objects only (insert)" ON storage.objects;
DROP POLICY IF EXISTS "Users write own attachment objects only (update)" ON storage.objects;
DROP POLICY IF EXISTS "Users write own attachment objects only (delete)" ON storage.objects;

CREATE POLICY "Users can write own attachment objects"
  ON storage.objects FOR ALL
  USING (
    bucket_id = 'chat-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- 2. Restore mig 067 remove_workspace_member body verbatim. The DROP-then-
--    re-CREATE pattern is unnecessary (CREATE OR REPLACE handles the body
--    swap) but matches mig 067's idempotent shape. The body below is
--    BYTE-EQUAL to apps/web-platform/supabase/migrations/067_workspace_
--    member_revocation_lookup.sql lines 117-206.
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
  v_org_id         uuid;
  v_rows           int;
BEGIN
  IF v_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;

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

  IF v_caller_user_id = p_user_id THEN
    RAISE EXCEPTION 'owner cannot remove themselves; use account-delete to cascade-anonymise instead'
      USING ERRCODE = '22023';
  END IF;

  SELECT role INTO v_target_role
  FROM public.workspace_members
  WHERE workspace_id = p_workspace_id AND user_id = p_user_id;

  IF v_target_role IS NULL THEN
    RETURN 0;
  END IF;

  IF v_target_role = 'owner' THEN
    RAISE EXCEPTION 'cannot remove another owner; only members can be removed'
      USING ERRCODE = '22023';
  END IF;

  SELECT organization_id INTO v_org_id
    FROM public.workspaces WHERE id = p_workspace_id;

  INSERT INTO public.workspace_member_removals (
    workspace_id, removed_user_id, removed_by_user_id,
    revoked_after, revocation_reason
  ) VALUES (
    p_workspace_id, p_user_id, v_caller_user_id,
    now(), 'removed'
  );

  DELETE FROM public.workspace_members
  WHERE workspace_id = p_workspace_id AND user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_org_id IS NOT NULL THEN
    UPDATE public.user_session_state uss
       SET current_organization_id = NULL
     WHERE uss.user_id = p_user_id
       AND uss.current_organization_id = v_org_id
       AND NOT EXISTS (
         SELECT 1 FROM public.workspace_members m
         JOIN public.workspaces w ON w.id = m.workspace_id
         WHERE m.user_id = p_user_id AND w.organization_id = v_org_id
       );
  END IF;

  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.remove_workspace_member(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.remove_workspace_member(uuid, uuid)
  TO authenticated;

-- 3. Drop the two cascade RPCs + internal helper + attachment-path helper.
--    Order: public RPC first (depends on internal), then internal, then helper.
DROP FUNCTION IF EXISTS public.anonymise_departed_user_across_workspaces(uuid);
DROP FUNCTION IF EXISTS public._anonymise_authored_messages_internal(uuid, uuid);
DROP FUNCTION IF EXISTS public.is_attachment_path_workspace_member(uuid, uuid);
