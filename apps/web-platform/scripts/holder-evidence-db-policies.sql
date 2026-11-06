-- Policy metadata only: expressions are excluded and effects remain unknown.
SELECT row_to_json(q)::text FROM (
  SELECT 'policy' AS kind, n.oid::bigint AS schema_oid, n.nspname AS schema_name, c.oid::bigint AS relation_oid, c.relname AS relation,
         p.polname AS policy_name, p.polcmd AS command, p.polpermissive AS permissive,
         ARRAY(SELECT CASE WHEN role_oid = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(role_oid) END
               FROM unnest(p.polroles) role_oid ORDER BY role_oid) AS roles,
         ARRAY(SELECT role_oid::bigint FROM unnest(p.polroles) role_oid ORDER BY role_oid) AS role_oids,
         p.polqual IS NOT NULL AS has_using, p.polwithcheck IS NOT NULL AS has_check,
         'unknown' AS policy_effect
  FROM pg_catalog.pg_policy p
  JOIN pg_catalog.pg_class c ON c.oid = p.polrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
  ORDER BY n.nspname, c.relname, p.polname
  LIMIT 10001
) q;
