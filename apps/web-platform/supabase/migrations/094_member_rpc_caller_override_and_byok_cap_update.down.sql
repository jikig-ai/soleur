-- Down-migration for 094_member_rpc_caller_override_and_byok_cap_update.
--
-- Drops the 3-arg/4-arg caller-override member overloads + the new
-- update_byok_delegation_cap RPC, and restores the mig-068 2-arg
-- remove_workspace_member + mig-067 3-arg update_workspace_member_role forms
-- verbatim. Data is NOT reverted (cap updates / removals that already occurred
-- remain). Provided for schema-object reversibility symmetry only.
--
-- WARNING: restoring the bare auth.uid() member RPCs re-introduces the
-- service-role 500 (#4779-followup / #4765 defect class) — the service-role
-- caller hits auth.uid() NULL → 28000 → HTTP 500.

DROP FUNCTION IF EXISTS public.update_byok_delegation_cap(uuid, int, int, uuid);
DROP FUNCTION IF EXISTS public.remove_workspace_member(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS public.update_workspace_member_role(uuid, uuid, text, uuid);

-- Restore mig-068 2-arg remove_workspace_member (bare auth.uid()).
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
  v_anon_count     int;
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

  v_anon_count := public._anonymise_authored_messages_internal(p_user_id, p_workspace_id);

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

-- Restore mig-067 3-arg update_workspace_member_role (bare auth.uid()).
CREATE OR REPLACE FUNCTION public.update_workspace_member_role(
  p_workspace_id uuid,
  p_user_id      uuid,
  p_new_role     text
) RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_user_id uuid := auth.uid();
  v_org_id         uuid;
BEGIN
  IF v_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = v_caller_user_id
      AND role         = 'owner'
  ) THEN
    RAISE EXCEPTION 'caller is not an owner of workspace %', p_workspace_id
      USING ERRCODE = '42501';
  END IF;

  IF p_new_role NOT IN ('owner', 'member') THEN
    RAISE EXCEPTION 'invalid role; must be owner or member'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_caller_user_id = p_user_id THEN
    RAISE EXCEPTION 'owner cannot change their own role; transfer ownership via add+remove flow'
      USING ERRCODE = '22023';
  END IF;
  IF p_new_role = 'member' AND (
    SELECT count(*) FROM public.workspace_members
     WHERE workspace_id = p_workspace_id AND role = 'owner'
  ) <= 1 THEN
    RAISE EXCEPTION 'cannot demote the last owner of workspace %', p_workspace_id
      USING ERRCODE = '22023';
  END IF;

  PERFORM set_config('workspace_audit.actor_user_id', v_caller_user_id::text, true);

  UPDATE public.workspace_members
     SET role = p_new_role
   WHERE workspace_id = p_workspace_id
     AND user_id      = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no workspace_members row for (workspace_id=%, user_id=%)',
      p_workspace_id, p_user_id
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.workspace_member_removals (
    workspace_id, removed_user_id, removed_by_user_id,
    revoked_after, revocation_reason
  ) VALUES (
    p_workspace_id, p_user_id, v_caller_user_id,
    now(), 'role-changed'
  );

  SELECT organization_id INTO v_org_id
    FROM public.workspaces WHERE id = p_workspace_id;

  IF v_org_id IS NOT NULL THEN
    UPDATE public.user_session_state uss
       SET current_organization_id = NULL
     WHERE uss.user_id = p_user_id
       AND uss.current_organization_id = v_org_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_workspace_member_role(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_workspace_member_role(uuid, uuid, text)
  TO authenticated;
