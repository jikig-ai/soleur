-- 079_workspace_repo_ownership_schema.down.sql
-- Reverse 079: drop both new RPCs, revert runtime_jwt_mint_hook to its
-- exact migration-060 body (org-only injection), drop current_workspace_id,
-- restore the table-level SELECT grant on workspaces, drop the repo
-- indexes + columns.
--
-- ROLLBACK SAFETY (ADR-044): reverting the schema alone while the 081
-- read-cutover still ships would induce the wrong-repo hazard. The
-- rollback runbook MUST be all-or-nothing (revert 081 + 080 + 079
-- together) OR reset every user_session_state.current_workspace_id to the
-- user's solo workspace. This .down.sql drops the column entirely, which
-- satisfies the "reset claim" requirement (no claim survives the drop).

DROP FUNCTION IF EXISTS public.set_current_workspace_id(uuid);
DROP FUNCTION IF EXISTS public.resolve_workspace_installation_id(uuid);

-- Revert the hook to the exact migration-060 body (org injection + OTP
-- precheck only; no current_workspace_id).
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

  SELECT current_organization_id INTO v_org_id
  FROM public.user_session_state
  WHERE user_id = v_user_id;

  IF v_org_id IS NOT NULL THEN
    v_app_metadata := COALESCE(v_claims->'app_metadata', '{}'::jsonb);
    v_app_metadata := jsonb_set(v_app_metadata, '{current_organization_id}', to_jsonb(v_org_id::text));
    v_claims := jsonb_set(v_claims, '{app_metadata}', v_app_metadata);
  END IF;

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

-- Drop the session claim column.
ALTER TABLE public.user_session_state
  DROP COLUMN IF EXISTS current_workspace_id;

-- Restore the Supabase default table-level SELECT grant (undoes the
-- column-level split). The narrower column-list grant becomes subsumed.
GRANT SELECT ON public.workspaces TO authenticated;

-- Drop the repo indexes + columns.
DROP INDEX IF EXISTS public.workspaces_installation_repo_idx;
DROP INDEX IF EXISTS public.workspaces_repo_url_idx;

ALTER TABLE public.workspaces
  DROP COLUMN IF EXISTS repo_last_synced_at,
  DROP COLUMN IF EXISTS repo_status,
  DROP COLUMN IF EXISTS github_installation_id,
  DROP COLUMN IF EXISTS repo_provider,
  DROP COLUMN IF EXISTS repo_url;
