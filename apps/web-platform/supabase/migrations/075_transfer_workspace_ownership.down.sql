-- 075_transfer_workspace_ownership.down.sql
-- Revert: drop transfer_workspace_ownership, restore
-- update_workspace_member_role to its mig 067 form (allows owner
-- promotions), and restore anonymise_organization_membership to its
-- mig 058 form (without role promotion fix).
--
-- NOTE: This does NOT revert data — any transfers that occurred remain.

DROP FUNCTION IF EXISTS public.transfer_workspace_ownership(uuid, uuid, text);

-- Restore update_workspace_member_role without the owner-promotion block.
-- Full body from mig 067.
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

-- Restore anonymise_organization_membership without role promotion.
CREATE OR REPLACE FUNCTION public.anonymise_organization_membership(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_org_rec record;
  v_orgs_deleted int := 0;
  v_remaining int;
BEGIN
  FOR v_org_rec IN
    SELECT o.id AS org_id
    FROM public.organizations o
    WHERE o.owner_user_id = p_user_id
  LOOP
    SELECT COUNT(*) INTO v_remaining
    FROM public.workspace_members m
    JOIN public.workspaces w ON w.id = m.workspace_id
    WHERE w.organization_id = v_org_rec.org_id;

    IF v_remaining = 0 THEN
      DELETE FROM public.workspaces WHERE organization_id = v_org_rec.org_id;
      DELETE FROM public.organizations WHERE id = v_org_rec.org_id;
      v_orgs_deleted := v_orgs_deleted + 1;
    ELSE
      UPDATE public.organizations o
         SET owner_user_id = (
           SELECT m.user_id
           FROM public.workspace_members m
           JOIN public.workspaces w ON w.id = m.workspace_id
           WHERE w.organization_id = o.id
             AND m.user_id != p_user_id
           ORDER BY m.created_at ASC
           LIMIT 1
         )
       WHERE o.id = v_org_rec.org_id;
    END IF;
  END LOOP;

  RETURN v_orgs_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_organization_membership(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_organization_membership(uuid)
  TO service_role;
