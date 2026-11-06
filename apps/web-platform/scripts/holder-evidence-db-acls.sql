-- Direct ACL entries across non-system schemas, including PUBLIC and owner
-- defaults. The collector must independently enforce the cap and error state.
SELECT row_to_json(q)::text FROM (
  SELECT 'relation_acl' AS kind, 'table' AS scope, n.oid::bigint AS schema_oid, n.nspname AS schema_name,
         c.oid::bigint AS relation_oid, c.relname AS relation, NULL::name AS column_name,
         acl.grantee::bigint AS grantee_oid, acl.grantor::bigint AS grantor_oid,
         CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(acl.grantee) END AS grantee,
         pg_catalog.pg_get_userbyid(acl.grantor) AS grantor,
         acl.privilege_type AS privilege, acl.is_grantable AS grantable
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl, pg_catalog.acldefault('r', c.relowner))) acl
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
  UNION ALL
  SELECT 'relation_acl', 'column', n.oid::bigint, n.nspname, c.oid::bigint, c.relname, a.attname, acl.grantee::bigint, acl.grantor::bigint,
         CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(acl.grantee) END,
         pg_catalog.pg_get_userbyid(acl.grantor), acl.privilege_type, acl.is_grantable
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
  CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) acl
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
  ORDER BY schema_name, relation, scope, column_name, grantee, privilege
  LIMIT 10001
) q;
