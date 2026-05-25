-- =====================================================================
-- 063_post_workspace_rpc_repair.sql — post-workspace contract repair.
-- =====================================================================
--
-- Issue: #4342 (tenant-integration CI runtime failures post-PR #4339).
--
-- Migration 059 added `workspace_id NOT NULL` + the CHECK constraint
-- `scope_grants_workspace_id_check` to `scope_grants` (059:359) but did
-- NOT update the `grant_action_class` RPC body at 051:284, which still
-- INSERTs `(founder_id, action_class, tier)` without `workspace_id`.
-- Every caller (production POST /api/scope-grants/grant route and the
-- 13 test sites across 4 files) fails 23514.
--
-- Migration 053 also REVOKEs `is_workspace_member` from service_role at
-- 053:139, but multiple tenant-iso tests (workspace-members.test.ts:90,
-- :102, :133, :140) call the helper via service-role and fail 42501.
--
-- This migration fixes both with `CREATE OR REPLACE` (additive) only:
--   (1) `grant_action_class` derives `workspace_id` internally from the
--       solo-canary predicate established in 059's own backfill at
--       059:344-347 (`workspace_members WHERE user_id = founder_id AND
--       workspace_id = founder_id AND role = 'owner'`). API surface
--       preserved (2-arg shape) — no caller change required.
--   (2) `GRANT EXECUTE ON FUNCTION is_workspace_member TO service_role`
--       additive; does not affect any other role's permissions.
--
-- Failure classes addressed (issue body understated; see plan):
--   A. grant_action_class missing workspace_id INSERT → 23514
--   B. is_workspace_member missing service_role GRANT → 42501
-- Classes C-F (test fixtures) are handled in the test diff of the same PR.
--
-- Multi-workspace future: when a founder is a member of N workspaces
-- (beyond their own solo backfill), this RPC will need an explicit
-- `p_workspace_id` arg with the solo-canary as default. Tracked as
-- "Future Work" in plan; not in scope for this hotfix.
--
-- CREATE OR REPLACE only — no destructive DDL. Down migration restores
-- the pre-fix RPC body verbatim from 051:256-295.
-- =====================================================================

-- ---------------------------------------------------------------------
-- (1) grant_action_class — re-CREATE OR REPLACE with workspace_id
--     derivation from the solo-canary predicate. Same signature as
--     051:256 to preserve back-compat for all callers.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.grant_action_class(
  p_action_class text,
  p_tier         text
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_founder_id   uuid := auth.uid();
  v_workspace_id uuid;
  v_grant_id     uuid;
BEGIN
  IF v_founder_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;
  IF p_tier NOT IN ('auto', 'draft_one_click', 'approve_every_time', 'auto_with_digest') THEN
    RAISE EXCEPTION 'invalid tier: %', p_tier USING ERRCODE = '22P02';
  END IF;

  -- Derive workspace_id from the solo-canary predicate established by
  -- migration 059's own backfill (059:344-347). handle_new_user (053)
  -- guarantees exactly one (user_id=X, workspace_id=X, role='owner') row
  -- per signed-up user, so this SELECT returns at most one row. If the
  -- canary row is missing for any reason, v_workspace_id stays NULL and
  -- the INSERT below raises 23502 (NOT NULL) — column context preserved
  -- by the DB error, no custom SQLSTATE needed.
  SELECT workspace_id INTO v_workspace_id
    FROM public.workspace_members
   WHERE user_id      = v_founder_id
     AND workspace_id = v_founder_id
     AND role         = 'owner';

  -- Revoke any currently-active grant for this (founder, action_class).
  UPDATE public.scope_grants
     SET revoked_at = now(),
         revoked_reason = 'tier_change'
   WHERE founder_id = v_founder_id
     AND action_class = p_action_class
     AND revoked_at IS NULL;

  INSERT INTO public.scope_grants (founder_id, action_class, tier, workspace_id)
       VALUES (v_founder_id, p_action_class, p_tier, v_workspace_id)
  RETURNING id INTO v_grant_id;

  RETURN v_grant_id;
END;
$$;

REVOKE ALL ON FUNCTION public.grant_action_class(text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.grant_action_class(text, text)
  TO authenticated;

COMMENT ON FUNCTION public.grant_action_class(text, text) IS
  'Issues a scope_grants row for the calling founder under their solo '
  'workspace. workspace_id derived internally from the 059-backfill '
  'solo-canary invariant. Multi-workspace support requires explicit '
  'p_workspace_id arg (see #4342 plan Future Work).';

-- ---------------------------------------------------------------------
-- (2) is_workspace_member — additive GRANT for service_role so tests
--     using SUPABASE_SERVICE_ROLE_KEY can call the helper. service_role
--     already bypasses RLS on workspace_members directly, so this is
--     functionally equivalent in access pattern; the function is read-
--     only and side-effect-free with a pinned search_path.
-- ---------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.is_workspace_member(uuid, uuid) TO service_role;
