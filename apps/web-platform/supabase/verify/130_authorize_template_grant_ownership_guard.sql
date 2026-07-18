-- Verify 130_authorize_template_grant_ownership_guard.sql (#6336).
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row fails CI
-- verify-migrations (run-verify.sh parses tab-separated (check_name TEXT, bad INT)
-- rows under ON_ERROR_STOP=1).
--
-- FAIL-CLOSED (verify/116 idiom): each check is a `CASE WHEN count(*)=1` aggregate
-- that always emits exactly one row, so a regressed/dropped function yields
-- `bad=1` rather than a vanished zero-row false-green.
--
-- SCOPED to proname='authorize_template' + the (text, text, uuid) signature: the
-- fragment `founder_id = v_founder_id` also appears in revoke_template_authorization
-- (053:359 / 089:158) and grant_action_class / revoke_action_class (048:157,195),
-- so an unscoped prosrc match would false-green on a sibling body.

-- (1) the ownership guard is present in the body (scope_grants ownership re-check)
SELECT 'authorize_template_grant_ownership_guard' AS check_name,
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int AS bad
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'authorize_template'
   AND pg_catalog.oidvectortypes(p.proargtypes) = 'text, text, uuid'
   AND p.prosrc ILIKE '%scope_grants%founder_id = v_founder_id%'
UNION ALL
-- (2) still SECURITY DEFINER (cq-pg-security-definer-search-path-pin-pg-temp)
SELECT 'authorize_template_security_definer',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'authorize_template'
   AND pg_catalog.oidvectortypes(p.proargtypes) = 'text, text, uuid'
   AND p.prosecdef = true
UNION ALL
-- (3) search_path pin retained (= public, pg_temp)
SELECT 'authorize_template_search_path_pinned',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'authorize_template'
   AND pg_catalog.oidvectortypes(p.proargtypes) = 'text, text, uuid'
   AND EXISTS (
     SELECT 1 FROM unnest(p.proconfig) AS cfg
      WHERE cfg ILIKE 'search_path=%pg_temp%'
   )
UNION ALL
-- (4) authenticated retains EXECUTE (the legit first-send path must keep working;
--     a DROP+CREATE down/regression would sever this grant)
SELECT 'authorize_template_authenticated_execute',
       CASE WHEN has_function_privilege('authenticated', 'public.authorize_template(text, text, uuid)', 'EXECUTE') THEN 0 ELSE 1 END::int;
