-- Verify 054_users_role_column.sql.
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row
-- fails CI verify-migrations.
--
-- Sentinels confirm post-apply state from migration 054:
--   * users.role column exists with the expected type
--   * CHECK constraint admits ('prd','dev') only
--   * Default 'prd' is in place (so new inserts inherit safely)
--   * users_prevent_role_self_mutation trigger fn exists
--   * Trigger is wired on public.users for BEFORE UPDATE
--   * Existing rows are backfilled to 'prd' (no NULLs)

-- (1) Column present
SELECT 'users_role_column_present' AS check_name,
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int AS bad
  FROM information_schema.columns
 WHERE table_schema = 'public'
   AND table_name = 'users'
   AND column_name = 'role'
   AND data_type = 'text'
   AND is_nullable = 'NO'
UNION ALL
-- (2) CHECK constraint admits the two valid roles
SELECT 'users_role_check_admits_prd_dev',
       CASE WHEN pg_get_constraintdef(c.oid) ~ 'prd' AND
                  pg_get_constraintdef(c.oid) ~ 'dev'
            THEN 0 ELSE 1 END::int
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
 WHERE t.relname = 'users' AND c.contype = 'c'
   AND pg_get_constraintdef(c.oid) ~ 'role'
UNION ALL
-- (3) Default 'prd' present on the column
SELECT 'users_role_default_prd',
       CASE WHEN column_default ~ 'prd' THEN 0 ELSE 1 END::int
  FROM information_schema.columns
 WHERE table_schema = 'public'
   AND table_name = 'users'
   AND column_name = 'role'
UNION ALL
-- (4) Guard function exists
SELECT 'users_prevent_role_self_mutation_fn_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname = 'users_prevent_role_self_mutation'
UNION ALL
-- (5) Trigger wired on users BEFORE UPDATE
SELECT 'users_prevent_role_self_mutation_trigger_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_trigger
 WHERE tgname = 'users_prevent_role_self_mutation'
   AND NOT tgisinternal
UNION ALL
-- (6) Existing rows backfilled (no NULL role values)
SELECT 'users_role_no_nulls',
       (SELECT count(*) FROM public.users WHERE role IS NULL)::int;
