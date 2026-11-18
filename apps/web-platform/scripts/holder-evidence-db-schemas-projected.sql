-- Filtered privilege observations only; role and schema names are omitted.
-- Completeness, effective reachability and writer clearance remain unknown.
SELECT row_to_json(q)::text FROM (
  SELECT 'schema_privilege' AS kind, r.oid::bigint AS role_oid,
         n.oid::bigint AS schema_oid, n.nspowner::bigint AS owner_oid,
         pg_catalog.has_schema_privilege(r.oid, n.oid, 'USAGE') AS schema_usage,
         pg_catalog.has_schema_privilege(r.oid, n.oid, 'CREATE') AS schema_create,
         pg_catalog.has_database_privilege(r.oid, d.oid, 'CONNECT') AS database_connect,
         pg_catalog.has_database_privilege(r.oid, d.oid, 'CREATE') AS database_create,
         pg_catalog.has_database_privilege(r.oid, d.oid, 'TEMPORARY') AS database_temporary
  FROM pg_catalog.pg_roles r
  CROSS JOIN pg_catalog.pg_namespace n
  CROSS JOIN pg_catalog.pg_database d
  WHERE d.datname = pg_catalog.current_database() AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
  ORDER BY r.oid, n.oid
  LIMIT 10001
) q;
