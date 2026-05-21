-- 056_current_organization_jwt_hook.sql
-- feat-team-workspace-multi-user (#4229, PR #4225) — JWT custom-claim
-- hook extension for current_organization_id + user_session_state
-- table + set_current_organization_id RPC.
--
-- DEPENDENCY: migrations 053 + 055 must have applied (organizations,
-- workspaces, workspace_members tables + the backfilled solo rows;
-- workspace_id columns on the 9 swept tables for the JWT-resident
-- org context to actually gate visibility).
--
-- The existing runtime_jwt_mint_hook (migration 047) is the SINGLE
-- Supabase Auth custom_access_token_hook slot. Supabase Auth supports
-- only ONE such hook per project. This migration EXTENDS the existing
-- hook to also inject `app_metadata.current_organization_id` into the
-- JWT claims on ALL paths (OTP runtime-mint AND regular user logins),
-- sourcing from public.user_session_state.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: pins
-- SET search_path = public, pg_temp.
-- Per migration 047 precedent: failure semantics — NO `EXCEPTION WHEN
-- OTHERS` block. Security-critical functions fail loud.

-- =====================================================================
-- 1. user_session_state table
-- =====================================================================
--
-- Stores the per-user current_organization_id selection. The JWT hook
-- reads this on every token mint/refresh and injects the value into
-- app_metadata. The set_current_organization_id RPC (below) writes it
-- after validating that the caller is a member of the target org.

CREATE TABLE IF NOT EXISTS public.user_session_state (
  user_id                 uuid          PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  current_organization_id uuid          NULL REFERENCES public.organizations(id) ON DELETE SET NULL,
  updated_at              timestamptz   NOT NULL DEFAULT now()
);

ALTER TABLE public.user_session_state ENABLE ROW LEVEL SECURITY;

-- Users can SELECT their own session_state row.
CREATE POLICY user_session_state_owner_select ON public.user_session_state
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- INSERT/UPDATE routed through set_current_organization_id RPC; no
-- direct grant.

-- =====================================================================
-- 2. Backfill user_session_state from existing workspaces
-- =====================================================================
--
-- For each user, pick the organization of their oldest workspace
-- membership (MIN created_at). For backfilled solo users this is their
-- single workspace = their single organization.

DO $$
DECLARE
  v_rc int;
BEGIN
  INSERT INTO public.user_session_state (user_id, current_organization_id)
  SELECT
    m.user_id,
    (
      SELECT w.organization_id
      FROM public.workspaces w
      JOIN public.workspace_members mm ON mm.workspace_id = w.id
      WHERE mm.user_id = m.user_id
      ORDER BY mm.created_at ASC
      LIMIT 1
    )
  FROM (
    SELECT DISTINCT user_id FROM public.workspace_members
  ) m
  ON CONFLICT (user_id) DO NOTHING;
  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[056-backfill user_session_state] % rows', v_rc;
END $$;

-- =====================================================================
-- 3. Hook extension: inject current_organization_id into JWT claims
-- =====================================================================
--
-- CREATE OR REPLACE runtime_jwt_mint_hook with extended logic:
--   * OTP path (existing behavior): precheck_jwt_mint + jti/exp/iat/
--     aud/role injection — UNCHANGED.
--   * Non-OTP path (previously pass-through): inject
--     app_metadata.current_organization_id from user_session_state.
--   * Both paths: append the current_organization_id claim so
--     workspace-resolver in webapp can read it without a DB round-
--     trip.
--
-- The hook reads user_session_state via the function's SECURITY
-- DEFINER context (postgres role), so RLS doesn't block. The lookup
-- is keyed on the user_id from the event payload.

CREATE OR REPLACE FUNCTION public.runtime_jwt_mint_hook(event jsonb)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id           uuid;
  v_claims            jsonb;
  v_auth_method       text;
  v_precheck          record;
  v_org_id            uuid;
  v_app_metadata      jsonb;
  v_ttl_sec           int := 600;
BEGIN
  v_user_id     := (event->>'user_id')::uuid;
  v_claims      := event->'claims';
  v_auth_method := event->>'authentication_method';

  -- Look up current_organization_id for this user. NULL is valid (the
  -- user has no organization context yet — pre-053-trigger signups
  -- between 053 apply and TS fallback wire-up, edge case). The JWT
  -- claim is omitted entirely in that case rather than encoded as
  -- explicit NULL, so the consumer's `claims.app_metadata.current_organization_id`
  -- access surfaces as `undefined` rather than `null`. The workspace-
  -- resolver in apps/web-platform/server/workspace-resolver.ts handles
  -- both shapes (single-membership users fall back to their default
  -- org per AC-FLOW1).
  SELECT current_organization_id INTO v_org_id
  FROM public.user_session_state
  WHERE user_id = v_user_id;

  -- Inject org_id into app_metadata if present. app_metadata is
  -- maintained additively across hook invocations — we read the
  -- existing app_metadata, jsonb_set the org_id key, write back.
  IF v_org_id IS NOT NULL THEN
    v_app_metadata := COALESCE(v_claims->'app_metadata', '{}'::jsonb);
    v_app_metadata := jsonb_set(v_app_metadata, '{current_organization_id}', to_jsonb(v_org_id::text));
    v_claims := jsonb_set(v_claims, '{app_metadata}', v_app_metadata);
  END IF;

  -- OTP path: runtime-mint precheck + claim injection (migration 047
  -- behavior, unchanged).
  IF v_auth_method = 'otp' THEN
    SELECT jti, exp_epoch, iat_epoch INTO v_precheck
    FROM public.precheck_jwt_mint(v_user_id, v_ttl_sec);

    v_claims := jsonb_set(v_claims, '{jti}',  to_jsonb(v_precheck.jti::text));
    v_claims := jsonb_set(v_claims, '{exp}',  to_jsonb(v_precheck.exp_epoch));
    v_claims := jsonb_set(v_claims, '{iat}',  to_jsonb(v_precheck.iat_epoch));
    v_claims := jsonb_set(v_claims, '{aud}',  '"soleur-runtime"');
    v_claims := jsonb_set(v_claims, '{role}', '"authenticated"');
  END IF;

  RETURN jsonb_build_object('claims', v_claims);
END;
$$;

REVOKE ALL ON FUNCTION public.runtime_jwt_mint_hook(jsonb) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.runtime_jwt_mint_hook(jsonb) TO supabase_auth_admin;

COMMENT ON FUNCTION public.runtime_jwt_mint_hook(jsonb) IS
  'Custom Access Token Hook. (1) Injects app_metadata.current_organization_id '
  'from user_session_state for ALL auth paths (regular login, OAuth, '
  'OTP runtime-mint, refresh-token). (2) For OTP path, additionally '
  'runs precheck_jwt_mint + jti/exp/iat/aud/role injection per '
  'migration 047. The single Supabase Auth hook slot dual-purposes '
  'both responsibilities. ADR-038.';

-- =====================================================================
-- 4. set_current_organization_id RPC
-- =====================================================================
--
-- Caller updates their current_organization_id selection. Validated:
-- caller MUST be a member of the target organization (via at least
-- one workspace_members row for any workspace in the target org).
-- Sets user_session_state.current_organization_id; the next JWT
-- refresh picks up the new claim via the hook above.

CREATE OR REPLACE FUNCTION public.set_current_organization_id(p_org_id uuid)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id    uuid := auth.uid();
  v_is_member  boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF p_org_id IS NULL THEN
    RAISE EXCEPTION 'p_org_id is required'
      USING ERRCODE = '22004';
  END IF;

  -- Authorize: caller must be a member of any workspace in the target
  -- organization.
  SELECT EXISTS (
    SELECT 1 FROM public.workspace_members m
    JOIN public.workspaces w ON w.id = m.workspace_id
    WHERE w.organization_id = p_org_id
      AND m.user_id         = v_user_id
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RAISE EXCEPTION 'caller is not a member of organization %', p_org_id
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.user_session_state (user_id, current_organization_id, updated_at)
       VALUES (v_user_id, p_org_id, now())
  ON CONFLICT (user_id) DO UPDATE
        SET current_organization_id = EXCLUDED.current_organization_id,
            updated_at              = EXCLUDED.updated_at;
END;
$$;

REVOKE ALL ON FUNCTION public.set_current_organization_id(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_current_organization_id(uuid) TO authenticated;

COMMENT ON TABLE public.user_session_state IS
  'Per-user current_organization_id selection for the org-switcher '
  'UI. Read by the JWT custom-claim hook to inject '
  'app_metadata.current_organization_id into every access token. '
  'Written via set_current_organization_id RPC (membership-checked). '
  'ADR-038.';

COMMENT ON FUNCTION public.set_current_organization_id(uuid) IS
  'Sets the calling user''s current_organization_id (org-switcher '
  'UI). Validates that the caller is a member of any workspace in '
  'the target organization. Caller refreshes their session '
  '(supabase.auth.refreshSession()) after this call to pick up the '
  'new JWT claim. ADR-038.';
