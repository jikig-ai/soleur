-- Role flags and OIDs only; names, passwords and settings are omitted.
SELECT pg_catalog.row_to_json(q)::text FROM (
  SELECT 'role' AS kind,oid::bigint AS role_oid,rolcanlogin AS can_login,
         rolsuper AS superuser,rolbypassrls AS bypass_rls,
         rolinherit AS inherits_by_default,rolcreaterole AS can_create_role,
         rolcreatedb AS can_create_database,rolreplication AS replication
  FROM pg_catalog.pg_roles ORDER BY oid LIMIT 10001
) q;
