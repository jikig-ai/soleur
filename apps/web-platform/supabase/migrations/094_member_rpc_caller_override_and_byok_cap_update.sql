-- 094_member_rpc_caller_override_and_byok_cap_update.sql
--
-- Problem 1 (member removal 500): remove_workspace_member (mig 062/067/068)
-- gates the caller on a bare auth.uid(), but the sole caller
-- (server/workspace-membership.ts removeWorkspaceMember) invokes the RPC via
-- createServiceClient() (SUPABASE_SERVICE_ROLE_KEY, persistSession:false),
-- under which auth.uid() returns NULL. Every removal therefore raised 28000 →
-- the wrapper fell through to rpc_failed → HTTP 500 → "Failed to remove
-- member. Please try again." toast. This is the IDENTICAL defect class that
-- migration 092 fixed for transfer_workspace_ownership (#4765) and #4761 fixed
-- for the BYOK grant path. PR #4779 only changed the same page's
-- workspace-resolution — a timing coincidence, not the cause.
--
-- Fix (Problem 1): adopt the COALESCE(p_caller_user_id, auth.uid()) caller-
-- resolution + service_role-only grant shape from mig 092. The route already
-- forwards the verified getUser() id as args.callerUserId; the wrapper now
-- forwards it as p_caller_user_id. update_workspace_member_role (mig 067) has
-- the identical hole and is patched as defense-in-depth (no route reaches it
-- today, but it WILL be wired later).
--
-- SECURITY: the new p_caller_user_id param is forgeable. It is ONLY safe
-- because the overloaded RPCs are GRANTed to service_role ONLY (NOT
-- authenticated) — if authenticated could reach them via PostgREST, any user
-- could forge p_caller_user_id = <victim owner uuid> and remove members from a
-- workspace they do not own (the #4762 P1 privilege-escalation class). The old
-- 2-arg / 3-arg overloads (granted to authenticated) are DROPped so no
-- orphaned reachable form remains. Postgres distinguishes overloads by
-- parameter list.
--
-- Problem 2 (no post-join cap update): the byok_delegations WORM trigger
-- byok_delegations_no_mutate already permits a "cap-update flip" (Shape 3, mig
-- 064:332-353 — "raise Harry's budget" UX) and the cap_updated_at /
-- cap_updated_by_user_id columns exist (064:102-103), but NO RPC executes that
-- flip and byok_delegations REVOKEs UPDATE from authenticated. So the owner can
-- only set a cap at grant time; changing it requires revoke + re-grant (which
-- resets spend accounting). This migration adds update_byok_delegation_cap, an
-- UPDATE-flip RPC modelled on revoke_byok_delegation (064:495-568). Caller/actor
-- resolution follows the BYOK grant/revoke pattern (auth.uid() branch + actor
-- impersonation guard), NOT the transfer-ownership service_role-only pattern,
-- because the BYOK RPCs reject impersonation internally — so GRANT to
-- authenticated + service_role is safe. The actor is restricted to grantor /
-- created_by (a grantee may NOT raise their own cap).
--
-- A cap change MUST be an UPDATE-flip, never a re-grant: grant_byok_delegation
-- is a pure INSERT guarded by the partial unique index
-- byok_delegations_active_triple_uidx (064:146); a second active grant for the
-- same (grantor,grantee,workspace) triple violates the index.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: SET search_path =
-- public, pg_temp (pg_temp LAST). Per
-- 2026-05-06-supabase-default-privileges-defeat-revoke-from-public: explicit
-- REVOKE from PUBLIC + anon + authenticated before any GRANT.
--
-- FORWARD REFERENCE: any future migration that DROPs/recreates these member
-- RPCs MUST preserve COALESCE(p_caller_user_id, auth.uid()) + service_role-only
-- grant; reverting to a bare auth.uid() gate re-introduces the service-role
-- 500, and an authenticated grant re-introduces the forgeable-override
-- tenant-takeover class.

-- =====================================================================
-- 1. remove_workspace_member — 3-arg caller-override (Problem 1)
-- =====================================================================

-- Drop the old 2-arg, authenticated-granted overload so it is no longer
-- reachable by `authenticated` via PostgREST.
DROP FUNCTION IF EXISTS public.remove_workspace_member(uuid, uuid);

CREATE OR REPLACE FUNCTION public.remove_workspace_member(
  p_workspace_id   uuid,
  p_user_id        uuid,
  p_caller_user_id uuid DEFAULT NULL
) RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_user_id uuid := COALESCE(p_caller_user_id, auth.uid());
  v_is_owner       boolean;
  v_target_role    text;
  v_org_id         uuid;
  v_rows           int;
  v_anon_count     int;
BEGIN
  IF v_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'caller_user_id is NULL — caller must be authenticated'
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

  -- mig 068 #4318 — cascade-pseudonymise authored messages-with-attachments
  -- BEFORE the DELETE (defense-in-depth; see mig 068 header §F2).
  v_anon_count := public._anonymise_authored_messages_internal(p_user_id, p_workspace_id);

  -- Append WORM revocation row (mig 067 #4307). FK violation rolls the DELETE
  -- back atomically per mig 062 AC2.
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

  -- F6: clear user_session_state.current_organization_id if it points to the
  -- affected organization AND the user has no remaining workspaces in it.
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

-- GRANT to service_role ONLY (NOT authenticated). The caller-override param
-- (p_caller_user_id) is forgeable; if authenticated could reach it via
-- PostgREST, any user could forge p_caller_user_id = <victim owner uuid> and
-- remove members from a workspace they do not own. Mirrors mig 092:178-191.
-- service_role's default EXECUTE grant is preserved (never revoked) — the sole
-- caller invokes via createServiceClient().
REVOKE ALL ON FUNCTION public.remove_workspace_member(uuid, uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.remove_workspace_member(uuid, uuid, uuid)
  TO service_role;

COMMENT ON FUNCTION public.remove_workspace_member(uuid, uuid, uuid) IS
  'Workspace-member removal RPC (mig 094 caller-override fix #4779-followup). '
  'Caller resolved via COALESCE(p_caller_user_id, auth.uid()) for service-role '
  'invocation; service_role-only grant (forgeable override). Atomic body: '
  'authorise owner; reject self/owner-target; cascade-pseudonymise authored '
  'messages-with-attachments (mig 068 #4318); INSERT workspace_member_removals '
  'WORM row; DELETE workspace_members; clear user_session_state (F6).';

-- =====================================================================
-- 2. update_workspace_member_role — 4-arg caller-override (defense-in-depth)
-- =====================================================================

DROP FUNCTION IF EXISTS public.update_workspace_member_role(uuid, uuid, text);

CREATE OR REPLACE FUNCTION public.update_workspace_member_role(
  p_workspace_id   uuid,
  p_user_id        uuid,
  p_new_role       text,
  p_caller_user_id uuid DEFAULT NULL
) RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_user_id uuid := COALESCE(p_caller_user_id, auth.uid());
  v_org_id         uuid;
BEGIN
  IF v_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'caller_user_id is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;

  -- Authorize FIRST so unauthenticated/unauthorised callers cannot probe the
  -- role enum (mig 067 security-sentinel P3-2).
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

  -- Mirror remove_workspace_member's guards (mig 067 P2-1): owner cannot
  -- self-mutate role; demoting the last owner would administratively lock the
  -- workspace.
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

  -- F2: actor attribution for the PA-20 §(g)(3) audit trigger.
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

  -- F6 (role-change variant): force JWT refresh by clearing the
  -- current_organization_id pointer if it matches the affected workspace's org.
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

-- service_role-only grant (forgeable override, same rationale as
-- remove_workspace_member above + mig 092). service_role's default EXECUTE is
-- preserved.
REVOKE ALL ON FUNCTION public.update_workspace_member_role(uuid, uuid, text, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_workspace_member_role(uuid, uuid, text, uuid)
  TO service_role;

COMMENT ON FUNCTION public.update_workspace_member_role(uuid, uuid, text, uuid) IS
  'Workspace-member role-change RPC (mig 094 caller-override fix). Caller '
  'resolved via COALESCE(p_caller_user_id, auth.uid()); service_role-only '
  'grant (forgeable override). Preserves owner-gate, invalid-role guard, '
  'self-mutate + last-owner-demote guards, audit GUC, revocation row, F6 '
  'session clear (mig 067 #4307).';

-- =====================================================================
-- 3. update_byok_delegation_cap — WORM Shape-3 cap-update RPC (Problem 2)
-- =====================================================================
--
-- Branches on auth.uid() IS NULL like grant/revoke_byok_delegation:
--   Service-role (auth.uid() NULL): p_actor_user_id required.
--   Authenticated (auth.uid() set): p_actor_user_id must be NULL or = auth.uid().
-- Actor MUST be grantor or created_by of the row (NOT grantee — a grantee may
-- not raise their own cap). Performs the WORM Shape-3 cap-update flip
-- (064:332-353): daily/hourly change + cap_updated_at + cap_updated_by_user_id,
-- every other column unchanged.

CREATE OR REPLACE FUNCTION public.update_byok_delegation_cap(
  p_delegation_id        uuid,
  p_daily_usd_cap_cents  int,
  p_hourly_usd_cap_cents int,
  p_actor_user_id        uuid DEFAULT NULL
) RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_jwt uuid := auth.uid();
  v_actor      uuid;
  v_row        public.byok_delegations%ROWTYPE;
BEGIN
  IF v_caller_jwt IS NULL THEN
    IF p_actor_user_id IS NULL THEN
      RAISE EXCEPTION 'update_byok_delegation_cap: service-role caller MUST supply p_actor_user_id'
        USING ERRCODE = '22023';
    END IF;
    v_actor := p_actor_user_id;
  ELSE
    IF p_actor_user_id IS NOT NULL AND p_actor_user_id <> v_caller_jwt THEN
      RAISE EXCEPTION 'update_byok_delegation_cap: authenticated caller MAY NOT impersonate another actor'
        USING ERRCODE = '42501';
    END IF;
    v_actor := v_caller_jwt;
  END IF;

  -- Cap bound checks (identical to grant_byok_delegation 064:451-463).
  IF p_daily_usd_cap_cents IS NULL
     OR p_daily_usd_cap_cents < 1
     OR p_daily_usd_cap_cents > 1000000 THEN
    RAISE EXCEPTION 'update_byok_delegation_cap: daily_usd_cap_cents out of range [1, 1000000]; got %',
      p_daily_usd_cap_cents
      USING ERRCODE = '22003';
  END IF;
  IF p_hourly_usd_cap_cents IS NULL
     OR p_hourly_usd_cap_cents < 1
     OR p_hourly_usd_cap_cents > p_daily_usd_cap_cents THEN
    RAISE EXCEPTION 'update_byok_delegation_cap: hourly_usd_cap_cents out of range [1, daily=%]; got %',
      p_daily_usd_cap_cents, p_hourly_usd_cap_cents
      USING ERRCODE = '22003';
  END IF;

  -- Row-lock + load OLD shape for attribution / idempotency validation.
  SELECT * INTO v_row
    FROM public.byok_delegations
   WHERE id = p_delegation_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'update_byok_delegation_cap: delegation % not found', p_delegation_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_row.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'update_byok_delegation_cap: delegation % already revoked at %',
      p_delegation_id, v_row.revoked_at
      USING ERRCODE = 'P0001', DETAIL = 'byok_delegations:already_revoked';
  END IF;

  -- Attribution: actor MUST be grantor or created_by of THIS row. The grantee
  -- is intentionally excluded — raising one's own spend cap is a privilege
  -- escalation (revoke allows grantee for decline, but cap-raise does not).
  IF v_actor NOT IN (v_row.grantor_user_id, v_row.created_by_user_id) THEN
    RAISE EXCEPTION 'update_byok_delegation_cap: actor % is not grantor/created_by of delegation %',
      v_actor, p_delegation_id
      USING ERRCODE = '42501';
  END IF;

  -- The WORM Shape-3 flip requires at least one cap value to actually change
  -- (064:338-341); a no-op UPDATE would fall through to the trigger's catch-all
  -- RAISE. Surface a clean error instead.
  IF p_daily_usd_cap_cents = v_row.daily_usd_cap_cents
     AND p_hourly_usd_cap_cents = v_row.hourly_usd_cap_cents THEN
    RAISE EXCEPTION 'update_byok_delegation_cap: caps unchanged for delegation %', p_delegation_id
      USING ERRCODE = '22023';
  END IF;

  -- WORM Shape-3 cap-update flip (064:332-353).
  UPDATE public.byok_delegations
     SET daily_usd_cap_cents    = p_daily_usd_cap_cents,
         hourly_usd_cap_cents   = p_hourly_usd_cap_cents,
         cap_updated_at         = now(),
         cap_updated_by_user_id = v_actor
   WHERE id = p_delegation_id;
END;
$$;

-- GRANT authenticated + service_role: the internal impersonation guard
-- (authenticated caller may not pass an actor ≠ auth.uid()) closes the forge
-- vector, so the authenticated grant is safe — mirrors grant/revoke (064:482,
-- 572). Distinct from the member RPCs above, which use the forgeable-override
-- pattern and MUST be service_role-only.
REVOKE ALL ON FUNCTION public.update_byok_delegation_cap(uuid, int, int, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_byok_delegation_cap(uuid, int, int, uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.update_byok_delegation_cap(uuid, int, int, uuid) IS
  'Update a byok_delegations daily/hourly cap in place via the WORM Shape-3 '
  'cap-update flip (064:332-353) — preserves the row id + audit continuity, '
  'unlike revoke+re-grant. Branches on auth.uid() IS NULL (service-role '
  'requires p_actor_user_id; authenticated forbids impersonation). Actor MUST '
  'be grantor/created_by (grantee may not raise own cap). Cap range checks '
  'mirror grant_byok_delegation. #4779-followup.';
