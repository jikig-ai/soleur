-- =====================================================================
-- 090_fix_accept_invitation_attestation_overwrite
--
-- ROOT CAUSE (confirmed against prod 2026-06-01, rolled-back repro):
--   accept_workspace_invitation always failed with P0001
--   "workspace_invitations attestation_id is immutable once set",
--   surfacing to the client as rpc_failed → "Something went wrong."
--
-- The defect is a self-contradiction introduced in 075:
--   * create_workspace_invitation (075) sets workspace_invitations.attestation_id
--     at CREATION time (the inviter's attestation) — so every invitation row
--     has a non-NULL attestation_id from creation.
--   * the workspace_invitations_no_mutate BEFORE UPDATE trigger (075:144-148)
--     forbids changing attestation_id once it is non-NULL.
--   * accept_workspace_invitation (075/085) did
--       UPDATE workspace_invitations SET accepted_at = now(),
--         attestation_id = v_attestation_id
--     re-pointing attestation_id at the NEW acceptance attestation, which the
--     trigger rejects. Result: NO invite could ever be accepted.
--
-- FIX: accept no longer overwrites workspace_invitations.attestation_id. The
-- invitation keeps its creation-time attestation (lineage); the freshly-created
-- acceptance attestation is linked only from the workspace_members row (which is
-- the membership-consent record). The trigger permits accepted_at NULL → NOT NULL
-- (075:117), so SET accepted_at = now() alone is allowed.
--
-- Re-issues the 085 accept body (revoked-aware arm preserved) with TWO changes:
--   1. drops the attestation_id reassignment (the P0001 root cause above);
--   2. restores the 076 not_intended_invitee identity-binding check, which 085
--      silently dropped when it re-issued the accept body without it (#4544
--      defense-in-depth — the RPC-level check guards against a direct service_role
--      caller bypassing the route's 403 gate).
-- CREATE OR REPLACE keeps the (uuid, uuid) signature so the change is rolling-deploy
-- safe (no DROP window for in-flight callers). Never edits the applied 085 migration
-- in place; forward migration only.
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

  IF v_inv.revoked_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'revoked');
  END IF;

  IF v_inv.expires_at < now() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'expired');
  END IF;

  -- Identity binding (restored from 076; #4544). This RPC-level check was
  -- silently dropped when 085 re-issued the accept body without it, leaving the
  -- route 403 (which no-ops when its pre-check SELECT returns null) as the only
  -- gate. 076's header is explicit that the binding lives here as defense in
  -- depth so a direct service_role call cannot accept an invite it was not
  -- addressed to. Re-issued verbatim from 076.
  IF v_inv.invitee_user_id IS NOT NULL AND v_inv.invitee_user_id <> v_accepter THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_intended_invitee');
  END IF;
  IF v_inv.invitee_user_id IS NULL THEN
    IF LOWER(v_inv.invitee_email) <> LOWER((SELECT email FROM auth.users WHERE id = v_accepter)) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'not_intended_invitee');
    END IF;
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

  -- Mark accepted. Do NOT overwrite attestation_id: it was set at creation and
  -- is immutable per the workspace_invitations_no_mutate trigger. The acceptance
  -- attestation is linked from workspace_members below, not from the invitation.
  UPDATE public.workspace_invitations
  SET accepted_at = now()
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

REVOKE ALL ON FUNCTION public.accept_workspace_invitation(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accept_workspace_invitation(uuid, uuid) TO service_role;
