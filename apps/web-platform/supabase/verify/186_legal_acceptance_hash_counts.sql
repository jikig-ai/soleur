-- verify/186_legal_acceptance_hash_counts.sql
-- Runtime catalog sentinel for the credential-free pre-flag aggregate (#12429, ADR-319 amendment 2026-11-08). The
-- migration-shape test (test/legal-acceptance/migration-186-legal-acceptance-hash-counts.test.ts) asserts the SQL TEXT;
-- this asserts the LIVE catalog after apply. Each row returns bad=1 on a drift (precedent: verify/185). NOTE: the release
-- pipeline does NOT run this file today. The `verify-migrations` job is skipped on `workflow_run` deploys (its `if:` lacks
-- `always()`; trackers #9825 and #9471), so nothing fails a deploy on a bad=1 here. The compensating post-deploy check for
-- the anon/authenticated EXECUTE rows below is an anonymous POST to the Supabase REST rpc endpoint with the public anon key
-- (ADR-319, amendment 2026-11-08, "Apply path"); run this file by hand with run-verify.sh when the catalog must be proven.
--
-- Invariants: the function is SECURITY DEFINER with a pinned search_path, STABLE, EXECUTE-able by service_role only, reads
-- ONLY the record table, refuses a user identity, and its source names no per-row column (founder id, choice, timestamp,
-- note). No other function of that name exists in public (no leftover overload), and none is EXECUTE-able by anon,
-- authenticated or PUBLIC.

SELECT format('%s_security_definer_search_path_pinned', f.fn) AS check_name,
       CASE WHEN (SELECT prosecdef AND proconfig @> ARRAY['search_path=public, pg_temp'] FROM pg_proc WHERE oid = f.sig::regprocedure) THEN 0 ELSE 1 END::int AS bad
  FROM (VALUES ('legal_acceptance_hash_counts', 'public.legal_acceptance_hash_counts(text)')) AS f(fn, sig)
UNION ALL
SELECT format('%s_execute_%s', f.fn, r.role),
       CASE WHEN has_function_privilege(r.role, f.sig, 'EXECUTE') = (r.role = 'service_role') THEN 0 ELSE 1 END::int
  FROM (VALUES ('legal_acceptance_hash_counts', 'public.legal_acceptance_hash_counts(text)')) AS f(fn, sig)
 CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) AS r(role)
UNION ALL
-- A leftover overload (a different argument list under the same name) is invisible to the exact-signature checks above.
SELECT 'hash_counts_has_no_other_overloads',
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'legal_acceptance_hash_counts'
           AND p.oid <> 'public.legal_acceptance_hash_counts(text)'::regprocedure)::int
UNION ALL
-- EXECUTE for anon, authenticated or PUBLIC on ANY function of that name, whatever its signature.
SELECT 'hash_counts_no_execute_for_anon_authenticated_or_public',
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'legal_acceptance_hash_counts'
           AND (has_function_privilege('anon', p.oid, 'EXECUTE')
                OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
                OR EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
                            WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')))::int
UNION ALL
SELECT 'hash_counts_is_stable_read_only_and_refuses_a_user_identity',
       CASE WHEN (SELECT provolatile = 's' AND prosrc LIKE '%auth.uid() IS NOT NULL%' AND prosrc LIKE '%FROM ONLY public.legal_acceptance%'
                         AND prosrc NOT LIKE '%set_config%' AND prosrc NOT LIKE '%app.legal_acceptance_rpc%'
                    FROM pg_proc WHERE oid = 'public.legal_acceptance_hash_counts(text)'::regprocedure)
            THEN 0 ELSE 1 END::int
UNION ALL
-- The aggregate may never name a per-row column: who decided, what they decided, when, or the note.
SELECT 'hash_counts_names_no_per_row_column',
       CASE WHEN (SELECT prosrc ~* '(founder_id|choice|created_at|requested_edit|row_hash|session_id|event_id|reauth_at|reauth_method)'
                    FROM pg_proc WHERE oid = 'public.legal_acceptance_hash_counts(text)'::regprocedure)
            THEN 1 ELSE 0 END::int;
