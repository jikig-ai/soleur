-- Verify 144_pending_checkout_sessions.sql (#8918).
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row fails CI
-- verify-migrations (run-verify.sh parses tab-separated (check_name TEXT,
-- bad INT) rows under ON_ERROR_STOP=1).
--
-- WHY THIS FILE EXISTS. The money-path claim table's safety properties are
-- the ones a silent in-place edit would void: an `IF NOT EXISTS` no-op that
-- leaves RLS disabled or the CASCADE FK absent changes the table's security
-- and Art. 17 posture without failing the apply. Only this file observes the
-- live post-apply state.

-- (1) Table exists with RLS enabled (service-role-only posture: enabled +
--     zero policies, not merely "table present").
SELECT 'rls_enabled' AS check_name,
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_class
               WHERE relname = 'pending_checkout_sessions'
                 AND relnamespace = 'public'::regnamespace
                 AND relrowsecurity)
            THEN 0 ELSE 1 END::int AS bad
UNION ALL

-- (2) Zero RLS policies — the table is reachable only via service-role.
SELECT 'zero_rls_policies' AS check_name,
       (SELECT COUNT(*)::int FROM pg_policies
         WHERE schemaname = 'public' AND tablename = 'pending_checkout_sessions') AS bad
UNION ALL

-- (3) users FK carries ON DELETE CASCADE (Art. 17 erasure path).
SELECT 'users_fk_cascade' AS check_name,
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_constraint
               WHERE conrelid = 'public.pending_checkout_sessions'::regclass
                 AND contype = 'f'
                 AND confdeltype = 'c'
                 AND confrelid = 'public.users'::regclass)
            THEN 0 ELSE 1 END::int
UNION ALL

-- (4) Retention cron is scheduled (stranded-marker bound).
SELECT 'retention_cron_scheduled' AS check_name,
       CASE WHEN EXISTS (
              SELECT 1 FROM cron.job
               WHERE jobname = 'pending_checkout_sessions_retention')
            THEN 0 ELSE 1 END::int;
