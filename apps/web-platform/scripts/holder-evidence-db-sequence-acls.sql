-- Direct sequence ACLs include PUBLIC and default owner privileges. The
-- caller must enforce read-only execution, a deadline and the row cap.
SELECT row_to_json(q)::text FROM (
  SELECT 'sequence_acl' AS kind, n.oid::bigint AS schema_oid, n.nspname AS schema_name,
         c.oid::bigint AS sequence_oid, c.relname AS sequence_name, c.relowner::bigint AS owner_oid, pg_catalog.pg_get_userbyid(c.relowner) AS owner,
         acl.grantee::bigint AS grantee_oid, acl.grantor::bigint AS grantor_oid,
         CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(acl.grantee) END AS grantee,
         pg_catalog.pg_get_userbyid(acl.grantor) AS grantor,
         acl.privilege_type AS privilege, acl.is_grantable AS grantable
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl, pg_catalog.acldefault('S', c.relowner))) acl
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema' AND c.relkind = 'S'
  ORDER BY n.nspname, c.relname, grantee, privilege
  LIMIT 10001
) q;
