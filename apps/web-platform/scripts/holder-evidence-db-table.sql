-- Read-only prototype. The consuming collector must enforce a read-only
-- transaction, a deadline, per-arm error states and the 10,000-row cap.
-- Effective privileges include inheritance and PUBLIC; RLS and schema usage
-- are separate facts and must not be interpreted as a usable write route.
SELECT row_to_json(q)::text
FROM (
  SELECT r.oid::bigint AS role_oid, r.rolname AS role_name, r.rolcanlogin, r.rolsuper, r.rolbypassrls,
         n.oid::bigint AS schema_oid, n.nspname AS schema_name, c.oid::bigint AS relation_oid, c.relname AS relation, c.relkind, c.relowner::bigint AS owner_oid, pg_get_userbyid(c.relowner) AS owner,
         c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS rls_forced,
         has_schema_privilege(r.oid, n.oid, 'USAGE') AS schema_usage,
         has_table_privilege(r.oid, c.oid, 'INSERT') AS can_insert,
         has_table_privilege(r.oid, c.oid, 'UPDATE') AS can_update_table,
         has_table_privilege(r.oid, c.oid, 'DELETE') AS can_delete,
         has_table_privilege(r.oid, c.oid, 'TRUNCATE') AS can_truncate,
         ARRAY(SELECT a.attname FROM pg_catalog.pg_attribute a
               WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
                 AND has_column_privilege(r.oid, c.oid, a.attnum, 'INSERT')
               ORDER BY a.attname) AS insertable_columns,
         ARRAY(SELECT a.attname FROM pg_catalog.pg_attribute a
               WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
                 AND has_column_privilege(r.oid, c.oid, a.attnum, 'UPDATE')
               ORDER BY a.attname) AS updatable_columns
  FROM pg_catalog.pg_roles r
  CROSS JOIN pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' AND c.relkind IN ('r', 'p', 'v', 'f')
  ORDER BY r.rolname, n.nspname, c.relname
  LIMIT 10001
) q;
