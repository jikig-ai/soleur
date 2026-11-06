-- Filtered effective table/column observations. Names, application rows and
-- policy expressions are excluded; privileges alone do not prove a route.
SELECT row_to_json(q)::text FROM (
  SELECT r.oid::bigint AS role_oid, n.oid::bigint AS schema_oid,
         c.oid::bigint AS relation_oid, c.relkind, c.relowner::bigint AS owner_oid,
         c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS rls_forced,
         pg_catalog.has_schema_privilege(r.oid,n.oid,'USAGE') AS schema_usage,
         pg_catalog.has_table_privilege(r.oid,c.oid,'INSERT') AS can_insert,
         pg_catalog.has_table_privilege(r.oid,c.oid,'UPDATE') AS can_update_table,
         pg_catalog.has_table_privilege(r.oid,c.oid,'DELETE') AS can_delete,
         pg_catalog.has_table_privilege(r.oid,c.oid,'TRUNCATE') AS can_truncate,
         ARRAY(SELECT a.attnum::integer FROM pg_catalog.pg_attribute a
               WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
                 AND pg_catalog.has_column_privilege(r.oid,c.oid,a.attnum,'INSERT') ORDER BY a.attnum) AS insertable_column_numbers,
         ARRAY(SELECT a.attnum::integer FROM pg_catalog.pg_attribute a
               WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
                 AND pg_catalog.has_column_privilege(r.oid,c.oid,a.attnum,'UPDATE') ORDER BY a.attnum) AS updatable_column_numbers
  FROM pg_catalog.pg_roles r
  CROSS JOIN pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' AND c.relkind IN ('r','p','v','f')
  ORDER BY r.oid,c.oid
  LIMIT 10001
) q;
