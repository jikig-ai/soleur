-- 056_current_organization_jwt_hook.down.sql
-- Reverse migration. Restore runtime_jwt_mint_hook to migration 047
-- shape (no current_organization_id injection); drop
-- user_session_state + set_current_organization_id.

DROP FUNCTION IF EXISTS public.set_current_organization_id(uuid);

-- Restore runtime_jwt_mint_hook to migration 047 shape (OTP-only
-- runtime-mint logic; no current_organization_id injection).
CREATE OR REPLACE FUNCTION public.runtime_jwt_mint_hook(event jsonb)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id     uuid;
  v_claims      jsonb;
  v_auth_method text;
  v_precheck    record;
  v_ttl_sec     int := 600;
BEGIN
  v_user_id     := (event->>'user_id')::uuid;
  v_claims      := event->'claims';
  v_auth_method := event->>'authentication_method';

  IF v_auth_method <> 'otp' THEN
    RETURN jsonb_build_object('claims', v_claims);
  END IF;

  SELECT jti, exp_epoch, iat_epoch INTO v_precheck
  FROM public.precheck_jwt_mint(v_user_id, v_ttl_sec);

  v_claims := jsonb_set(v_claims, '{jti}',  to_jsonb(v_precheck.jti::text));
  v_claims := jsonb_set(v_claims, '{exp}',  to_jsonb(v_precheck.exp_epoch));
  v_claims := jsonb_set(v_claims, '{iat}',  to_jsonb(v_precheck.iat_epoch));
  v_claims := jsonb_set(v_claims, '{aud}',  '"soleur-runtime"');
  v_claims := jsonb_set(v_claims, '{role}', '"authenticated"');

  RETURN jsonb_build_object('claims', v_claims);
END;
$$;

REVOKE ALL ON FUNCTION public.runtime_jwt_mint_hook(jsonb) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.runtime_jwt_mint_hook(jsonb) TO supabase_auth_admin;

DROP POLICY IF EXISTS user_session_state_owner_select ON public.user_session_state;
DROP TABLE IF EXISTS public.user_session_state;
