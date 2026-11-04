-- verify/184_legal_acceptance.sql
-- Runtime catalog sentinel for the legal acceptance record (#12011 PR-B, ADR-319). The migration-shape test
-- (test/legal-acceptance/migration-184-legal-acceptance.test.ts) asserts the SQL TEXT; this asserts the LIVE catalog
-- after apply. Each row returns bad=1 on a drift; run-verify.sh fails the deploy if any bad=1 (precedent: verify/180).
--
-- Invariants: both tables are RLS-enabled; legal_acceptance has exactly one permissive policy (the founder's own
-- SELECT) and no api role (anon, authenticated, service_role) holds any write privilege on either table; the
-- event table has no policy and no privilege; the write-once trigger exists, is enabled and covers INSERT, UPDATE
-- and DELETE; the truncate trigger exists; record_legal_acceptance is EXECUTE-able by authenticated only, the four
-- service RPCs by service_role only, the checksum and guard functions by nobody; every function pins search_path;
-- no foreign key leaves legal_acceptance (erasure must not cascade into it).

SELECT 'legal_acceptance_rls_enabled' AS check_name,
       CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.legal_acceptance'::regclass) THEN 0 ELSE 1 END::int AS bad
UNION ALL
SELECT 'legal_reauth_event_rls_enabled',
       CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.legal_reauth_event'::regclass) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'legal_acceptance_one_permissive_policy_select_only',
       CASE WHEN (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'legal_acceptance' AND permissive = 'PERMISSIVE') = 1
            AND (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'legal_acceptance' AND permissive = 'PERMISSIVE' AND cmd = 'SELECT') = 1
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'legal_acceptance_select_policy_is_founder_only_and_not_runtime_audience',
       CASE WHEN (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'legal_acceptance'
                    AND permissive = 'PERMISSIVE' AND cmd = 'SELECT' AND roles = '{authenticated}'
                    AND qual LIKE '%founder_id = auth.uid()%' AND qual LIKE '%soleur-runtime%') = 1 THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'legal_acceptance_jti_deny_policy_restrictive',
       CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'legal_acceptance' AND permissive = 'RESTRICTIVE'
                          AND qual LIKE '%is_jti_denied_from_jwt%') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'legal_reauth_event_no_policy',
       CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'legal_reauth_event') THEN 1 ELSE 0 END::int
UNION ALL
SELECT format('%s_%s_%s_revoked', t.tbl, r.role, p.priv),
       CASE WHEN has_table_privilege(r.role, 'public.' || t.tbl, p.priv)
                 AND NOT (t.tbl = 'legal_acceptance' AND r.role = 'authenticated' AND p.priv = 'SELECT')
            THEN 1 ELSE 0 END::int
  FROM (VALUES ('legal_acceptance'), ('legal_reauth_event')) AS t(tbl)
 CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) AS r(role)
 CROSS JOIN (VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')) AS p(priv)
UNION ALL
SELECT 'legal_acceptance_authenticated_select_granted',
       CASE WHEN has_table_privilege('authenticated', 'public.legal_acceptance', 'SELECT') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'legal_acceptance_guard_trigger_enabled',
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_trigger
               WHERE tgrelid = 'public.legal_acceptance'::regclass AND tgname = 'legal_acceptance_guard'
                 AND tgenabled = 'A'
                 AND (tgtype & 4) <> 0   -- INSERT
                 AND (tgtype & 8) <> 0   -- DELETE
                 AND (tgtype & 16) <> 0  -- UPDATE
                 AND (tgtype & 2) <> 0   -- BEFORE
                 AND (tgtype & 1) <> 0)  -- ROW
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'legal_acceptance_truncate_trigger_enabled',
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_trigger
               WHERE tgrelid = 'public.legal_acceptance'::regclass AND tgname = 'legal_acceptance_no_truncate'
                 AND tgenabled = 'A' AND (tgtype & 32) <> 0)
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'legal_acceptance_no_column_level_privileges',
       CASE WHEN EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid IN ('public.legal_acceptance'::regclass, 'public.legal_reauth_event'::regclass)
                           AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL) THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'legal_acceptance_no_inheritance_children',
       CASE WHEN EXISTS (SELECT 1 FROM pg_inherits WHERE inhparent IN ('public.legal_acceptance'::regclass, 'public.legal_reauth_event'::regclass)) THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'legal_acceptance_only_the_guard_triggers',
       CASE WHEN (SELECT count(*) FROM pg_trigger WHERE tgrelid = 'public.legal_acceptance'::regclass AND NOT tgisinternal) = 2 THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'legal_acceptance_column_count_matches_the_hash',
       CASE WHEN (SELECT count(*) FROM pg_attribute WHERE attrelid = 'public.legal_acceptance'::regclass AND attnum > 0 AND NOT attisdropped) = 15
                 AND (SELECT prosrc LIKE '%r.event_id::text%' AND prosrc LIKE '%r.text_hash%' AND prosrc LIKE '%r.id::text%'
                        FROM pg_proc WHERE oid = 'public.legal_acceptance_row_hash(public.legal_acceptance)'::regprocedure)
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'legal_acceptance_guard_function_refuses_and_requires_intent',
       CASE WHEN (SELECT prosrc LIKE '%write-once%' AND prosrc LIKE '%app.legal_acceptance_rpc%' AND prosrc LIKE '%e.consumed_at IS NOT NULL%'
                        AND prosrc LIKE '%NEW.row_hash :=%' FROM pg_proc WHERE oid = 'public.legal_acceptance_guard()'::regprocedure)
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'legal_acceptance_constraints_present',
       CASE WHEN (SELECT count(*) FROM pg_constraint WHERE conrelid = 'public.legal_acceptance'::regclass
                    AND conname IN ('legal_acceptance_yes_has_reauth', 'legal_acceptance_reauth_only_for_yes',
                                    'legal_acceptance_reauth_paired', 'legal_acceptance_edit_only_with_request')) = 4 THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'legal_acceptance_no_foreign_key',
       CASE WHEN EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.legal_acceptance'::regclass AND contype = 'f') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'legal_acceptance_unique_triple',
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_constraint
               WHERE conrelid = 'public.legal_acceptance'::regclass AND contype = 'u'
                 AND pg_get_constraintdef(oid) = 'UNIQUE (founder_id, key, text_hash)')
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'legal_acceptance_method_fixed',
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_constraint
               WHERE conrelid = 'public.legal_acceptance'::regclass AND contype = 'c'
                 AND pg_get_constraintdef(oid) LIKE '%method = ''web-session''%')
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT format('%s_security_definer_search_path_pinned', f.fn),
       CASE WHEN (SELECT prosecdef AND proconfig @> ARRAY['search_path=public, pg_temp'] FROM pg_proc WHERE oid = f.sig::regprocedure) THEN 0 ELSE 1 END::int
  FROM (VALUES
    ('legal_acceptance_row_hash', 'public.legal_acceptance_row_hash(public.legal_acceptance)'),
    ('legal_acceptance_guard', 'public.legal_acceptance_guard()'),
    ('issue_legal_reauth', 'public.issue_legal_reauth(uuid, text, text, text, text, boolean)'),
    ('claim_legal_reauth_attempt', 'public.claim_legal_reauth_attempt(uuid, text, text, text)'),
    ('mark_legal_reauth_verified', 'public.mark_legal_reauth_verified(uuid, uuid, text, text, text)'),
    ('record_legal_acceptance', 'public.record_legal_acceptance(text, text, text, text)'),
    ('verify_legal_acceptance', 'public.verify_legal_acceptance(uuid, text, text)')
  ) AS f(fn, sig)
