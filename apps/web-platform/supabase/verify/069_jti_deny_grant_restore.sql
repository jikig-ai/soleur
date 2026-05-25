-- Verify 069_jti_deny_grant_restore.sql.
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row
-- fails CI verify-migrations.
--
-- Sentinels confirm post-apply state from migration 069:
--   * is_jti_denied(uuid) does NOT have EXECUTE granted to authenticated.
--   * is_jti_denied(uuid) does NOT have EXECUTE granted to anon / PUBLIC.
--   * is_jti_denied(uuid) STILL has EXECUTE granted to service_role
--     (otherwise the SECURITY DEFINER wrapper itself cannot call it).
--   * is_jti_denied_from_jwt() STILL has EXECUTE granted to authenticated
--     (regression guard — the wrapper is the only path that should be
--     callable by authenticated; if mig 069 accidentally revoked from
--     the wrapper too, EVERY authenticated PostgREST query would 42501).

-- (1) is_jti_denied(uuid): authenticated does NOT have EXECUTE
SELECT 'is_jti_denied_authenticated_revoked' AS check_name,
       CASE WHEN has_function_privilege(
              'authenticated',
              'public.is_jti_denied(uuid)',
              'EXECUTE'
            ) THEN 1 ELSE 0 END::int AS bad
UNION ALL
-- (2) is_jti_denied(uuid): anon does NOT have EXECUTE
SELECT 'is_jti_denied_anon_revoked',
       CASE WHEN has_function_privilege(
              'anon',
              'public.is_jti_denied(uuid)',
              'EXECUTE'
            ) THEN 1 ELSE 0 END::int
UNION ALL
-- (3) is_jti_denied(uuid): service_role still has EXECUTE (load-bearing
--     for the SECURITY DEFINER wrapper's transitive call).
SELECT 'is_jti_denied_service_role_grant_present',
       CASE WHEN has_function_privilege(
              'service_role',
              'public.is_jti_denied(uuid)',
              'EXECUTE'
            ) THEN 0 ELSE 1 END::int
UNION ALL
-- (4) is_jti_denied_from_jwt() STILL has EXECUTE granted to authenticated
--     (regression guard — mig 068 line 159).
SELECT 'is_jti_denied_from_jwt_authenticated_grant_present',
       CASE WHEN has_function_privilege(
              'authenticated',
              'public.is_jti_denied_from_jwt()',
              'EXECUTE'
            ) THEN 0 ELSE 1 END::int;
