-- 075_transfer_workspace_ownership.sql
-- feat-workspace-role-management (#4520) — Atomic workspace ownership
-- transfer: promotes target to owner, demotes caller to member, updates
-- organizations.owner_user_id, writes fresh attestation row, and inserts
-- a workspace_member_removals revocation row — all in one SECURITY
-- DEFINER transaction.
--
-- Single-owner strict model: exactly one owner per workspace at all
-- times. The promote-before-demote ordering within the transaction
-- creates a transient two-owner state that is safe — no UNIQUE
-- constraint exists on (workspace_id, role='owner'). If a future
-- migration adds such a constraint, this RPC must be updated.
--
-- Also restricts update_workspace_member_role to block direct
-- promotions to owner (single-owner enforcement), and fixes
-- anonymise_organization_membership to promote the replacement
-- member's workspace_members.role alongside organizations.owner_user_id
-- (pre-existing desync from mig 058/065).
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every SECURITY
-- DEFINER function pins SET search_path = public, pg_temp.

-- =====================================================================
-- 1. transfer_workspace_ownership RPC
-- =====================================================================

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

  -- 2. Caller must be owner
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
  -- inviter_user_id = old owner (transferor)
  -- invitee_user_id = new owner (transferee)
  INSERT INTO public.workspace_member_attestations (
    workspace_id, inviter_user_id, invitee_user_id,
    attestation_text
  ) VALUES (
    p_workspace_id, v_caller_user_id, p_new_owner_user_id,
    p_attestation_text
  )
  RETURNING id INTO v_attestation_id;

  -- 9. Promote target to owner (FIRST — never violate at-least-one-owner
  -- invariant). Links attestation_id so the audit trigger captures the
  -- correct attestation in workspace_member_actions.attestation_id.
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
  -- The new owner gains privileges — no need to force re-auth.
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

-- =====================================================================
-- 2. Restrict update_workspace_member_role — block promotions to owner
-- =====================================================================
-- Full body carried forward from mig 067 with ONE addition:
-- IF p_new_role = 'owner' block after role validation.

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

  -- #4520: single-owner enforcement. Direct promotion to owner is
  -- blocked; use transfer_workspace_ownership for ownership changes.
  IF p_new_role = 'owner' THEN
    RAISE EXCEPTION 'direct promotion to owner is not allowed; use transfer_workspace_ownership'
      USING ERRCODE = '22023';
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

-- =====================================================================
-- 3. Fix anonymise_organization_membership — promote replacement
-- =====================================================================
-- Pre-existing desync from mig 058/065: reassigning owner_user_id
-- without promoting workspace_members.role leaves the workspace
-- administratively locked (every owner-gated RPC returns 42501).

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
  v_replacement_user_id uuid;
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
      -- Find the oldest remaining member (excluding the departing owner)
      SELECT m.user_id INTO v_replacement_user_id
        FROM public.workspace_members m
        JOIN public.workspaces w ON w.id = m.workspace_id
       WHERE w.organization_id = v_org_rec.org_id
         AND m.user_id != p_user_id
       ORDER BY m.created_at ASC
       LIMIT 1;

      -- Reassign org-level ownership
      UPDATE public.organizations o
         SET owner_user_id = v_replacement_user_id
       WHERE o.id = v_org_rec.org_id;

      -- #4520 fix: also promote the replacement member's
      -- workspace_members.role to 'owner' so owner-gated RPCs
      -- (invite, remove, update-role, transfer) continue working.
      IF v_replacement_user_id IS NOT NULL THEN
        UPDATE public.workspace_members m
           SET role = 'owner'
         WHERE m.user_id = v_replacement_user_id
           AND m.workspace_id IN (
             SELECT w.id FROM public.workspaces w
              WHERE w.organization_id = v_org_rec.org_id
           );
      END IF;
    END IF;
  END LOOP;

  RETURN v_orgs_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_organization_membership(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_organization_membership(uuid)
  TO service_role;
