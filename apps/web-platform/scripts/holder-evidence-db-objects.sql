-- Two independent SELECT arms: sequence privileges and materialized-view
-- maintenance privileges. The eventual runner must track each arm separately.
SELECT row_to_json(q)::text FROM (
  SELECT 'sequence_privilege' AS kind, r.oid::bigint AS role_oid, r.rolname AS role_name, n.oid::bigint AS schema_oid, n.nspname AS schema_name, c.oid::bigint AS object_oid,
         c.relname AS object_name, c.relowner::bigint AS owner_oid, pg_catalog.pg_get_userbyid(c.relowner) AS owner,
         pg_catalog.has_schema_privilege(r.oid, n.oid, 'USAGE') AS schema_usage,
         pg_catalog.has_sequence_privilege(r.oid, c.oid, 'USAGE') AS can_usage,
         pg_catalog.has_sequence_privilege(r.oid, c.oid, 'SELECT') AS can_select,
         pg_catalog.has_sequence_privilege(r.oid, c.oid, 'UPDATE') AS can_update
  FROM pg_catalog.pg_roles r CROSS JOIN pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' AND c.relkind = 'S'
  ORDER BY r.rolname, n.nspname, c.relname
  LIMIT 10001
) q;

SELECT row_to_json(q)::text FROM (
  SELECT 'materialized_view_privilege' AS kind, r.oid::bigint AS role_oid, r.rolname AS role_name, n.oid::bigint AS schema_oid, n.nspname AS schema_name, c.oid::bigint AS object_oid,
         c.relname AS object_name, c.relowner::bigint AS owner_oid, pg_catalog.pg_get_userbyid(c.relowner) AS owner,
         pg_catalog.has_schema_privilege(r.oid, n.oid, 'USAGE') AS schema_usage,
         pg_catalog.has_table_privilege(r.oid, c.oid, 'MAINTAIN') AS can_maintain
  FROM pg_catalog.pg_roles r CROSS JOIN pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' AND c.relkind = 'm'
  ORDER BY r.rolname, n.nspname, c.relname
  LIMIT 10001
) q;
