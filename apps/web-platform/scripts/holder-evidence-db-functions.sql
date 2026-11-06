-- Privilege potential only: function bodies and application rows are excluded.
-- The consuming collector must apply read-only, deadline and 10,000-row caps.
SELECT row_to_json(q)::text
FROM (
  SELECT r.oid::bigint AS role_oid, r.rolname AS role_name, n.oid::bigint AS schema_oid, n.nspname AS schema_name, p.oid::bigint AS function_oid, p.proname AS function_name,
         p.proowner::bigint AS owner_oid, pg_catalog.pg_get_userbyid(p.proowner) AS owner, p.prokind,
         p.prosecdef AS security_definer,
         pg_catalog.has_schema_privilege(r.oid, n.oid, 'USAGE') AS schema_usage,
         pg_catalog.has_function_privilege(r.oid, p.oid, 'EXECUTE') AS can_execute
  FROM pg_catalog.pg_roles r
  CROSS JOIN pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' AND p.prokind IN ('f', 'p')
  ORDER BY r.rolname, p.oid
  LIMIT 10001
) q;
