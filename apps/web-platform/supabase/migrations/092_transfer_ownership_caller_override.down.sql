-- Down-migration for 092_transfer_ownership_caller_override.
-- Drops the 4-arg (caller-override) form of transfer_workspace_ownership and
-- restores the 075 3-arg, authenticated-granted form verbatim. Data is NOT
-- reverted — ownership transfers that already occurred (workspace_members
-- role swaps, organizations.owner_user_id, attestation + revocation rows)
-- remain in place; reverting them would destroy user-initiated state.
-- Provided for reversibility symmetry of the schema-level object only.
--
-- WARNING: restoring the 3-arg auth.uid()-only form re-introduces the #4765
-- defect — the service-role caller (createServiceClient) hits auth.uid() NULL
-- → 28000 → HTTP 500. This down migration exists for rollback symmetry, not
-- because the 075 shape is correct.

DROP FUNCTION IF EXISTS public.transfer_workspace_ownership(uuid, uuid, text, uuid);

CREATE OR REPLACE FUNCTION public.transfer_workspace_ownership(
  p_workspace_id       uuid,
  p_new_owner_user_id  uuid,
  p_attestation_text   text
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_user_id uuid := auth.uid();
  v_is_owner       boolean;
  v_target_role    text;
  v_attestation_id uuid;
  v_org_id         uuid;
BEGIN
  -- 1. Authenticate
  IF v_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;

  -- 2. Caller must be owner (FOR UPDATE prevents concurrent transfers
  -- from both reading the caller as owner under READ COMMITTED)
  SELECT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = v_caller_user_id
      AND role         = 'owner'
    FOR UPDATE
  ) INTO v_is_owner;

  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'caller is not an owner of workspace %', p_workspace_id
      USING ERRCODE = '42501';
  END IF;

  -- 3. Self-transfer guard (explicit RAISE, not silent no-op)
  IF v_caller_user_id = p_new_owner_user_id THEN
    RAISE EXCEPTION 'cannot transfer ownership to self'
      USING ERRCODE = '22023';
  END IF;

  -- 4. Target must be a member
  SELECT role INTO v_target_role
    FROM public.workspace_members
   WHERE workspace_id = p_workspace_id
     AND user_id      = p_new_owner_user_id;

  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'target user is not a member of workspace %', p_workspace_id
      USING ERRCODE = 'P0001';
  END IF;

  -- 5. Target already owner guard
  IF v_target_role = 'owner' THEN
    RAISE EXCEPTION 'target user is already the owner of workspace %', p_workspace_id
      USING ERRCODE = '22023';
  END IF;

  -- 6. Attestation text validation (matches invite_workspace_member)
  IF p_attestation_text IS NULL OR length(p_attestation_text) < 16 THEN
    RAISE EXCEPTION 'attestation_text must be at least 16 chars'
      USING ERRCODE = '22023';
  END IF;

  -- 7. Actor GUC for audit trigger (PA-20 accountability)
  PERFORM set_config('workspace_audit.actor_user_id', v_caller_user_id::text, true);

  -- 8. Fresh attestation row (CLO Art. 5(2) requirement)
  INSERT INTO public.workspace_member_attestations (
    workspace_id, inviter_user_id, invitee_user_id,
    attestation_text
  ) VALUES (
    p_workspace_id, v_caller_user_id, p_new_owner_user_id,
    p_attestation_text
  )
  RETURNING id INTO v_attestation_id;

  -- 9. Promote target to owner (FIRST)
  UPDATE public.workspace_members
     SET role = 'owner',
         attestation_id = v_attestation_id
   WHERE workspace_id = p_workspace_id
     AND user_id      = p_new_owner_user_id;

  -- 10. Demote caller to member (SECOND)
  UPDATE public.workspace_members
     SET role = 'member'
   WHERE workspace_id = p_workspace_id
     AND user_id      = v_caller_user_id;

  -- 11. Dual-write: update organizations.owner_user_id
  UPDATE public.organizations
     SET owner_user_id = p_new_owner_user_id
   WHERE id = (
     SELECT organization_id FROM public.workspaces
      WHERE id = p_workspace_id
   );

  -- 12. Revocation ledger row for demoted owner
  INSERT INTO public.workspace_member_removals (
    workspace_id, removed_user_id, removed_by_user_id,
    revoked_after, revocation_reason
  ) VALUES (
    p_workspace_id, v_caller_user_id, v_caller_user_id,
    now(), 'ownership-transferred'
  );

  -- 13. F6 session clear for demoted owner only.
  SELECT organization_id INTO v_org_id
    FROM public.workspaces WHERE id = p_workspace_id;

  IF v_org_id IS NOT NULL THEN
    UPDATE public.user_session_state uss
       SET current_organization_id = NULL
     WHERE uss.user_id = v_caller_user_id
       AND uss.current_organization_id = v_org_id;
  END IF;

  RETURN v_attestation_id;
END;
$$;

REVOKE ALL ON FUNCTION public.transfer_workspace_ownership(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.transfer_workspace_ownership(uuid, uuid, text)
  TO authenticated;

COMMENT ON FUNCTION public.transfer_workspace_ownership(uuid, uuid, text) IS
  'Atomic workspace ownership transfer. Single-owner strict: promotes '
  'target to owner, demotes caller to member, updates organizations.'
  'owner_user_id, writes attestation + revocation rows. #4520.';
