-- 075_workspace_invitations.sql
-- feat-workspace-invite-acceptance (#4516, #4519) — token-based invite
-- acceptance flow with pending-invite lifecycle.
--
-- LAWFUL_BASIS: GDPR Art. 6(1)(b) contract performance for existing-user
-- invites; Art. 6(1)(f) legitimate interest for non-user invitees (the
-- inviter's interest in adding team members). PA-N of the Article 30
-- register tracks the "workspace invite email delivery" data category.
--
-- RETENTION: pending invites expire at expires_at (7d default). Accepted/
-- declined rows retained for audit trail; PII columns anonymised on
-- Art. 17 cascade via anonymise_workspace_invitations.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every fn pins
-- SET search_path = public, pg_temp.

-- =====================================================================
-- 1. workspace_invitations table
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.workspace_invitations (
  id                uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id      uuid         NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  -- PII columns — NULL after Art. 17 anonymise.
  inviter_user_id   uuid         NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  invitee_email     text         NULL,
  invitee_user_id   uuid         NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  -- Token — SHA-256 hash of the raw token sent via email.
  token_hash        text         NOT NULL,
  role              text         NOT NULL CHECK (role IN ('owner', 'member')),
  expires_at        timestamptz  NOT NULL,
  accepted_at       timestamptz  NULL,
  declined_at       timestamptz  NULL,
  attestation_id    uuid         NULL REFERENCES public.workspace_member_attestations(id) ON DELETE RESTRICT,
  created_at        timestamptz  NOT NULL DEFAULT now()
);

ALTER TABLE public.workspace_invitations ENABLE ROW LEVEL SECURITY;

-- Column-level posture: REVOKE table-level mutations from authenticated.
REVOKE UPDATE ON TABLE public.workspace_invitations FROM PUBLIC, anon, authenticated;
REVOKE DELETE ON TABLE public.workspace_invitations FROM PUBLIC, anon, authenticated;
REVOKE INSERT ON TABLE public.workspace_invitations FROM PUBLIC, anon, authenticated;

-- SELECT: invitee can see their own pending invitations.
CREATE POLICY invitations_select_for_invitee ON public.workspace_invitations
  FOR SELECT TO authenticated
  USING (
    invitee_user_id = auth.uid()
    OR invitee_email = (SELECT email FROM auth.users WHERE id = auth.uid())
  );

-- SELECT: workspace members can see invitations for their workspace.
CREATE POLICY invitations_select_for_members ON public.workspace_invitations
  FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspace_id, auth.uid()));

-- =====================================================================
-- 2. Indexes
-- =====================================================================

CREATE INDEX IF NOT EXISTS workspace_invitations_invitee_email_workspace_idx
  ON public.workspace_invitations (invitee_email, workspace_id)
  WHERE accepted_at IS NULL AND declined_at IS NULL;

CREATE INDEX IF NOT EXISTS workspace_invitations_invitee_user_id_idx
  ON public.workspace_invitations (invitee_user_id)
  WHERE accepted_at IS NULL AND declined_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS workspace_invitations_token_hash_idx
  ON public.workspace_invitations (token_hash);

-- =====================================================================
-- 3. WORM trigger (BEFORE UPDATE/DELETE)
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
  -- NOT NULL → NULL and value changes are rejected.
  IF OLD.accepted_at IS NOT NULL AND NEW.accepted_at IS DISTINCT FROM OLD.accepted_at THEN
    RAISE EXCEPTION 'workspace_invitations accepted_at is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;
  IF OLD.declined_at IS NOT NULL AND NEW.declined_at IS DISTINCT FROM OLD.declined_at THEN
    RAISE EXCEPTION 'workspace_invitations declined_at is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;

  -- PII columns: only Art. 17 anonymise shape (NOT NULL → NULL) OR unchanged.
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

DROP TRIGGER IF EXISTS workspace_invitations_no_update ON public.workspace_invitations;
CREATE TRIGGER workspace_invitations_no_update
  BEFORE UPDATE ON public.workspace_invitations
  FOR EACH ROW EXECUTE FUNCTION public.workspace_invitations_no_mutate();

