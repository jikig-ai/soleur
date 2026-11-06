-- Direct schema and current-database ACL entries, including PUBLIC.
-- OIDs and flags only; this is not an effective-access census.
SELECT pg_catalog.row_to_json(q)::text FROM (
  SELECT 'control_acl' AS kind, 'schema' AS scope, n.oid::bigint AS object_oid,
         n.nspowner::bigint AS owner_oid, acl.grantee::bigint AS grantee_oid,
         acl.grantor::bigint AS grantor_oid, acl.privilege_type AS privilege, acl.is_grantable AS grantable
  FROM pg_catalog.pg_namespace n
  CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(n.nspacl,pg_catalog.acldefault('n',n.nspowner))) acl
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
  UNION ALL
  SELECT 'control_acl','database',d.oid::bigint,d.datdba::bigint,acl.grantee::bigint,acl.grantor::bigint,acl.privilege_type,acl.is_grantable
  FROM pg_catalog.pg_database d
  CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(d.datacl,pg_catalog.acldefault('d',d.datdba))) acl
  WHERE d.datname=pg_catalog.current_database()
  ORDER BY scope,object_oid,grantee_oid,grantor_oid,privilege
  LIMIT 10001
) q;
