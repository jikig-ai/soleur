-- Verify 102_email_triage_items.sql.
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row
-- fails CI verify-migrations.
--
-- Sentinels confirm post-apply state from migration 102
-- (feat-operator-inbox-delegation Phase 1):
--   * email_triage_items exists with RLS enabled and NO INSERT/UPDATE/DELETE
--     policies (writes are service-role pipeline + SECURITY DEFINER RPCs only;
--     learning 2026-05-21 — an owner-write policy beside RPCs is a bypass path)
--   * purge_email_triage_items + anonymise_email_triage_items are NOT
--     EXECUTE-able by `authenticated` (service_role-only bulk-mutation RPCs;
--     learning security-issues/2026-06-01)
--   * set_email_triage_status IS EXECUTE-able by `authenticated` but NOT anon
--   * the WORM triggers are attached
--   * processed_resend_events retention cron is scheduled

-- (1) email_triage_items exists with RLS enabled
SELECT 'email_triage_items_rls_enabled' AS check_name,
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_class c
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relname = 'email_triage_items'
           AND c.relrowsecurity
       ) THEN 0 ELSE 1 END::int AS bad
UNION ALL
-- (2) no INSERT/UPDATE/DELETE policies on email_triage_items
SELECT 'email_triage_items_no_write_policies',
       (SELECT count(*) FROM pg_policy p
        JOIN pg_class c ON c.oid = p.polrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname = 'email_triage_items'
          AND p.polcmd IN ('a', 'w', 'd'))::int
UNION ALL
-- (3) purge_email_triage_items NOT executable by authenticated
SELECT 'purge_email_triage_items_not_granted_to_authenticated',
       CASE WHEN has_function_privilege(
         'authenticated',
         'public.purge_email_triage_items()',
         'EXECUTE'
       ) THEN 1 ELSE 0 END::int
UNION ALL
-- (4) anonymise_email_triage_items NOT executable by authenticated
SELECT 'anonymise_email_triage_items_not_granted_to_authenticated',
       CASE WHEN has_function_privilege(
         'authenticated',
         'public.anonymise_email_triage_items(uuid)',
         'EXECUTE'
       ) THEN 1 ELSE 0 END::int
UNION ALL
-- (5) set_email_triage_status IS executable by authenticated
SELECT 'set_email_triage_status_granted_to_authenticated',
       CASE WHEN has_function_privilege(
         'authenticated',
         'public.set_email_triage_status(uuid, text)',
         'EXECUTE'
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (6) set_email_triage_status NOT executable by anon
SELECT 'set_email_triage_status_not_granted_to_anon',
       CASE WHEN has_function_privilege(
         'anon',
         'public.set_email_triage_status(uuid, text)',
         'EXECUTE'
       ) THEN 1 ELSE 0 END::int
UNION ALL
-- (7) both WORM triggers attached
SELECT 'email_triage_items_worm_triggers_attached',
       CASE WHEN (
         SELECT count(*) FROM pg_trigger t
         JOIN pg_class c ON c.oid = t.tgrelid
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relname = 'email_triage_items'
           AND t.tgname IN ('email_triage_items_no_update', 'email_triage_items_no_delete')
           AND NOT t.tgisinternal
       ) = 2 THEN 0 ELSE 1 END::int
UNION ALL
-- (8) processed_resend_events retention cron scheduled
SELECT 'processed_resend_events_retention_cron_scheduled',
       CASE WHEN EXISTS (
         SELECT 1 FROM cron.job
         WHERE jobname = 'processed_resend_events_retention'
       ) THEN 0 ELSE 1 END::int;
