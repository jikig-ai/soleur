-- Direct sequence ACLs, including PUBLIC and defaults; no names returned.
SELECT pg_catalog.row_to_json(q)::text FROM (
  SELECT 'sequence_acl' AS kind,n.oid::bigint AS schema_oid,c.oid::bigint AS sequence_oid,
         c.relowner::bigint AS owner_oid,acl.grantee::bigint AS grantee_oid,
         acl.grantor::bigint AS grantor_oid,acl.privilege_type AS privilege,acl.is_grantable AS grantable
  FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('S',c.relowner))) acl
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' AND c.relkind='S'
  ORDER BY c.oid,acl.grantee,acl.grantor,acl.privilege_type LIMIT 10001
) q;
