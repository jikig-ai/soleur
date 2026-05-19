-- Verify 051_action_class_widening_and_action_sends.sql.
--
-- Contract (see scripts/run-verify.sh): every row returns `check_name`
-- + `bad`. Any row with `bad > 0` fails the CI verify-migrations job.
--
-- Sentinels verify post-apply structural invariants from migration 051:
--   * scope_grants_tier_check admits 'auto_with_digest'
--   * scope_grants_action_class_not_locked regex CHECK exists
--   * messages.action_class column exists
--   * PR-F CFO backfill landed (action_class set for the bounded set)
--   * action_sends table exists with RLS, both BEFORE triggers, both
--     RLS policies, the covering index
--   * action_sends_action_class_not_locked CHECK exists
--   * anonymise_action_sends RPC exists with correct grants
--   * grant_action_class RPC accepts the 4th tier literal (text-grep on
--     prosrc since pg_proc.prosrc is the source we control)

-- (1) scope_grants tier CHECK widened
SELECT 'scope_grants_tier_check_admits_4th' AS check_name,
       CASE WHEN pg_get_constraintdef(c.oid)
                 ~ 'auto_with_digest' THEN 0 ELSE 1 END::int AS bad
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
 WHERE t.relname = 'scope_grants' AND c.conname = 'scope_grants_tier_check'
UNION ALL
-- (2) scope_grants action_class enum-absence CHECK present
SELECT 'scope_grants_action_class_not_locked_present',
       CASE WHEN count(*) >= 1 THEN 0 ELSE 1 END::int
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
 WHERE t.relname = 'scope_grants'
   AND c.conname = 'scope_grants_action_class_not_locked'
UNION ALL
-- (3) messages.action_class column present
SELECT 'messages_action_class_column_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM information_schema.columns
 WHERE table_schema = 'public'
   AND table_name = 'messages'
   AND column_name = 'action_class'
UNION ALL
-- (4) PR-F CFO backfill — confirms the cutoff matched at least zero rows
--     without erroring (bounded backfill must not leave matching rows
--     un-classified for the pre-deploy window).
SELECT 'messages_pr_f_cfo_backfill_landed',
       (SELECT count(*) FROM public.messages
         WHERE tier = 'external_brand_critical'
           AND owning_domain = 'cfo'
           AND source = 'stripe'
           AND created_at < '2026-05-19 23:59:59+00'::timestamptz
           AND action_class IS NULL)::int
UNION ALL
-- (5) action_sends table exists
SELECT 'action_sends_table_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM information_schema.tables
 WHERE table_schema = 'public' AND table_name = 'action_sends'
UNION ALL
-- (6) RLS enabled
SELECT 'action_sends_rls_enabled',
       CASE WHEN c.relrowsecurity THEN 0 ELSE 1 END::int
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relname = 'action_sends'
UNION ALL
-- (7) Both WORM triggers exist
SELECT 'action_sends_no_update_trigger',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_trigger
 WHERE tgname = 'action_sends_no_update' AND NOT tgisinternal
UNION ALL
SELECT 'action_sends_no_delete_trigger',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_trigger
 WHERE tgname = 'action_sends_no_delete' AND NOT tgisinternal
UNION ALL
-- (8) Both RLS policies exist
SELECT 'action_sends_owner_select_policy',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'action_sends'
   AND policyname = 'action_sends_owner_select'
UNION ALL
SELECT 'action_sends_owner_insert_policy',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'action_sends'
   AND policyname = 'action_sends_owner_insert'
UNION ALL
-- (9) action_class enum-absence CHECK present on action_sends
SELECT 'action_sends_action_class_not_locked_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
 WHERE t.relname = 'action_sends'
   AND c.conname = 'action_sends_action_class_not_locked'
UNION ALL
-- (10) Covering index for digest/audit hot-path
SELECT 'action_sends_user_clicked_idx',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_indexes
 WHERE schemaname = 'public' AND indexname = 'action_sends_user_clicked_idx'
UNION ALL
-- (11) anonymise_action_sends RPC exists + service_role + authenticated grants
SELECT 'anonymise_action_sends_rpc_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'anonymise_action_sends'
UNION ALL
SELECT 'anonymise_action_sends_grants_correct',
       (
         SELECT CASE
           WHEN has_function_privilege('service_role',
                  'public.anonymise_action_sends(uuid)', 'EXECUTE')
             AND has_function_privilege('authenticated',
                  'public.anonymise_action_sends(uuid)', 'EXECUTE')
             AND NOT has_function_privilege('anon',
                  'public.anonymise_action_sends(uuid)', 'EXECUTE')
           THEN 0 ELSE 1 END
       )::int
UNION ALL
-- (12) grant_action_class RPC accepts 'auto_with_digest' — check prosrc.
SELECT 'grant_action_class_admits_auto_with_digest',
       CASE WHEN p.prosrc ~ 'auto_with_digest' THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'grant_action_class'
UNION ALL
-- (13) messages.action_class enum-absence CHECK present.
SELECT 'messages_action_class_not_locked_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
 WHERE t.relname = 'messages'
   AND c.conname = 'messages_action_class_not_locked'
UNION ALL
-- (14) scope_grants partial UNIQUE on (founder_id, action_class) WHERE
--      revoked_at IS NULL — enforces the "one active grant per pair"
--      invariant against concurrent-POST race in grant_action_class.
SELECT 'scope_grants_active_unique_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_indexes
 WHERE schemaname = 'public' AND indexname = 'scope_grants_active_unique'
UNION ALL
-- (15) action_sends(message_id) UNIQUE — prevents double-send via founder
--      double-click or archive-after-write split-brain.
SELECT 'action_sends_message_unique_present',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_indexes
 WHERE schemaname = 'public' AND indexname = 'action_sends_message_unique'
UNION ALL
-- (16) action_sends_no_mutate trigger fn pins search_path = public, pg_temp
--      per cq-pg-security-definer-search-path-pin-pg-temp. Post-deploy
--      assertion that a future regression dropping the pin trips CI verify.
SELECT 'action_sends_no_mutate_search_path_pinned',
       CASE WHEN p.proconfig @> ARRAY['search_path=public, pg_temp']
            THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'action_sends_no_mutate'
UNION ALL
-- (17) action_sends_no_mutate is SECURITY DEFINER (prosecdef = true).
SELECT 'action_sends_no_mutate_security_definer',
       CASE WHEN p.prosecdef THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'action_sends_no_mutate'
UNION ALL
-- (18) anonymise_action_sends search_path pinned.
SELECT 'anonymise_action_sends_search_path_pinned',
       CASE WHEN p.proconfig @> ARRAY['search_path=public, pg_temp']
            THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'anonymise_action_sends'
UNION ALL
-- (19) grant_action_class search_path pinned.
SELECT 'grant_action_class_search_path_pinned',
       CASE WHEN p.proconfig @> ARRAY['search_path=public, pg_temp']
            THEN 0 ELSE 1 END::int
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'grant_action_class';
