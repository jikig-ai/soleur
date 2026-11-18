-- Independent role roster, including roles with no visible public relations.
-- No password hashes or connection settings are selected.
SELECT row_to_json(q)::text
FROM (
  SELECT 'role' AS kind, oid::bigint AS role_oid, rolname AS role_name, rolcanlogin AS can_login,
         rolsuper AS superuser, rolbypassrls AS bypass_rls,
         rolinherit AS inherits_by_default, rolcreaterole AS can_create_role,
         rolcreatedb AS can_create_database, rolreplication AS replication
  FROM pg_catalog.pg_roles
  ORDER BY rolname
  LIMIT 10001
) q;
