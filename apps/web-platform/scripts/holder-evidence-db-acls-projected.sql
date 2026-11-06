-- Direct relation/column ACLs, including PUBLIC; names are omitted.
-- This is a filtered query walk, not an effective-writer census.
SELECT pg_catalog.row_to_json(q)::text FROM (
  SELECT 'relation_acl' AS kind, 'table' AS scope, n.oid::bigint AS schema_oid,
         c.oid::bigint AS relation_oid, NULL::integer AS column_number,
         acl.grantee::bigint AS grantee_oid, acl.grantor::bigint AS grantor_oid,
         acl.privilege_type AS privilege, acl.is_grantable AS grantable
  FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) acl
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' AND c.relkind IN ('r','p','v','m','f')
  UNION ALL
  SELECT 'relation_acl','column',n.oid::bigint,c.oid::bigint,a.attnum::integer,
         acl.grantee::bigint,acl.grantor::bigint,acl.privilege_type,acl.is_grantable
  FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
  CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) acl
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' AND c.relkind IN ('r','p','v','m','f')
  ORDER BY relation_oid,scope,column_number,grantee_oid,grantor_oid,privilege
  LIMIT 10001
) q;
