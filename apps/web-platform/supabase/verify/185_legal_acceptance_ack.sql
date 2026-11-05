-- verify/185_legal_acceptance_ack.sql
-- Runtime catalog sentinel for the legal acceptance acknowledgement (#12011 PR-D, ADR-319). The migration-shape test
-- (test/legal-acceptance/migration-185-legal-acceptance-ack.test.ts) asserts the SQL TEXT; this asserts the LIVE catalog
-- after apply. Each row returns bad=1 on a drift; run-verify.sh fails the deploy if any bad=1 (precedent: verify/184).
--
-- Invariants: the ack table is RLS-enabled with no policy and no privilege for any api role; its columns are exactly
-- acceptance_id (primary key) and acked_at; no foreign key and no column-level privilege; both functions are SECURITY
-- DEFINER with a pinned search_path, EXECUTE-able by service_role only, and neither names the write-door setting of
-- legal_acceptance.

SELECT 'legal_acceptance_ack_rls_enabled' AS check_name,
       CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.legal_acceptance_ack'::regclass) THEN 0 ELSE 1 END::int AS bad
UNION ALL
SELECT 'legal_acceptance_ack_no_policy',
       CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'legal_acceptance_ack') THEN 1 ELSE 0 END::int
UNION ALL
SELECT format('legal_acceptance_ack_%s_%s_revoked', r.role, p.priv),
       CASE WHEN has_table_privilege(r.role, 'public.legal_acceptance_ack', p.priv) THEN 1 ELSE 0 END::int
  FROM (VALUES ('anon'), ('authenticated'), ('service_role')) AS r(role)
 CROSS JOIN (VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')) AS p(priv)
UNION ALL
SELECT 'legal_acceptance_ack_no_column_level_privileges',
       CASE WHEN EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = 'public.legal_acceptance_ack'::regclass
                           AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL) THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'legal_acceptance_ack_columns_are_exactly_id_and_time',
       CASE WHEN (SELECT array_agg(attname::text ORDER BY attnum) FROM pg_attribute
                   WHERE attrelid = 'public.legal_acceptance_ack'::regclass AND attnum > 0 AND NOT attisdropped)
                 = ARRAY['acceptance_id', 'acked_at'] THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'legal_acceptance_ack_primary_key_is_acceptance_id',
       CASE WHEN EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.legal_acceptance_ack'::regclass AND contype = 'p'
                           AND pg_get_constraintdef(oid) = 'PRIMARY KEY (acceptance_id)') THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'legal_acceptance_ack_no_foreign_key',
       CASE WHEN EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.legal_acceptance_ack'::regclass AND contype = 'f') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'legal_acceptance_ack_no_inheritance_children',
       CASE WHEN EXISTS (SELECT 1 FROM pg_inherits WHERE inhparent = 'public.legal_acceptance_ack'::regclass) THEN 1 ELSE 0 END::int
UNION ALL
SELECT format('%s_security_definer_search_path_pinned', f.fn),
       CASE WHEN (SELECT prosecdef AND proconfig @> ARRAY['search_path=public, pg_temp'] FROM pg_proc WHERE oid = f.sig::regprocedure) THEN 0 ELSE 1 END::int
  FROM (VALUES
    ('ack_legal_acceptance', 'public.ack_legal_acceptance(uuid, text, text)'),
    ('legal_acceptance_ack_state', 'public.legal_acceptance_ack_state(uuid, text, text)')
  ) AS f(fn, sig)
UNION ALL
SELECT format('%s_execute_%s', f.fn, r.role),
       CASE WHEN has_function_privilege(r.role, f.sig, 'EXECUTE') = (r.role = 'service_role') THEN 0 ELSE 1 END::int
  FROM (VALUES
    ('ack_legal_acceptance', 'public.ack_legal_acceptance(uuid, text, text)'),
    ('legal_acceptance_ack_state', 'public.legal_acceptance_ack_state(uuid, text, text)')
  ) AS f(fn, sig)
 CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) AS r(role)
UNION ALL
SELECT 'ack_functions_do_not_open_the_write_door_of_legal_acceptance',
       CASE WHEN (SELECT bool_and(prosrc NOT LIKE '%set_config%' AND prosrc NOT LIKE '%app.legal_acceptance_rpc%'
                                  AND prosrc LIKE '%auth.uid() IS NOT NULL%' AND prosrc LIKE '%FROM ONLY public.legal_acceptance%')
                    FROM pg_proc WHERE oid IN ('public.ack_legal_acceptance(uuid, text, text)'::regprocedure,
                                               'public.legal_acceptance_ack_state(uuid, text, text)'::regprocedure))
            THEN 0 ELSE 1 END::int
UNION ALL
SELECT 'legal_acceptance_ack_state_is_stable_and_read_only',
       CASE WHEN (SELECT provolatile = 's' FROM pg_proc WHERE oid = 'public.legal_acceptance_ack_state(uuid, text, text)'::regprocedure)
            THEN 0 ELSE 1 END::int;
