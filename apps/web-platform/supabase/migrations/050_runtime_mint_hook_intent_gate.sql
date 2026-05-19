-- Migration 050: runtime_jwt_mint_hook intent-gate strengthening.
--
-- Migration 047 introduced the Custom Access Token Hook with a single gate:
--   IF v_auth_method <> 'otp' THEN pass-through
--
-- The Phase-4 empirical probe (ADR-033 §0.7, 2026-05-18) established that
-- this gate is insufficient: Supabase's hook event payload contains no
-- field that discriminates the runtime mint path (auth.admin.generateLink +
-- verifyOtp{token_hash}) from the dashboard OTP login path (signInWithOtp +
-- verifyOtp{token}). Both produce identical aud/amr/exp/app_metadata, so
-- every dashboard login was being rewritten with aud='soleur-runtime' and
-- exp=600s (10-minute auto-logout for end users).
--
-- This migration replaces the hook (CREATE OR REPLACE FUNCTION — same
-- signature, grants preserved) with a strengthened gate that additionally
-- requires consumption of a row from public.runtime_mint_intent (added in
-- migration 049). tenant.ts UPSERTs the marker before its generateLink
-- call; this hook atomically DELETEs it inside a CTE. Dashboard logins
-- never UPSERT, so the DELETE finds no row → pass-through.
--
-- Race window + bounded-harm analysis: see migration 049 prose.
--
-- Plan: knowledge-base/project/plans/2026-05-18-refactor-runtime-jwt-asymmetric-signing-substrate-plan.md §Phase 4 amendment
-- ADR:  knowledge-base/engineering/architecture/decisions/ADR-033-runtime-jwt-signing-substrate.md §0.7

CREATE OR REPLACE FUNCTION public.runtime_jwt_mint_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id          uuid;
  v_claims           jsonb;
  v_auth_method      text;
  v_intent_consumed  boolean;
  v_precheck         record;
  -- Runtime JWTs are minted with a TTL of 600s. See migration 047 prose.
  v_ttl_sec          int := 600;
BEGIN
  v_user_id     := (event->>'user_id')::uuid;
  v_claims      := event->'claims';
  v_auth_method := event->>'authentication_method';

  -- Atomic check-and-consume. A single SQL statement (DELETE ... RETURNING
  -- inside WITH) is race-safe against concurrent hook firings. The CTE
  -- materializes whether any row was removed; v_intent_consumed reflects
  -- the boolean check.
  --
  -- 10-second TTL guards against stale intents (defense in depth — if the
  -- table were ever writeable by an unintended role, ancient rows would
  -- still not unlock the mint path).
  WITH consumed AS (
    DELETE FROM public.runtime_mint_intent
    WHERE user_id = v_user_id
      AND created_at > NOW() - INTERVAL '10 seconds'
      AND created_at <= NOW()
    RETURNING 1
  )
  SELECT EXISTS (SELECT 1 FROM consumed) INTO v_intent_consumed;

  -- Note: GoTrue's Custom Access Token Hook runs inside the JWT-issuance
  -- transaction. If GoTrue rolls back post-hook (e.g., refresh-token write
  -- failure), the DELETE above rolls back too — the marker survives. The
  -- 10s TTL bounds the residual exposure; the next dashboard OTP login for
  -- the same user within that window could consume the leftover marker
  -- and receive runtime claims. Bounded harm matches the documented
  -- ADR-033 §0.7 race characterization (still self-recovering via
  -- re-login); flagged here so future operators don't miss it during
  -- incident triage.

  -- Pass-through gate. BOTH conditions must hold for the mint path:
  --   (a) authentication_method = 'otp' — pre-existing gate from 047,
  --       distinguishes from password/oauth/token_refresh.
  --   (b) intent row consumed — distinguishes runtime from dashboard OTP.
  --
  -- The 'otp' check stays for defense in depth: even if a future change
  -- causes the marker to leak, non-OTP paths (password logins, OAuth,
  -- refresh-token rotations) remain pass-through.
  IF v_auth_method <> 'otp' OR NOT v_intent_consumed THEN
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
  -- are present in v_claims from GoTrue's baseline. We OVERWRITE only the
  -- ones the runtime contract owns:
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

-- Grants preserved from migration 047 (CREATE OR REPLACE retains them).
-- Repeated here for migration-rpc-grants.test.ts file-parse linting and
-- so a reader of migration 050 in isolation sees the role-restriction
-- contract. REVOKE/GRANT are idempotent.
REVOKE ALL ON FUNCTION public.runtime_jwt_mint_hook(jsonb) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.runtime_jwt_mint_hook(jsonb) TO supabase_auth_admin;

-- Comment updated to reflect the strengthened gate.
COMMENT ON FUNCTION public.runtime_jwt_mint_hook(jsonb) IS
  'Custom Access Token Hook for runtime JWTs (Resolution C, #3363, Phase-4 '
  'intent-gate strengthening). Gates on authentication_method=otp AND '
  'consumption of public.runtime_mint_intent row written by '
  'lib/supabase/tenant.ts:mintFounderJwt. Discriminates runtime mint path '
  'from user-facing dashboard OTP logins (ADR-033 §0.7 empirical probe). '
  'Calls precheck_jwt_mint and injects jti+exp+iat+aud+role. Errors '
  'propagate (no WHEN OTHERS pass-through) — security-critical.';
