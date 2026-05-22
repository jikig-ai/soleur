-- 064_workspace_member_revocation_lookup.sql
-- feat-rls-known-gaps-4233-bundle PR-1 (#4307) — middleware revocation
-- lookup for workspace-member removal AND role-change. Extends mig 062's
-- workspace_member_removals WORM ledger with revoked_after + revocation_reason
-- columns, adds the SECURITY DEFINER `check_my_revocation` middleware probe,
-- adds the `update_workspace_member_role` SECURITY DEFINER RPC, and updates
-- `remove_workspace_member` to populate the new columns AND clear stale
-- user_session_state.current_organization_id (F6) atomically.
--
-- LAWFUL_BASIS: GDPR Art. 6(1)(c) record-keeping AND Art. 32(1)(b) entitlement-
-- change TOM. Carries forward PA-19's Art. 30 record; PA-19 §(g)(2) prose is
-- amended in this PR to reflect the two-INSERT-site reality (remove +
-- role-change); PA-19 §(g) gains TOM (10) describing the revocation lookup.
--
-- INVARIANT (F1): EXACTLY TWO `CREATE OR REPLACE FUNCTION` bodies in this
-- file INSERT into public.workspace_member_removals — `remove_workspace_member`
-- (revocation_reason='removed') and `update_workspace_member_role`
-- (revocation_reason='role-changed'). Enforced by the migration-shape lint
-- at apps/web-platform/test/supabase-migrations/064-workspace-member-
-- revocation-lookup.test.ts. The RPC-only-writer invariant from mig 062
-- §1 (column-level REVOKE INSERT/UPDATE/DELETE on the table) protects the
-- new columns at the same boundary as the legacy ones — no WORM trigger
-- rewrite is required (cut C3 in plan-review v2).
--
-- PREDICATE (F5): `check_my_revocation` is USER-GLOBAL — it returns true for
-- the calling user iff ANY revocation row for them has revoked_after strictly
-- > the JWT's iat, regardless of current_organization_id. A multi-workspace
-- user removed from workspace X (org-A) is redirected on ANY context, then
-- signs back in to access their other workspaces. This closes the cross-leak
-- the per-org predicate would have left open at demo time.

-- =====================================================================
-- 1. Schema: add revoked_after + revocation_reason + lookup index
-- =====================================================================

ALTER TABLE public.workspace_member_removals
  ADD COLUMN IF NOT EXISTS revoked_after     timestamptz NULL,
  ADD COLUMN IF NOT EXISTS revocation_reason text         NULL;

-- Backfill legacy rows so any pre-064 removal also blocks stale JWTs whose
-- iat predates the removal. Set revoked_after = removed_at. UPDATE passes
-- the existing WORM trigger (062:140-212) because NEW.id = OLD.id AND
-- NEW.removed_at = OLD.removed_at AND every PII column is unchanged — the
-- trigger only rejects PII NULL → NOT NULL transitions, id/removed_at
-- changes, and unauthorized workspace_id transitions. The two new NULL
-- columns being set to non-NULL is structurally distinct from the PII
-- rule set; the trigger has no clause on revoked_after / revocation_reason
-- and therefore permits the UPDATE.
UPDATE public.workspace_member_removals
   SET revoked_after = removed_at,
       revocation_reason = 'removed'
 WHERE revoked_after IS NULL;

CREATE INDEX IF NOT EXISTS workspace_member_removals_revocation_lookup_idx
  ON public.workspace_member_removals (removed_user_id, revoked_after);

-- =====================================================================
-- 2. check_my_revocation — middleware probe (F5 user-global predicate)
-- =====================================================================

DROP FUNCTION IF EXISTS public.check_my_revocation(timestamptz);

CREATE FUNCTION public.check_my_revocation(p_jwt_iat timestamptz)
  RETURNS TABLE(revoked boolean, workspace_id uuid, reason text)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  -- Defense-in-depth: under SECURITY DEFINER context, a future caller
  -- invoking us with a forged JWT lacking `sub` (or under service_role
  -- which sets auth.uid()=NULL) would silently fall-open returning
  -- revoked=false (predicate `removed_user_id = NULL` matches no rows).
  -- Fail explicit instead. The middleware passes a user-bound supabase
  -- client so this branch is unreachable on the happy path.
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;
  -- User-global predicate (F5): any revocation for auth.uid() with
  -- revoked_after STRICTLY AFTER the JWT's issued-at. Strict `>` absorbs
  -- ±1s clock skew on the safer (deny) side per AC6.
  RETURN QUERY
    SELECT true, wmr.workspace_id, wmr.revocation_reason
      FROM public.workspace_member_removals wmr
     WHERE wmr.removed_user_id = auth.uid()
       AND wmr.revoked_after   > p_jwt_iat
     ORDER BY wmr.revoked_after DESC
     LIMIT 1;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::text;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.check_my_revocation(timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_my_revocation(timestamptz)
  TO authenticated;

COMMENT ON FUNCTION public.check_my_revocation(timestamptz) IS
  'Returns (revoked, workspace_id, reason) for auth.uid(). User-global predicate per #4307 plan-review F5 — any post-iat revocation triggers redirect, regardless of current_organization_id.';

-- =====================================================================
-- 3. remove_workspace_member — populate new columns + clear user_session_state
-- =====================================================================
-- Preserves all existing AC-FLOW4 guards from mig 062:272-342:
--   * NULL auth.uid() rejection (28000)
--   * caller-is-owner authorization (42501)
--   * owner-self-remove rejection (22023)
--   * owner-target rejection (22023)
--   * idempotent not-a-member RETURN 0
-- Adds:
--   * revoked_after = now(), revocation_reason = 'removed' on the INSERT
--   * user_session_state.current_organization_id = NULL when affected (F6)

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

  -- Append WORM revocation row with the new columns populated. The INSERT
  -- lands inside the same SECURITY DEFINER body as the DELETE; FK violation
  -- rolls the DELETE back atomically per mig 062 AC2.
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
  -- The hook at mig 060 doesn't re-validate membership before injecting
  -- current_organization_id into the next JWT; clearing here ensures the
  -- post-refresh JWT lands the user on /login instead of a half-broken
  -- dashboard. Best-effort — a follow-up (AC20-1) will add membership
  -- validation to the hook itself.
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

-- =====================================================================
-- 4. update_workspace_member_role — new RPC (F2 actor + F6 session clear)
-- =====================================================================

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

  -- Authorize FIRST so unauthenticated/unauthorised callers cannot probe
  -- the role enum (security-sentinel P3-2 #4307 review). Owner-check
  -- runs before role-validation; role-validation before any work; F2
  -- actor-attribution after authorization so the GUC only sets for
  -- callers who would actually proceed.
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

  -- Mirror remove_workspace_member's AC-FLOW4 guards (security-sentinel
  -- P2-1 #4307 review): owner cannot self-mutate role, and demoting the
  -- last owner would administratively lock the workspace (every
  -- owner-gated RPC then returns 42501 for everyone).
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

  -- F2: actor attribution so the PA-20 §(g)(3) audit-trigger writes the
  -- actor instead of NULL (orphan-audit-row → Sentry alert per PA-20 §(g)(5)).
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
  -- current_organization_id pointer if it matches the affected workspace's
  -- org. The next JWT mint comes from a clean state; the user signs back
  -- in and lands with their new role.
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

-- REVOKE matrix MUST omit service_role (matches mig 062's
-- remove_workspace_member at 062:344). The TS wrapper
-- `updateWorkspaceMemberRole` in server/workspace-membership.ts calls
-- via `createServiceClient()`; revoking service_role's default EXECUTE
-- would yield 42501 at first call. Stripping service_role here is a
-- self-inflicted production outage (review pattern-recognition + security-
-- sentinel P1, #4307 review).
REVOKE ALL ON FUNCTION public.update_workspace_member_role(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_workspace_member_role(uuid, uuid, text)
  TO authenticated;

COMMENT ON FUNCTION public.update_workspace_member_role(uuid, uuid, text) IS
  'Role-change RPC #4307. SECURITY DEFINER. Owner-only. Writes workspace_member_removals row with revocation_reason=role-changed AND clears user_session_state.current_organization_id (F6). PERFORM set_config workspace_audit.actor_user_id at body top so PA-20 §(g)(3) audit-trigger captures the actor (F2).';
