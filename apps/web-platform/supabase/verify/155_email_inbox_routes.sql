-- Verify 155_email_inbox_routes.sql.
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row
-- fails CI verify-migrations.
--
-- Sentinels confirm post-apply state from migration 155 (ADR-269):
--   * the table exists with RLS enabled and ZERO policies
--   * anon/authenticated hold NO privilege on it (queried from the live
--     catalog, not from migration source)
--   * address is unique, and the shape CHECK exists
--   * the owner FK is the composite (workspace_id, owner_user_id) ->
--     workspace_members(workspace_id, user_id) with ON DELETE CASCADE, so a
--     non-member owner is rejected at write time and account/workspace
--     deletion is never blocked by a route

-- (1) table exists
SELECT 'email_inbox_routes_exists' AS check_name,
       CASE WHEN to_regclass('public.email_inbox_routes') IS NOT NULL
            THEN 0 ELSE 1 END::int AS bad
UNION ALL
-- (2) RLS enabled
SELECT 'email_inbox_routes_rls_enabled',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_class c
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relname = 'email_inbox_routes'
           AND c.relrowsecurity
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (3) zero policies (service-role only)
SELECT 'email_inbox_routes_no_policies',
       (SELECT count(*) FROM pg_policy p
        JOIN pg_class c ON c.oid = p.polrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname = 'email_inbox_routes')::int
UNION ALL
-- (4) no client-role privileges of any kind
SELECT 'email_inbox_routes_no_client_privileges',
       (SELECT count(*) FROM (
          VALUES ('anon'), ('authenticated')
        ) AS r(role_name)
        CROSS JOIN (
          VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
                 ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')
        ) AS p(priv)
        WHERE to_regclass('public.email_inbox_routes') IS NOT NULL
          AND has_table_privilege(
                r.role_name, 'public.email_inbox_routes', p.priv))::int
UNION ALL
-- (5) address uniqueness
SELECT 'email_inbox_routes_address_unique_index',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_indexes
         WHERE schemaname = 'public'
           AND tablename = 'email_inbox_routes'
           AND indexname = 'email_inbox_routes_address_key'
           AND indexdef LIKE 'CREATE UNIQUE INDEX%'
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (6) address shape CHECK present
SELECT 'email_inbox_routes_address_shape_check',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_constraint
         WHERE conrelid = 'public.email_inbox_routes'::regclass
           AND conname = 'email_inbox_routes_address_shape'
           AND contype = 'c'
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (7) composite owner FK -> workspace_members, ON DELETE CASCADE
SELECT 'email_inbox_routes_owner_member_fk_cascade',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_constraint
         WHERE conrelid = 'public.email_inbox_routes'::regclass
           AND conname = 'email_inbox_routes_owner_member_fk'
           AND contype = 'f'
           AND confrelid = 'public.workspace_members'::regclass
           AND confdeltype = 'c'
           AND array_length(conkey, 1) = 2
       ) THEN 0 ELSE 1 END::int;
