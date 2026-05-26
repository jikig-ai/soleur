-- Migration 047: Custom Access Token Hook for runtime JWT minting
-- (#3363 Resolution C — supersedes the HS256 substrate from PR-B #3395).
--
-- Adds public.runtime_jwt_mint_hook(event jsonb) -> jsonb, registered as
-- Supabase Auth's Custom Access Token Hook via the Mgmt API
-- (see Deploy-Order Runbook §c in
--  knowledge-base/project/plans/2026-05-18-refactor-runtime-jwt-asymmetric-signing-substrate-plan.md).
--
-- Behavioral contract (verified empirically in Phase 0.2/0.4):
--   - The hook fires on EVERY token-issuance event in this Supabase project.
--   - The pass-through gate is event->>'authentication_method' = 'otp'.
--     On the generateLink+verifyOtp path used by lib/supabase/tenant.ts:
--     mintFounderJwt (post-#3363), Supabase Auth sets
--     authentication_method = 'otp'. All other paths (Dashboard password
--     login, OAuth, refresh-token rotation) get pass-through with claims
--     unchanged — they MUST continue to work or the entire project's auth
--     surface degrades.
--   - When the gate fires (runtime mint path), the hook calls
--     public.precheck_jwt_mint (which raises SQLSTATE '45001' on ceiling
--     trip — see migration 048) and additively jsonb_set()s the
--     hook-controlled claims (jti, exp, iat, aud, role) into the JWT
--     payload. Required claims that cannot be removed (iss, aud, exp,
--     iat, sub, role, aal, session_id, email, phone, is_anonymous) are
--     preserved by the additive jsonb_set pattern.
--
-- Failure semantics: NO `EXCEPTION WHEN OTHERS` block. Security-critical
-- functions fail loud. Errors propagate to GoTrue which returns HTTP 500
-- to the Node caller; lib/supabase/tenant.ts:mintFounderJwt raises
-- RuntimeAuthError on the verifyOtp.error path.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: SECURITY DEFINER fn
-- pins SET search_path = public, pg_temp (pg_temp LAST).
-- Per cq-supabase-migration-no-concurrently: no CREATE INDEX CONCURRENTLY.

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
  -- Runtime JWTs are minted with a TTL of 600s (matches PR-B's TTL/2
  -- caching boundary at lib/supabase/tenant.ts:DEFAULT_TTL_SEC). The hook
  -- doesn't receive the Node caller's ttlSec preference — the precheck
  -- output's exp_epoch/iat_epoch encodes the durable contract. Hard-code
  -- here so the hook is self-contained; if a future ttlSec change is
  -- needed it lives in a coordinated migration + tenant.ts edit per
  -- 2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md.
  v_ttl_sec     int := 600;
BEGIN
  v_user_id     := (event->>'user_id')::uuid;
  v_claims      := event->'claims';
  v_auth_method := event->>'authentication_method';

  -- Pass-through gate.
  -- Phase 0.4 pre-commit decision (plan-review panel): gate on
  -- authentication_method = 'otp' rather than aud=soleur-runtime, because
  -- the audience-injection channel (app_metadata.target_aud or verifyOtp
  -- audience param) is not guaranteed to flow into the hook input.
  -- The 'otp' gate is robust and API-readable from event payload directly.
  -- Empirically verified against dev (ADR-033 §0.4): verifyOtp path
  -- produces amr=[{method:"otp"}] and Supabase sets authentication_method
  -- to "otp" on the hook input.
  --
  -- Future-optimization channels if multi-aud-per-founder becomes a need:
  --   (a) auth.users.app_metadata.target_aud propagation into claims.
  --   (b) verifyOtp audience request parameter.
  -- Neither is exercised by this PR; the 'otp' gate is sufficient for
  -- the single-runtime-aud surface.
  IF v_auth_method <> 'otp' THEN
    RETURN jsonb_build_object('claims', v_claims);
  END IF;

  -- Pull the precheck row (atomic rate-limit + jti generation).
  -- precheck_jwt_mint raises with custom ERRCODE '45001' on ceiling trip
  -- (see migration 048). No EXCEPTION WHEN OTHERS catch — propagation is
  -- the contract. Node side surfaces 500 → RuntimeAuthError.
  SELECT jti, exp_epoch, iat_epoch INTO v_precheck
  FROM public.precheck_jwt_mint(v_user_id, v_ttl_sec);

  -- Additive jsonb_set: required claims from Supabase's spec (iss, aud,
  -- exp, iat, sub, role, aal, session_id, email, phone, is_anonymous)
  -- are present in v_claims from GoTrue's baseline (verified in Phase
  -- 0.2). We OVERWRITE only the ones the runtime contract owns:
  --   - jti: precheck-issued (load-bearing for denied_jti revocation)
  --   - exp: precheck.exp_epoch (overrides Supabase default 3600)
  --   - iat: precheck.iat_epoch (matches exp window)
  --   - aud: 'soleur-runtime' (overrides default 'authenticated')
  --   - role: 'authenticated' (preserved; explicit for parity with PR-B)
  v_claims := jsonb_set(v_claims, '{jti}', to_jsonb(v_precheck.jti::text));
  v_claims := jsonb_set(v_claims, '{exp}', to_jsonb(v_precheck.exp_epoch));
  v_claims := jsonb_set(v_claims, '{iat}', to_jsonb(v_precheck.iat_epoch));
  v_claims := jsonb_set(v_claims, '{aud}', '"soleur-runtime"');
  v_claims := jsonb_set(v_claims, '{role}', '"authenticated"');

  RETURN jsonb_build_object('claims', v_claims);
END;
$$;

-- Locked down per the Supabase hooks contract: the hook is invoked by
-- the GoTrue auth daemon running as role supabase_auth_admin.
REVOKE ALL ON FUNCTION public.runtime_jwt_mint_hook(jsonb) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.runtime_jwt_mint_hook(jsonb) TO supabase_auth_admin;

COMMENT ON FUNCTION public.runtime_jwt_mint_hook(jsonb) IS
  'Custom Access Token Hook for runtime JWTs (Resolution C, #3363). '
  'Gates on authentication_method=otp; calls precheck_jwt_mint and '
  'injects jti+exp+iat+aud+role into the JWT claims so denied_jti '
  'revocation continues to work against the JWT''s own jti claim '
  '(no binding table required). Errors propagate (no WHEN OTHERS '
  'pass-through) — security-critical.';
