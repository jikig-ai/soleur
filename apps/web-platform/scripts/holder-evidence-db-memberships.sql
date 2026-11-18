-- Direct membership edges and effective SET/USAGE: no role is switched here.
-- The consuming collector must apply read-only, deadline and 10,000-row caps.
SELECT row_to_json(q)::text
FROM (
  SELECT member.oid::bigint AS member_oid, parent.oid::bigint AS role_oid, grantor.oid::bigint AS grantor_oid,
         member.rolname AS member_name, parent.rolname AS role_name,
         grantor.rolname AS grantor_name,
         m.admin_option, m.inherit_option, m.set_option,
         pg_catalog.pg_has_role(member.oid, parent.oid, 'USAGE') AS inherits_privileges,
         pg_catalog.pg_has_role(member.oid, parent.oid, 'SET') AS can_set_role
  FROM pg_catalog.pg_auth_members m
  JOIN pg_catalog.pg_roles member ON member.oid = m.member
  JOIN pg_catalog.pg_roles parent ON parent.oid = m.roleid
  JOIN pg_catalog.pg_roles grantor ON grantor.oid = m.grantor
  ORDER BY member.rolname, parent.rolname, grantor.rolname
  LIMIT 10001
) q;