UNION ALL
SELECT format('%s_execute_%s', f.fn, r.role),
       CASE WHEN has_function_privilege(r.role, f.sig, 'EXECUTE') = (r.role = f.allowed) THEN 0 ELSE 1 END::int
  FROM (VALUES
    ('legal_acceptance_row_hash', 'public.legal_acceptance_row_hash(public.legal_acceptance)', 'nobody'),
    ('legal_acceptance_guard', 'public.legal_acceptance_guard()', 'nobody'),
    ('issue_legal_reauth', 'public.issue_legal_reauth(uuid, text, text, text, text, boolean)', 'service_role'),
    ('claim_legal_reauth_attempt', 'public.claim_legal_reauth_attempt(uuid, text, text, text)', 'service_role'),
    ('mark_legal_reauth_verified', 'public.mark_legal_reauth_verified(uuid, uuid, text, text, text)', 'service_role'),
    ('record_legal_acceptance', 'public.record_legal_acceptance(text, text, text, text)', 'authenticated'),
    ('verify_legal_acceptance', 'public.verify_legal_acceptance(uuid, text, text)', 'service_role')
  ) AS f(fn, sig, allowed)
 CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) AS r(role)
UNION ALL
SELECT 'record_legal_acceptance_checks_actor_jti_and_audience',
       CASE WHEN (SELECT prosrc LIKE '%auth.uid() IS NULL%' AND prosrc LIKE '%is_jti_denied_from_jwt()%'
                    AND prosrc LIKE '%IS DISTINCT FROM ''authenticated''%' AND prosrc LIKE '%v_session IS NULL%'
                    AND prosrc LIKE '%pg_advisory_xact_lock%' AND prosrc LIKE '%SET consumed_at = now()%'
                    FROM pg_proc WHERE oid = 'public.record_legal_acceptance(text, text, text, text)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'verify_legal_acceptance_fails_closed_and_does_not_open_write_door',
       CASE WHEN (SELECT prosrc NOT LIKE '%set_config%' AND prosrc LIKE '%''invalid''%' AND prosrc LIKE '%FROM ONLY%' FROM pg_proc WHERE oid = 'public.verify_legal_acceptance(uuid, text, text)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'anonymise_approval_request_does_not_know_the_record',
       CASE WHEN (SELECT prosrc NOT LIKE '%legal_acceptance%' FROM pg_proc WHERE oid = 'public.anonymise_approval_request(uuid)'::regprocedure) THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'legal_acceptance_rows_match_their_checksum',
       CASE WHEN EXISTS (SELECT 1 FROM public.legal_acceptance a WHERE a.row_hash <> public.legal_acceptance_row_hash(a)) THEN 1 ELSE 0 END::int;