DROP TRIGGER IF EXISTS workspace_invitations_no_delete ON public.workspace_invitations;
CREATE TRIGGER workspace_invitations_no_delete
  BEFORE DELETE ON public.workspace_invitations
  FOR EACH ROW EXECUTE FUNCTION public.workspace_invitations_no_mutate();

-- =====================================================================
-- 4. create_workspace_invitation RPC
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

  -- Check no pending invitation for same email + workspace.
  IF EXISTS (
    SELECT 1 FROM public.workspace_invitations
    WHERE workspace_id = p_workspace_id
      AND LOWER(invitee_email) = LOWER(p_invitee_email)
      AND accepted_at IS NULL
      AND declined_at IS NULL
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
-- 5. accept_workspace_invitation RPC
-- =====================================================================

CREATE OR REPLACE FUNCTION public.accept_workspace_invitation(
  p_invitation_id   uuid,
  p_accepter_user_id uuid DEFAULT NULL
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_accepter uuid;
  v_inv RECORD;
  v_attestation_id uuid;
BEGIN
  v_accepter := COALESCE(p_accepter_user_id, auth.uid());
  IF v_accepter IS NULL THEN
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

  IF v_inv.accepted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_accepted');
  END IF;

  IF v_inv.declined_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_declined');
  END IF;

  IF v_inv.expires_at < now() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'expired');
  END IF;

  -- Check accepter is not already a member.
  IF EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = v_inv.workspace_id
      AND user_id = v_accepter
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_member');
  END IF;

  -- Create acceptance attestation.
  INSERT INTO public.workspace_member_attestations (
    workspace_id, inviter_user_id, invitee_user_id,
    attestation_text
  ) VALUES (
    v_inv.workspace_id, v_inv.inviter_user_id, v_accepter,
    'Invite accepted by user'
  ) RETURNING id INTO v_attestation_id;

  -- Mark invitation as accepted.
  UPDATE public.workspace_invitations
  SET accepted_at = now(), attestation_id = v_attestation_id
  WHERE id = p_invitation_id;

  -- Create workspace_members row.
  INSERT INTO public.workspace_members (
    workspace_id, user_id, role, attestation_id
  ) VALUES (
    v_inv.workspace_id, v_accepter, v_inv.role, v_attestation_id
  );

  RETURN jsonb_build_object(
    'ok', true,
    'workspace_id', v_inv.workspace_id,
    'attestation_id', v_attestation_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.accept_workspace_invitation(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accept_workspace_invitation(uuid, uuid) TO service_role;

-- =====================================================================
-- 6. decline_workspace_invitation RPC
-- =====================================================================

CREATE OR REPLACE FUNCTION public.decline_workspace_invitation(
  p_invitation_id   uuid,
  p_decliner_user_id uuid DEFAULT NULL
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_decliner uuid;
  v_inv RECORD;
BEGIN
  v_decliner := COALESCE(p_decliner_user_id, auth.uid());

  SELECT * INTO v_inv
  FROM public.workspace_invitations
  WHERE id = p_invitation_id
  FOR UPDATE;

  IF v_inv IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invitation_not_found');
  END IF;

  IF v_inv.accepted_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_accepted');
  END IF;

  IF v_inv.declined_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_declined');
  END IF;

  UPDATE public.workspace_invitations
  SET declined_at = now()
  WHERE id = p_invitation_id;

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.decline_workspace_invitation(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.decline_workspace_invitation(uuid, uuid) TO service_role;

-- =====================================================================
-- 7. anonymise_workspace_invitations RPC (Art. 17)
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
      invitee_email = NULL,
      invitee_user_id = NULL
  WHERE inviter_user_id = p_user_id
     OR invitee_user_id = p_user_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_workspace_invitations(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_workspace_invitations(uuid) TO service_role;

-- =====================================================================
-- 8. lookup_invitation_by_token RPC (public-facing token validation)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.lookup_invitation_by_token(p_token_hash text)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_inv RECORD;
  v_workspace_name text;
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
