-- 076 down: Revert identity binding from accept/decline workspace invitation RPCs.
-- Restores the original function bodies from migration 075 (without identity checks).

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

  IF EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = v_inv.workspace_id
      AND user_id = v_accepter
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_member');
  END IF;

  INSERT INTO public.workspace_member_attestations (
    workspace_id, inviter_user_id, invitee_user_id,
    attestation_text
  ) VALUES (
    v_inv.workspace_id, v_inv.inviter_user_id, v_accepter,
    'Invite accepted by user'
  ) RETURNING id INTO v_attestation_id;

  UPDATE public.workspace_invitations
  SET accepted_at = now(), attestation_id = v_attestation_id
  WHERE id = p_invitation_id;

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
