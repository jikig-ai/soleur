-- Direct schema and current-database ACLs, including PUBLIC and defaults.
-- Callers must enforce read-only execution, timeout, and the row cap.
SELECT row_to_json(q)::text FROM (
  SELECT 'control_acl' AS kind, 'schema' AS scope, n.oid::bigint AS object_oid, n.nspname AS object_name,
         n.nspowner::bigint AS owner_oid, pg_catalog.pg_get_userbyid(n.nspowner) AS owner,
         acl.grantee::bigint AS grantee_oid, acl.grantor::bigint AS grantor_oid,
         CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(acl.grantee) END AS grantee,
         pg_catalog.pg_get_userbyid(acl.grantor) AS grantor,
         acl.privilege_type AS privilege, acl.is_grantable AS grantable
  FROM pg_catalog.pg_namespace n
  CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(n.nspacl, pg_catalog.acldefault('n', n.nspowner))) acl
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
  UNION ALL
  SELECT 'control_acl', 'database', d.oid::bigint, d.datname, d.datdba::bigint, pg_catalog.pg_get_userbyid(d.datdba), acl.grantee::bigint, acl.grantor::bigint,
         CASE WHEN acl.grantee = 0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(acl.grantee) END,
         pg_catalog.pg_get_userbyid(acl.grantor), acl.privilege_type, acl.is_grantable
  FROM pg_catalog.pg_database d
  CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(d.datacl, pg_catalog.acldefault('d', d.datdba))) acl
  WHERE d.datname = current_database()
  ORDER BY scope, object_name, grantee, privilege
  LIMIT 10001
) q;
