-- verify/164_git_data_erasure_pending.sql
-- Runtime sentinel for the git-data erasure ledger (#8211, precedent: verify/162). Each row
-- returns bad=1 on drift; run-verify.sh fails the deploy if any bad=1. Asserts the LIVE state:
-- only service_role may execute the five RPCs, both tables keep RLS on with no policy and no
-- client-role (nor service_role) table privilege, the CHECK constraints equal their full expected
-- text, and each table holds EXACTLY the expected column set (the data-minimisation guarantee:
-- a column added later, such as an email or a user id, turns this red).

SELECT 'rec_anon_revoked' AS check_name,
       CASE WHEN has_function_privilege('anon', 'public.record_git_data_erasure_pending(uuid, text, timestamptz)', 'EXECUTE') THEN 1 ELSE 0 END::int AS bad
UNION ALL
SELECT 'rec_authenticated_revoked' AS check_name,
       CASE WHEN has_function_privilege('authenticated', 'public.record_git_data_erasure_pending(uuid, text, timestamptz)', 'EXECUTE') THEN 1 ELSE 0 END::int AS bad
UNION ALL
SELECT 'rec_service_role_granted',
       CASE WHEN has_function_privilege('service_role', 'public.record_git_data_erasure_pending(uuid, text, timestamptz)', 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'rec_definer_pinned_search_path',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = 'public.record_git_data_erasure_pending(uuid, text, timestamptz)'::regprocedure
                          AND p.prosecdef AND 'search_path=public, pg_temp' = ANY (p.proconfig)) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'claim_anon_revoked' AS check_name,
       CASE WHEN has_function_privilege('anon', 'public.claim_git_data_erasure_pending(int, interval)', 'EXECUTE') THEN 1 ELSE 0 END::int AS bad
UNION ALL
SELECT 'claim_authenticated_revoked' AS check_name,
       CASE WHEN has_function_privilege('authenticated', 'public.claim_git_data_erasure_pending(int, interval)', 'EXECUTE') THEN 1 ELSE 0 END::int AS bad
UNION ALL
SELECT 'claim_service_role_granted',
       CASE WHEN has_function_privilege('service_role', 'public.claim_git_data_erasure_pending(int, interval)', 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'claim_definer_pinned_search_path',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = 'public.claim_git_data_erasure_pending(int, interval)'::regprocedure
                          AND p.prosecdef AND 'search_path=public, pg_temp' = ANY (p.proconfig)) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'resolve_anon_revoked' AS check_name,
       CASE WHEN has_function_privilege('anon', 'public.resolve_git_data_erasure_pending(uuid)', 'EXECUTE') THEN 1 ELSE 0 END::int AS bad
UNION ALL
SELECT 'resolve_authenticated_revoked' AS check_name,
       CASE WHEN has_function_privilege('authenticated', 'public.resolve_git_data_erasure_pending(uuid)', 'EXECUTE') THEN 1 ELSE 0 END::int AS bad
UNION ALL
SELECT 'resolve_service_role_granted',
       CASE WHEN has_function_privilege('service_role', 'public.resolve_git_data_erasure_pending(uuid)', 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'resolve_definer_pinned_search_path',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = 'public.resolve_git_data_erasure_pending(uuid)'::regprocedure
                          AND p.prosecdef AND 'search_path=public, pg_temp' = ANY (p.proconfig)) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'oldest_anon_revoked' AS check_name,
       CASE WHEN has_function_privilege('anon', 'public.oldest_git_data_erasure_pending_age()', 'EXECUTE') THEN 1 ELSE 0 END::int AS bad
UNION ALL
SELECT 'oldest_authenticated_revoked' AS check_name,
       CASE WHEN has_function_privilege('authenticated', 'public.oldest_git_data_erasure_pending_age()', 'EXECUTE') THEN 1 ELSE 0 END::int AS bad
UNION ALL
SELECT 'oldest_service_role_granted',
       CASE WHEN has_function_privilege('service_role', 'public.oldest_git_data_erasure_pending_age()', 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'oldest_definer_pinned_search_path',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = 'public.oldest_git_data_erasure_pending_age()'::regprocedure
                          AND p.prosecdef AND 'search_path=public, pg_temp' = ANY (p.proconfig)) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'owner_gone_anon_revoked' AS check_name,
       CASE WHEN has_function_privilege('anon', 'public.git_data_erasure_owner_gone(uuid)', 'EXECUTE') THEN 1 ELSE 0 END::int AS bad
UNION ALL
SELECT 'owner_gone_authenticated_revoked' AS check_name,
       CASE WHEN has_function_privilege('authenticated', 'public.git_data_erasure_owner_gone(uuid)', 'EXECUTE') THEN 1 ELSE 0 END::int AS bad
UNION ALL
SELECT 'owner_gone_service_role_granted',
       CASE WHEN has_function_privilege('service_role', 'public.git_data_erasure_owner_gone(uuid)', 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'owner_gone_definer_pinned_search_path',
       CASE WHEN EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = 'public.git_data_erasure_owner_gone(uuid)'::regprocedure
                          AND p.prosecdef AND 'search_path=public, pg_temp' = ANY (p.proconfig)) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'git_data_erasure_pending_rls_enabled',
       CASE WHEN (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid = 'public.git_data_erasure_pending'::regclass) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'git_data_erasure_pending_no_policy',
       CASE WHEN EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = 'public.git_data_erasure_pending'::regclass) THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'git_data_erasure_pending_no_client_privilege',
       CASE WHEN has_table_privilege('anon', 'public.git_data_erasure_pending', 'SELECT,INSERT,UPDATE,DELETE')
              OR has_table_privilege('authenticated', 'public.git_data_erasure_pending', 'SELECT,INSERT,UPDATE,DELETE')
              OR has_table_privilege('service_role', 'public.git_data_erasure_pending', 'SELECT,INSERT,UPDATE,DELETE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'git_data_erasure_pending_no_foreign_key',
       CASE WHEN EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = 'public.git_data_erasure_pending'::regclass AND k.contype = 'f') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'git_data_erasure_counts_rls_enabled',
       CASE WHEN (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid = 'public.git_data_erasure_counts'::regclass) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'git_data_erasure_counts_no_policy',
       CASE WHEN EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = 'public.git_data_erasure_counts'::regclass) THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'git_data_erasure_counts_no_client_privilege',
       CASE WHEN has_table_privilege('anon', 'public.git_data_erasure_counts', 'SELECT,INSERT,UPDATE,DELETE')
              OR has_table_privilege('authenticated', 'public.git_data_erasure_counts', 'SELECT,INSERT,UPDATE,DELETE')
              OR has_table_privilege('service_role', 'public.git_data_erasure_counts', 'SELECT,INSERT,UPDATE,DELETE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'git_data_erasure_counts_no_foreign_key',
       CASE WHEN EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = 'public.git_data_erasure_counts'::regclass AND k.contype = 'f') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'git_data_erasure_pending_exact_column_set',
       CASE WHEN (SELECT string_agg(column_name || ':' || data_type || ':' || is_nullable, ',' ORDER BY column_name)
                     FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'git_data_erasure_pending') = 'attempts:integer:NO,last_attempt_at:timestamp with time zone:YES,last_outcome:text:YES,requested_at:timestamp with time zone:NO,workspace_id:uuid:NO' THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'git_data_erasure_counts_exact_column_set',
       CASE WHEN (SELECT string_agg(column_name || ':' || data_type || ':' || is_nullable, ',' ORDER BY column_name)
                     FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'git_data_erasure_counts') = 'bucket:text:NO,count:bigint:NO,month:date:NO' THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'check_git_data_erasure_pending_last_outcome_check_exact',
       CASE WHEN (SELECT pg_get_constraintdef(k.oid) FROM pg_constraint k
                   WHERE k.conrelid = 'public.git_data_erasure_pending'::regclass AND k.conname = 'git_data_erasure_pending_last_outcome_check' AND k.contype = 'c')
                 = 'CHECK ((last_outcome = ANY (ARRAY[''refused''::text, ''unreachable''::text, ''unauthorized''::text, ''unconfigured''::text, ''host_key_mismatch''::text, ''threw''::text, ''seeded''::text])))' THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'check_git_data_erasure_pending_attempts_check_exact',
       CASE WHEN (SELECT pg_get_constraintdef(k.oid) FROM pg_constraint k
                   WHERE k.conrelid = 'public.git_data_erasure_pending'::regclass AND k.conname = 'git_data_erasure_pending_attempts_check' AND k.contype = 'c')
                 = 'CHECK ((attempts >= 0))' THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'check_git_data_erasure_counts_bucket_check_exact',
       CASE WHEN (SELECT pg_get_constraintdef(k.oid) FROM pg_constraint k
                   WHERE k.conrelid = 'public.git_data_erasure_counts'::regclass AND k.conname = 'git_data_erasure_counts_bucket_check' AND k.contype = 'c')
                 = 'CHECK ((bucket = ANY (ARRAY[''lt_1h''::text, ''lt_24h''::text, ''lt_7d''::text, ''lt_20d''::text, ''ge_20d''::text])))' THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'check_git_data_erasure_counts_count_check_exact',
       CASE WHEN (SELECT pg_get_constraintdef(k.oid) FROM pg_constraint k
                   WHERE k.conrelid = 'public.git_data_erasure_counts'::regclass AND k.conname = 'git_data_erasure_counts_count_check' AND k.contype = 'c')
                 = 'CHECK ((count >= 0))' THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'check_git_data_erasure_counts_month_check_exact',
       CASE WHEN (SELECT pg_get_constraintdef(k.oid) FROM pg_constraint k
                   WHERE k.conrelid = 'public.git_data_erasure_counts'::regclass AND k.conname = 'git_data_erasure_counts_month_check' AND k.contype = 'c')
                 = 'CHECK ((EXTRACT(day FROM month) = (1)::numeric))' THEN 0 ELSE 1 END::int;
