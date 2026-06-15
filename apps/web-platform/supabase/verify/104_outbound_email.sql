-- Verify 104_outbound_email.sql.
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row
-- fails CI verify-migrations.
--
-- Sentinels confirm post-apply state from migration 104
-- (feat-agent-native-outbound-email Phase 1, #5325):
--   * email_suppression exists with RLS enabled and NO INSERT/UPDATE/DELETE
--     policies (writes go through the SECURITY DEFINER upsert RPC only; an
--     owner-write policy beside the RPC is a bypass path — learning
--     2026-05-21 / security-issues/2026-06-01)
--   * the UNIQUE(owner_id, recipient_hash) upsert target index exists
--   * suppress_recipient + is_recipient_suppressed ARE EXECUTE-able by
--     `authenticated` but NOT by `anon` (owner-pinned send-time RPCs)
--   * anonymise_email_suppression IS EXECUTE-able by `service_role`
--     (Art-17 erasure path; mirrors anonymise_action_sends)
--   * all three RPCs are SECURITY DEFINER
--
-- The send-audit + body-hash approval binding reuses action_sends (mig 051),
-- which has its own verify sentinel (verify/051_*.sql) — 104 makes no
-- action_sends/scope_grants change, so this file asserts only email_suppression.

-- (1) email_suppression exists with RLS enabled
SELECT 'email_suppression_rls_enabled' AS check_name,
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_class c
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relname = 'email_suppression'
           AND c.relrowsecurity
       ) THEN 0 ELSE 1 END::int AS bad
UNION ALL
-- (2) no INSERT/UPDATE/DELETE policies on email_suppression
SELECT 'email_suppression_no_write_policies',
       (SELECT count(*) FROM pg_policy p
        JOIN pg_class c ON c.oid = p.polrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname = 'email_suppression'
          AND p.polcmd IN ('a', 'w', 'd'))::int
