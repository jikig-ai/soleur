-- Migration 048: precheck_jwt_mint SQLSTATE disambiguation (#3363 Resolution C).
--
-- In-place CREATE OR REPLACE of precheck_jwt_mint (originally migration 037,
-- PR-B #3244). Sole behavioral change: the rate-limit RAISE now uses custom
-- ERRCODE '45001' (user-defined class — Postgres reserves classes 00-42).
-- Migration 037's RAISE used the default ERRCODE 'P0001', which collides
-- with the WORM-trigger raises elsewhere in 037 (audit_byok_use's UPDATE/
-- DELETE blockers). Migration 047's runtime_jwt_mint_hook needs to
-- distinguish "precheck-rate-limit exceeded" (callers should retry post-
-- backoff or rotate session) from "WORM-trigger violation" (genuine app
-- bug). SQLSTATE-based matching is the durable disambiguator; MESSAGE
-- string-matching ('mint_rate_exceeded') is preserved for callers that
-- already string-match, but new hook code can rely on '45001' exclusively.
--
-- No signature change: (uuid, int) -> TABLE(jti uuid, exp_epoch int,
-- iat_epoch int). The cross-process contract with the Node side and with
-- the runtime_jwt_mint_hook (migration 047) is unchanged.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: SECURITY DEFINER fn
-- pins SET search_path = public, pg_temp (pg_temp LAST) and qualifies
-- relations as public.<table>.
-- Per cq-supabase-migration-no-concurrently: no CREATE INDEX CONCURRENTLY.

CREATE OR REPLACE FUNCTION public.precheck_jwt_mint(
  p_founder_id uuid,
  p_ttl_sec    int DEFAULT 600
) RETURNS TABLE(jti uuid, exp_epoch int, iat_epoch int)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_now          timestamptz := now();
  v_window_start timestamptz;
  v_count        int;
BEGIN
  -- Atomic rate-limit increment under the row's lock (mirrors migration 037).
  INSERT INTO public.mint_rate_window AS m (founder_id, window_start, mints_count)
  VALUES (p_founder_id, v_now, 1)
  ON CONFLICT (founder_id) DO UPDATE
    SET window_start = CASE
          WHEN m.window_start < v_now - interval '1 hour' THEN v_now
          ELSE m.window_start
        END,
        mints_count  = CASE
          WHEN m.window_start < v_now - interval '1 hour' THEN 1
          ELSE m.mints_count + 1
        END
  RETURNING m.window_start, m.mints_count INTO v_window_start, v_count;

  IF v_count > 60 THEN
    -- ERRCODE '45001' (user-defined class). MESSAGE preserved from
    -- migration 037 for callers that string-match. New consumers
    -- (migration 047 runtime_jwt_mint_hook) MUST rely on the SQLSTATE
    -- value, not the message — see plan §1.6 and ADR-033 §0.4.
    RAISE EXCEPTION 'mint_rate_exceeded' USING ERRCODE = '45001';
  END IF;

  RETURN QUERY SELECT
    gen_random_uuid()                                                 AS jti,
    EXTRACT(epoch FROM (v_now + (p_ttl_sec || ' seconds')::interval))::int AS exp_epoch,
    EXTRACT(epoch FROM v_now)::int                                    AS iat_epoch;
END;
$$;

-- Grants unchanged from migration 037 (service_role only, plus the hook
-- caller). REVOKE re-applied defensively in case prior grants were widened.
REVOKE ALL ON FUNCTION public.precheck_jwt_mint(uuid, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.precheck_jwt_mint(uuid, int) TO service_role;
-- The hook (migration 047) runs SECURITY DEFINER as the function's owner
-- (postgres superuser), so it can call precheck_jwt_mint regardless of the
-- caller's grants. No supabase_auth_admin grant needed on precheck.

COMMENT ON FUNCTION public.precheck_jwt_mint(uuid, int) IS
  'Atomic rate-limit gate + jti supplier for runtime JWT minting. '
  'Returns (jti, exp_epoch, iat_epoch). Rate-limit raise uses ERRCODE '
  '''45001'' (#3363 Resolution C, migration 048) to disambiguate from '
  'migration 037''s WORM-trigger P0001 raises. Called by the Custom '
  'Access Token Hook (public.runtime_jwt_mint_hook, migration 047), '
  'NOT directly from Node post-#3363.';

-- Compile probe: re-resolve the function and check the new ERRCODE
-- shows up in the body. The behavioral 61-call SQLSTATE assertion lives
-- in the integration block of
-- test/supabase-migrations/048-precheck-jwt-mint-sqlstate.test.ts and
-- runs against a real auth.users fixture post-apply (an inline DO block
-- here would require a hard-coded founder_id, which is environment-
-- coupled since mint_rate_window.founder_id has a FK to auth.users.id).
DO $$
DECLARE
  v_body text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_body
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'precheck_jwt_mint'
    AND pg_get_function_arguments(p.oid) = 'p_founder_id uuid, p_ttl_sec integer DEFAULT 600';
  IF v_body IS NULL THEN
    RAISE EXCEPTION 'migration 048 self-test FAILED: precheck_jwt_mint(uuid, int) not found post-apply';
  END IF;
  IF v_body NOT LIKE '%45001%' THEN
    RAISE EXCEPTION 'migration 048 self-test FAILED: ERRCODE 45001 not present in resolved function body';
  END IF;
END;
$$;
