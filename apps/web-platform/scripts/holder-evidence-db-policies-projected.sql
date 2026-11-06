-- Filtered policy metadata only. Names and expressions are not returned.
-- A policy's effect and the completeness of this walk remain unknown.
SELECT pg_catalog.row_to_json(q)::text FROM (
  SELECT 'policy' AS kind, p.oid::bigint AS policy_oid, n.oid::bigint AS schema_oid,
         c.oid::bigint AS relation_oid, p.polcmd AS command, p.polpermissive AS permissive,
         ARRAY(SELECT role_oid::bigint FROM pg_catalog.unnest(p.polroles) role_oid ORDER BY role_oid) AS role_oids,
         p.polqual IS NOT NULL AS has_using, p.polwithcheck IS NOT NULL AS has_check,
         'unknown' AS policy_effect
  FROM pg_catalog.pg_policy p
  JOIN pg_catalog.pg_class c ON c.oid=p.polrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
  ORDER BY p.oid
  LIMIT 10001
) q;