UNION ALL
-- (3) owner-only SELECT policy present
SELECT 'email_suppression_owner_select_policy_present',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_policy p
         JOIN pg_class c ON c.oid = p.polrelid
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relname = 'email_suppression'
           AND p.polname = 'email_suppression_owner_select'
           AND p.polcmd = 'r'
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (4) UNIQUE(owner_id, recipient_hash) upsert-target index exists
SELECT 'email_suppression_owner_recipient_unique_index',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_class i
         JOIN pg_namespace n ON n.oid = i.relnamespace
         WHERE n.nspname = 'public'
           AND i.relname = 'email_suppression_owner_recipient_unique'
           AND i.relkind = 'i'
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (5) suppress_recipient IS executable by authenticated
SELECT 'suppress_recipient_granted_to_authenticated',
       CASE WHEN has_function_privilege(
         'authenticated',
         'public.suppress_recipient(text, text)',
         'EXECUTE'
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (6) suppress_recipient NOT executable by anon
SELECT 'suppress_recipient_not_granted_to_anon',
       CASE WHEN has_function_privilege(
         'anon',
         'public.suppress_recipient(text, text)',
         'EXECUTE'
       ) THEN 1 ELSE 0 END::int
UNION ALL
-- (7) is_recipient_suppressed IS executable by authenticated
SELECT 'is_recipient_suppressed_granted_to_authenticated',
       CASE WHEN has_function_privilege(
         'authenticated',
         'public.is_recipient_suppressed(text)',
         'EXECUTE'
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (8) is_recipient_suppressed NOT executable by anon
SELECT 'is_recipient_suppressed_not_granted_to_anon',
       CASE WHEN has_function_privilege(
         'anon',
         'public.is_recipient_suppressed(text)',
         'EXECUTE'
       ) THEN 1 ELSE 0 END::int
UNION ALL
-- (9) anonymise_email_suppression IS executable by service_role
SELECT 'anonymise_email_suppression_granted_to_service_role',
       CASE WHEN has_function_privilege(
         'service_role',
         'public.anonymise_email_suppression(uuid)',
         'EXECUTE'
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (10) all three suppression RPCs are SECURITY DEFINER (prosecdef)
SELECT 'email_suppression_rpcs_security_definer',
       CASE WHEN (
         SELECT count(*) FROM pg_proc p
         JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname IN ('suppress_recipient', 'is_recipient_suppressed', 'anonymise_email_suppression')
           AND p.prosecdef
       ) = 3 THEN 0 ELSE 1 END::int
UNION ALL
-- (11) outbound_sends exists with RLS enabled
SELECT 'outbound_sends_rls_enabled',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_class c
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND c.relname = 'outbound_sends' AND c.relrowsecurity
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (12) no INSERT/UPDATE/DELETE policies on outbound_sends
SELECT 'outbound_sends_no_write_policies',
       (SELECT count(*) FROM pg_policy p
        JOIN pg_class c ON c.oid = p.polrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = 'outbound_sends'
          AND p.polcmd IN ('a', 'w', 'd'))::int
UNION ALL
-- (13) authenticated cannot INSERT directly into outbound_sends
SELECT 'outbound_sends_insert_revoked_from_authenticated',
       CASE WHEN has_table_privilege('authenticated', 'public.outbound_sends', 'INSERT')
         THEN 1 ELSE 0 END::int
UNION ALL
-- (14) both WORM triggers attached to outbound_sends
SELECT 'outbound_sends_worm_triggers_attached',
       CASE WHEN (
         SELECT count(*) FROM pg_trigger t
         JOIN pg_class c ON c.oid = t.tgrelid
         JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND c.relname = 'outbound_sends'
           AND t.tgname IN ('outbound_sends_no_update', 'outbound_sends_no_delete')
           AND NOT t.tgisinternal
       ) = 2 THEN 0 ELSE 1 END::int
UNION ALL
-- (15) record_outbound_send IS executable by authenticated
SELECT 'record_outbound_send_granted_to_authenticated',
       CASE WHEN has_function_privilege(
         'authenticated',
         'public.record_outbound_send(text, text, text, text, text)',
         'EXECUTE'
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (16) record_outbound_send NOT executable by anon
SELECT 'record_outbound_send_not_granted_to_anon',
       CASE WHEN has_function_privilege(
         'anon',
         'public.record_outbound_send(text, text, text, text, text)',
         'EXECUTE'
       ) THEN 1 ELSE 0 END::int
UNION ALL
-- (17) anonymise_outbound_sends IS executable by service_role
SELECT 'anonymise_outbound_sends_granted_to_service_role',
       CASE WHEN has_function_privilege(
         'service_role',
         'public.anonymise_outbound_sends(uuid)',
         'EXECUTE'
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (18) all outbound_sends RPCs + trigger fn are SECURITY DEFINER (prosecdef)
SELECT 'outbound_sends_rpcs_security_definer',
       CASE WHEN (
         SELECT count(*) FROM pg_proc p
         JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname IN ('record_outbound_send', 'anonymise_outbound_sends', 'outbound_sends_no_mutate')
           AND p.prosecdef
       ) = 3 THEN 0 ELSE 1 END::int
UNION ALL
-- (19) anonymise_outbound_sends NOT executable by authenticated (service-role
-- only — no self-service erasure of the third-party WORM audit; sec review #5325)
SELECT 'anonymise_outbound_sends_not_granted_to_authenticated',
       CASE WHEN has_function_privilege(
         'authenticated',
         'public.anonymise_outbound_sends(uuid)',
         'EXECUTE'
       ) THEN 1 ELSE 0 END::int
UNION ALL
-- (20) anonymise_email_suppression NOT executable by authenticated (service-role
-- only — wiping the suppression set could re-enable opted-out sends)
SELECT 'anonymise_email_suppression_not_granted_to_authenticated',
       CASE WHEN has_function_privilege(
         'authenticated',
         'public.anonymise_email_suppression(uuid)',
         'EXECUTE'
       ) THEN 1 ELSE 0 END::int
UNION ALL
-- (21) duplicate-send guard: the UNIQUE(owner_id, recipient_hash,
-- approved_body_sha256) dedup index exists
SELECT 'outbound_sends_dedup_unique_index',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_class i
         JOIN pg_namespace n ON n.oid = i.relnamespace
         WHERE n.nspname = 'public'
           AND i.relname = 'outbound_sends_dedup_unique'
           AND i.relkind = 'i'
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (22) outbound_send_exists IS executable by authenticated (pre-send dup check)
SELECT 'outbound_send_exists_granted_to_authenticated',
       CASE WHEN has_function_privilege(
         'authenticated',
         'public.outbound_send_exists(text, text)',
         'EXECUTE'
       ) THEN 0 ELSE 1 END::int;
