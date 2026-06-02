-- 092_transfer_ownership_caller_override.sql
-- fix: transfer_workspace_ownership broken under service-role (#4765).
--
-- Migration 075 gated the caller on a bare auth.uid(), but the sole caller
-- (server/workspace-membership.ts transferWorkspaceOwnership) invokes the RPC
-- via createServiceClient() (SUPABASE_SERVICE_ROLE_KEY, persistSession:false),
-- under which auth.uid() returns NULL. Every call therefore raised 28000 →
-- the wrapper mapped it to rpc_failed → HTTP 500. The flow is gated behind
-- isTeamWorkspaceInviteEnabled (dogfood), which is why it never surfaced.
--
-- Fix: adopt the COALESCE(p_caller_user_id, auth.uid()) caller-resolution +
-- service-role-only grant shape established by rename_organization (mig 091)
-- and accept_workspace_invitation (mig 076/085). The route already passes the
-- verified getUser() id as args.callerUserId; the wrapper now forwards it as
-- p_caller_user_id. When auth.uid() IS populated (authenticated-client call)
-- COALESCE returns the same value, so the gate is correct under both modes.
--
-- SECURITY: the new p_caller_user_id param is forgeable. It is ONLY safe
-- because the 4-arg RPC is GRANTed to service_role ONLY (NOT authenticated) —
-- if authenticated could reach it via PostgREST, any user could forge
-- p_caller_user_id = <victim owner uuid> and steal a workspace they do not
-- own (the identical P1 privilege-escalation class fixed in #4762). 075
-- granted the 3-arg form to `authenticated`; this migration DROPs that
-- overload and grants the new 4-arg form to service_role only.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: SET search_path =
-- public, pg_temp (pg_temp LAST). Per
-- 2026-05-06-supabase-default-privileges-defeat-revoke-from-public: explicit
-- REVOKE from PUBLIC + anon + authenticated before the service_role GRANT.
--
-- Scope: this migration touches ONLY transfer_workspace_ownership. The
-- update_workspace_member_role and anonymise_organization_membership
-- functions that also live in 075 are unaffected and intentionally NOT
-- re-emitted here (re-emitting would create a second source of truth).
--
-- FORWARD REFERENCE: any future migration that DROPs and recreates
-- transfer_workspace_ownership MUST preserve the
-- COALESCE(p_caller_user_id, auth.uid()) caller resolution AND the
-- service_role-only grant — reverting to a bare auth.uid() gate or an
-- authenticated grant silently re-introduces #4765 (service-role 500) or
-- the #4762 forgeable-override tenant-takeover class respectively.

-- Drop the old 3-arg, authenticated-granted overload. Postgres distinguishes
-- overloads by parameter list, so without this DROP the 075 form would remain
-- reachable by `authenticated` via PostgREST.
DROP FUNCTION IF EXISTS public.transfer_workspace_ownership(uuid, uuid, text);

CREATE OR REPLACE FUNCTION public.transfer_workspace_ownership(
  p_workspace_id       uuid,
  p_new_owner_user_id  uuid,
  p_attestation_text   text,
  p_caller_user_id     uuid DEFAULT NULL
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_user_id uuid := COALESCE(p_caller_user_id, auth.uid());
  v_is_owner       boolean;
  v_target_role    text;
  v_attestation_id uuid;
  v_org_id         uuid;
BEGIN
  -- 1. Authenticate
  IF v_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'caller_user_id is NULL — caller must be authenticated'
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

-- GRANT to service_role ONLY (NOT authenticated). The RPC takes a
-- caller-override param (p_caller_user_id) that COALESCE prefers over
-- auth.uid(); if authenticated could reach it via PostgREST, any user could
-- forge p_caller_user_id = <victim owner uuid> and bypass the route's
-- owner-gate (full tenant takeover — the #4762 P1 class). Mirrors
-- rename_organization (mig 091:116-119) and accept_workspace_invitation
-- (mig 076/085) verbatim — the forgeable-override pattern is ONLY safe behind
-- service-role, because the sole caller (server/workspace-membership.ts
-- transferWorkspaceOwnership) invokes via createServiceClient() and forwards
-- the route-verified getUser() id.
REVOKE ALL ON FUNCTION public.transfer_workspace_ownership(uuid, uuid, text, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.transfer_workspace_ownership(uuid, uuid, text, uuid)
  TO service_role;

COMMENT ON FUNCTION public.transfer_workspace_ownership(uuid, uuid, text, uuid) IS
  'Atomic workspace ownership transfer. Single-owner strict: promotes '
  'target to owner, demotes caller to member, updates organizations.'
  'owner_user_id, writes attestation + revocation rows. Caller resolved via '
  'COALESCE(p_caller_user_id, auth.uid()) for service-role invocation; '
  'service_role-only grant (forgeable override). #4520 / #4765.';
