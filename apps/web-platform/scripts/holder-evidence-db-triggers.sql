-- Trigger identities and activation metadata only: never function bodies or args.
SELECT row_to_json(q)::text FROM (
  SELECT 'trigger' AS kind, n.oid::bigint AS schema_oid, n.nspname AS schema_name, c.oid::bigint AS relation_oid, c.relname AS relation,
         t.tgname AS trigger_name, t.tgenabled AS enabled, t.tgisinternal AS internal,
         p.oid::bigint AS function_oid, p.proname AS function_name,
         pn.nspname AS function_schema, p.proowner::bigint AS function_owner_oid, pg_catalog.pg_get_userbyid(p.proowner) AS function_owner,
         p.prosecdef AS security_definer
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_catalog.pg_proc p ON p.oid = t.tgfoid
  JOIN pg_catalog.pg_namespace pn ON pn.oid = p.pronamespace
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
  ORDER BY n.nspname, c.relname, t.tgname
  LIMIT 10001
) q;
