-- Filtered materialized-view maintenance observations; no names returned.
SELECT pg_catalog.row_to_json(q)::text FROM (
  SELECT 'materialized_view_privilege' AS kind,r.oid::bigint AS role_oid,n.oid::bigint AS schema_oid,
         c.oid::bigint AS object_oid,c.relowner::bigint AS owner_oid,
         pg_catalog.has_schema_privilege(r.oid,n.oid,'USAGE') AS schema_usage,
         pg_catalog.has_table_privilege(r.oid,c.oid,'MAINTAIN') AS can_maintain
  FROM pg_catalog.pg_roles r CROSS JOIN pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' AND c.relkind='m'
  ORDER BY r.oid,c.oid LIMIT 10001
) q;
