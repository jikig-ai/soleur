-- Effective schema and current-database capabilities, including inheritance
-- and PUBLIC. Cap, visibility and failure handling belong to the caller.
SELECT row_to_json(q)::text FROM (
  SELECT 'schema_privilege' AS kind, r.oid::bigint AS role_oid, r.rolname AS role_name,
         n.oid::bigint AS schema_oid, n.nspname AS schema_name, n.nspowner::bigint AS owner_oid, pg_catalog.pg_get_userbyid(n.nspowner) AS schema_owner,
         pg_catalog.has_schema_privilege(r.oid, n.oid, 'USAGE') AS schema_usage,
         pg_catalog.has_schema_privilege(r.oid, n.oid, 'CREATE') AS schema_create,
         pg_catalog.has_database_privilege(r.oid, d.oid, 'CONNECT') AS database_connect,
         pg_catalog.has_database_privilege(r.oid, d.oid, 'CREATE') AS database_create,
         pg_catalog.has_database_privilege(r.oid, d.oid, 'TEMPORARY') AS database_temporary
  FROM pg_catalog.pg_roles r
  CROSS JOIN pg_catalog.pg_namespace n
  CROSS JOIN pg_catalog.pg_database d
  WHERE d.datname = current_database() AND n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
  ORDER BY r.rolname, n.nspname
  LIMIT 10001
) q;
