-- Filtered effective function privileges; role and function names omitted.
-- Coverage, reachability and writer clearance remain unknown.
SELECT row_to_json(q)::text FROM (
  SELECT r.oid::bigint AS role_oid, n.oid::bigint AS schema_oid, p.oid::bigint AS function_oid,
         p.proowner::bigint AS owner_oid, p.prokind, p.prosecdef AS security_definer,
         pg_catalog.has_schema_privilege(r.oid, n.oid, 'USAGE') AS schema_usage,
         pg_catalog.has_function_privilege(r.oid, p.oid, 'EXECUTE') AS can_execute
  FROM pg_catalog.pg_roles r
  CROSS JOIN pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' AND p.prokind IN ('f', 'p')
  ORDER BY r.oid, p.oid
  LIMIT 10001
) q;
