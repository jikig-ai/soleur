-- Filtered effective sequence privilege observations; no names returned.
SELECT pg_catalog.row_to_json(q)::text FROM (
  SELECT 'sequence_privilege' AS kind,r.oid::bigint AS role_oid,n.oid::bigint AS schema_oid,
         c.oid::bigint AS object_oid,c.relowner::bigint AS owner_oid,
         pg_catalog.has_schema_privilege(r.oid,n.oid,'USAGE') AS schema_usage,
         pg_catalog.has_sequence_privilege(r.oid,c.oid,'USAGE') AS can_usage,
         pg_catalog.has_sequence_privilege(r.oid,c.oid,'SELECT') AS can_select,
         pg_catalog.has_sequence_privilege(r.oid,c.oid,'UPDATE') AS can_update
  FROM pg_catalog.pg_roles r CROSS JOIN pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' AND c.relkind='S'
  ORDER BY r.oid,c.oid LIMIT 10001
) q;
