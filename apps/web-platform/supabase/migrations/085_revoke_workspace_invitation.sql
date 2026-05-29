-- 085_revoke_workspace_invitation.sql
-- feat-cancel-pending-invite (#4634) — owner-side soft revoke of a pending
-- workspace invitation. Extends 075_workspace_invitations.
--
-- An owner can cancel a pending invite (wrong email / never accepted). Soft
-- revoke: revoked_at + revoked_by are set; the row is retained for audit,
-- mirroring accepted_at / declined_at. A revoked invite drops out of the
-- pending lists, its token can no longer be accepted, and the same email may
-- be re-invited (the duplicate-pending guard ignores revoked rows).
--
-- LAWFUL_BASIS: unchanged from 075 (Art. 6(1)(b)/(f)). revoked_by is a new PII
-- column (the acting owner) — nulled on the Art. 17 cascade alongside the
-- existing inviter/invitee columns.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every fn pins
-- SET search_path = public, pg_temp. WORM trigger extends 075's
-- negative-rejection idiom (NULL → NOT NULL permitted by fall-through;
-- re-mutation rejected) — NOT a positive allowlist.

-- =====================================================================
-- 1. Columns
-- =====================================================================

ALTER TABLE public.workspace_invitations
  ADD COLUMN IF NOT EXISTS revoked_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS revoked_by uuid NULL REFERENCES public.users(id) ON DELETE RESTRICT;

-- =====================================================================
-- 2. WORM trigger — re-issue 075 body + revoked_at / revoked_by arms
-- =====================================================================

CREATE OR REPLACE FUNCTION public.workspace_invitations_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'workspace_invitations is append-only; use anonymise_workspace_invitations for Art. 17 cascade'
      USING ERRCODE = 'P0001';
  END IF;

  -- Audit lineage columns are immutable.
  IF NEW.id              IS DISTINCT FROM OLD.id
    OR NEW.workspace_id  IS DISTINCT FROM OLD.workspace_id
    OR NEW.token_hash    IS DISTINCT FROM OLD.token_hash
    OR NEW.role          IS DISTINCT FROM OLD.role
    OR NEW.created_at    IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'workspace_invitations audit lineage is immutable'
      USING ERRCODE = 'P0001';
  END IF;

  -- accepted_at and declined_at: NULL → NOT NULL permitted (one-time set).
  IF OLD.accepted_at IS NOT NULL AND NEW.accepted_at IS DISTINCT FROM OLD.accepted_at THEN
    RAISE EXCEPTION 'workspace_invitations accepted_at is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;
  IF OLD.declined_at IS NOT NULL AND NEW.declined_at IS DISTINCT FROM OLD.declined_at THEN
    RAISE EXCEPTION 'workspace_invitations declined_at is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;

  -- revoked_at and revoked_by: NULL → NOT NULL permitted (one-time set on
  -- cancel). NOT NULL → NULL and value changes are rejected. revoked_by is a
  -- PII column; the Art. 17 NOT NULL → NULL transition is handled below in the
  -- PII block, NOT here, so an anonymise after revoke is not blocked.
  IF OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at THEN
    RAISE EXCEPTION 'workspace_invitations revoked_at is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;
  IF OLD.revoked_by IS NOT NULL AND NEW.revoked_by IS NOT NULL AND NEW.revoked_by IS DISTINCT FROM OLD.revoked_by THEN
    RAISE EXCEPTION 'workspace_invitations revoked_by is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;

  -- PII columns: only Art. 17 anonymise shape (NOT NULL → NULL) OR unchanged.
  -- revoked_by joins inviter/invitee here so the anonymise cascade can null it.
  IF (OLD.inviter_user_id IS NULL AND NEW.inviter_user_id IS NOT NULL)
    OR (OLD.inviter_user_id IS NOT NULL AND NEW.inviter_user_id IS NOT NULL AND NEW.inviter_user_id IS DISTINCT FROM OLD.inviter_user_id)
    OR (OLD.invitee_email IS NULL AND NEW.invitee_email IS NOT NULL)
    OR (OLD.invitee_email IS NOT NULL AND NEW.invitee_email IS NOT NULL AND NEW.invitee_email IS DISTINCT FROM OLD.invitee_email)
    OR (OLD.invitee_user_id IS NULL AND NEW.invitee_user_id IS NOT NULL)
    OR (OLD.invitee_user_id IS NOT NULL AND NEW.invitee_user_id IS NOT NULL AND NEW.invitee_user_id IS DISTINCT FROM OLD.invitee_user_id)
  THEN
    RAISE EXCEPTION 'workspace_invitations PII columns are immutable; only Art. 17 anonymise (NOT NULL → NULL) permitted'
      USING ERRCODE = 'P0001';
  END IF;

  -- expires_at: immutable.
  IF NEW.expires_at IS DISTINCT FROM OLD.expires_at THEN
    RAISE EXCEPTION 'workspace_invitations expires_at is immutable'
      USING ERRCODE = 'P0001';
  END IF;

  -- attestation_id: NULL → NOT NULL permitted (set on acceptance).
  IF OLD.attestation_id IS NOT NULL AND NEW.attestation_id IS DISTINCT FROM OLD.attestation_id THEN
    RAISE EXCEPTION 'workspace_invitations attestation_id is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.workspace_invitations_no_mutate() FROM PUBLIC, anon, authenticated, service_role;

-- Trigger objects are unchanged from 075 (CREATE OR REPLACE FUNCTION updates
-- the body in place; the BEFORE UPDATE/DELETE triggers still point at it).

-- =====================================================================
-- 3. revoke_workspace_invitation RPC (owner-side cancel)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.revoke_workspace_invitation(
  p_invitation_id   uuid,
  p_caller_user_id  uuid DEFAULT NULL
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid;
  v_inv RECORD;
BEGIN
  v_caller := COALESCE(p_caller_user_id, auth.uid());
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'caller_not_authenticated'
      USING ERRCODE = 'P0001';
  END IF;

  -- Lock and fetch the invitation.
  SELECT * INTO v_inv
  FROM public.workspace_invitations
  WHERE id = p_invitation_id
  FOR UPDATE;

  IF v_inv IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invitation_not_found');
  END IF;

  -- Caller must be owner of the invitation's workspace (defense-in-depth; the
  -- route also checks, but the RPC re-checks so a service-role call cannot
  -- bypass the boundary).
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = v_inv.workspace_id
      AND user_id = v_caller
      AND role = 'owner'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'caller_not_owner');
  END IF;

  IF v_inv.accepted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_accepted');
  END IF;

  IF v_inv.declined_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_declined');
  END IF;

  IF v_inv.revoked_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_revoked');
  END IF;

  UPDATE public.workspace_invitations
  SET revoked_at = now(), revoked_by = v_caller
  WHERE id = p_invitation_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_workspace_invitation(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_workspace_invitation(uuid, uuid) TO service_role;

-- =====================================================================
-- 4. lookup_invitation_by_token — reject revoked invites (FR4)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.lookup_invitation_by_token(p_token_hash text)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_inv RECORD;
  v_inviter_name text;
BEGIN
  SELECT wi.*, w.name AS workspace_name
  INTO v_inv
  FROM public.workspace_invitations wi
  JOIN public.workspaces w ON w.id = wi.workspace_id
  WHERE wi.token_hash = p_token_hash;

  IF v_inv IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
  END IF;

  IF v_inv.accepted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_accepted');
  END IF;

  IF v_inv.declined_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_declined');
  END IF;

  IF v_inv.revoked_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'revoked');
  END IF;

  IF v_inv.expires_at < now() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'expired');
  END IF;

  -- Resolve inviter display name.
  SELECT COALESCE(raw_user_meta_data->>'full_name', email)
  INTO v_inviter_name
  FROM auth.users
  WHERE id = v_inv.inviter_user_id;

  RETURN jsonb_build_object(
    'ok', true,
    'invitation_id', v_inv.id,
    'workspace_id', v_inv.workspace_id,
    'workspace_name', v_inv.workspace_name,
    'inviter_name', COALESCE(v_inviter_name, 'A team member'),
    'invitee_email', v_inv.invitee_email,
    'role', v_inv.role,
    'expires_at', v_inv.expires_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.lookup_invitation_by_token(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lookup_invitation_by_token(text) TO service_role;

-- =====================================================================
-- 5. create_workspace_invitation — revoked-aware duplicate guard (FR5)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.create_workspace_invitation(
  p_workspace_id    uuid,
  p_invitee_email   text,
  p_role            text,
  p_token_hash      text,
  p_attestation_text text,
  p_caller_user_id  uuid DEFAULT NULL
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid;
  v_invitee_user_id uuid;
  v_attestation_id uuid;
  v_invitation_id uuid;
BEGIN
  v_caller := COALESCE(p_caller_user_id, auth.uid());
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'caller_not_authenticated'
      USING ERRCODE = 'P0001';
  END IF;

  -- Caller must be owner of the workspace.
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id = v_caller
      AND role = 'owner'
  ) THEN
    RAISE EXCEPTION 'caller_not_owner'
      USING ERRCODE = 'P0001';
  END IF;

  -- Validate role.
  IF p_role NOT IN ('owner', 'member') THEN
    RAISE EXCEPTION 'invalid_role'
      USING ERRCODE = 'P0001';
  END IF;

  -- Resolve invitee user_id if they exist.
  SELECT id INTO v_invitee_user_id
  FROM public.users
  WHERE LOWER(email) = LOWER(p_invitee_email)
  LIMIT 1;

  -- Check invitee is not already a workspace member.
  IF v_invitee_user_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id = v_invitee_user_id
  ) THEN
    RAISE EXCEPTION 'invitee_already_member'
      USING ERRCODE = 'P0001';
  END IF;

  -- Check no pending invitation for same email + workspace. A revoked invite
  -- is not pending (revoked_at IS NULL), so the same email can be re-invited.
  IF EXISTS (
    SELECT 1 FROM public.workspace_invitations
    WHERE workspace_id = p_workspace_id
      AND LOWER(invitee_email) = LOWER(p_invitee_email)
      AND accepted_at IS NULL
      AND declined_at IS NULL
      AND revoked_at IS NULL
      AND expires_at > now()
  ) THEN
    RAISE EXCEPTION 'duplicate_pending_invite'
      USING ERRCODE = 'P0001';
  END IF;

  -- Create attestation row.
  INSERT INTO public.workspace_member_attestations (
    workspace_id, inviter_user_id, invitee_user_id, attestation_text
  ) VALUES (
    p_workspace_id, v_caller, v_invitee_user_id, p_attestation_text
  ) RETURNING id INTO v_attestation_id;

  -- Create invitation row.
  INSERT INTO public.workspace_invitations (
    workspace_id, inviter_user_id, invitee_email, invitee_user_id,
    token_hash, role, expires_at, attestation_id
  ) VALUES (
    p_workspace_id, v_caller, LOWER(p_invitee_email), v_invitee_user_id,
    p_token_hash, p_role, now() + interval '7 days', v_attestation_id
  ) RETURNING id INTO v_invitation_id;

  RETURN jsonb_build_object(
    'ok', true,
    'invitation_id', v_invitation_id,
    'attestation_id', v_attestation_id,
    'invitee_user_id', v_invitee_user_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_workspace_invitation(uuid, text, text, text, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_workspace_invitation(uuid, text, text, text, text, uuid) TO service_role;

-- =====================================================================
-- 6. anonymise_workspace_invitations — null revoked_by on Art. 17 cascade
-- =====================================================================

CREATE OR REPLACE FUNCTION public.anonymise_workspace_invitations(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.workspace_invitations
  SET inviter_user_id = NULL,
      invitee_user_id = NULL,
      invitee_email = NULL,
      revoked_by = NULL
  WHERE inviter_user_id = p_user_id
     OR invitee_user_id = p_user_id
     OR revoked_by = p_user_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_workspace_invitations(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_workspace_invitations(uuid) TO service_role;
