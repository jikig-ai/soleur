-- Filtered trigger metadata; names, arguments and function bodies omitted.
-- Trigger effect and coverage remain unknown.
SELECT pg_catalog.row_to_json(q)::text FROM (
  SELECT 'trigger' AS kind, t.oid::bigint AS trigger_oid, n.oid::bigint AS schema_oid,
         c.oid::bigint AS relation_oid, p.oid::bigint AS function_oid,
         p.proowner::bigint AS function_owner_oid, t.tgtype::integer AS trigger_type,
         t.tgenabled AS enabled, t.tgisinternal AS internal, p.prosecdef AS security_definer
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_catalog.pg_proc p ON p.oid=t.tgfoid
  WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema'
  ORDER BY t.oid
  LIMIT 10001
) q;
