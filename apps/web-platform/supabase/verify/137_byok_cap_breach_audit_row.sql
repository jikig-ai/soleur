-- Verify 137_byok_cap_breach_audit_row.sql (#7829).
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row fails CI
-- verify-migrations (run-verify.sh parses tab-separated (check_name TEXT,
-- bad INT) rows under ON_ERROR_STOP=1).
--
-- WHY THIS FILE EXISTS. 137's own offline tripwire says so itself: it asserts
-- PRESENCE, and presence is exactly what shipped green against the broken
-- state before. The migration's highest-probability failure mode is "applies
-- but writes no row", and nothing else in the pipeline observes post-apply
-- state. The sibling migrations that change privileges (128, 129, 130) each
-- ship one of these; 137 changes privileges too, because DROP FUNCTION
-- discards the grants with the function.
--
-- Signature exactness is load-bearing: a wrong signature raises
-- `function ... does not exist` and, under ON_ERROR_STOP=1, hard-fails the
-- release pipeline (a false red) rather than silently passing.

-- (1) The return-status conversion actually landed. This is the migration's
--     entire thesis: refusal must be a RETURNED value, because an unhandled
--     RAISE aborts its own transaction and discards the audit row.
SELECT 'delegation_rpc_returns_refusal_reason' AS check_name,
       CASE WHEN pg_get_function_result(
              'public.check_and_record_byok_delegation_use(uuid,uuid,int,int,uuid,text)'::regprocedure
            ) = 'TABLE(refusal_reason text)' THEN 0 ELSE 1 END::int AS bad
UNION ALL

-- (2) No refusal is signalled by RAISE any more. Anchored on the sentinel
--     rather than a count, so a branch reintroduced later is caught.
SELECT 'delegation_rpc_no_cap_raise',
       CASE WHEN pg_get_functiondef(
              'public.check_and_record_byok_delegation_use(uuid,uuid,int,int,uuid,text)'::regprocedure
            ) LIKE '%byok_delegations:hourly_cap_exceeded%' THEN 1 ELSE 0 END::int
UNION ALL

-- (3) The CHECK admits all five reasons. A narrower live constraint aborts the
--     Art. 17 SET NULL cascade (065/066) the moment a cap row exists.
SELECT 'attribution_shift_reason_check_admits_five',
       CASE WHEN (SELECT pg_get_constraintdef(oid)
                    FROM pg_constraint
                   WHERE conname = 'audit_byok_use_attribution_shift_reason_check')
                 LIKE '%hourly_cap_exceeded%daily_cap_exceeded%' THEN 0 ELSE 1 END::int
UNION ALL

-- (4) The delegation windows carry the CORRECTED unit semantics (ADR-208
--     Decision 3). unit_cost_cents is a whole-turn total, so the product form
--     trips any real cap on the first turn and attributes 100% of delegated
--     rows to the wrong billing party, permanently, in a WORM table.
SELECT 'delegation_windows_sum_unit_cost_only',
       CASE WHEN pg_get_functiondef(
              'public.check_and_record_byok_delegation_use(uuid,uuid,int,int,uuid,text)'::regprocedure
            ) LIKE '%SUM(au.token_count * au.unit_cost_cents)%' THEN 1 ELSE 0 END::int
UNION ALL

-- (5) The personal Layer 1 accumulator excludes the refusal rows 137 creates,
--     and ONLY those (not admitted delegated rows, which 121 has always
--     counted against the grantor and should keep counting).
SELECT 'founder_sum_excludes_refusals_only',
       CASE WHEN pg_get_functiondef(
              'public.record_byok_use_and_check_cap(uuid,uuid,uuid,text,int,int)'::regprocedure
            ) LIKE '%attribution_shift_reason IS NULL%' THEN 0 ELSE 1 END::int
UNION ALL

-- (6-8) Privileges. DROP FUNCTION discards grants, so this is the live proof
--       that the re-issued REVOKE/GRANT actually took effect.
SELECT 'delegation_rpc_anon_revoked',
       CASE WHEN has_function_privilege('anon',
              'public.check_and_record_byok_delegation_use(uuid,uuid,int,int,uuid,text)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'delegation_rpc_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated',
              'public.check_and_record_byok_delegation_use(uuid,uuid,int,int,uuid,text)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'delegation_rpc_service_role_retained',
       CASE WHEN has_function_privilege('service_role',
              'public.check_and_record_byok_delegation_use(uuid,uuid,int,int,uuid,text)', 'EXECUTE') THEN 0 ELSE 1 END::int;
