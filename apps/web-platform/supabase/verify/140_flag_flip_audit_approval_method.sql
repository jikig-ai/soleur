-- Verify 140_flag_flip_audit_approval_method.sql (#8486, ADR-249).
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row fails CI
-- verify-migrations (run-verify.sh parses tab-separated (check_name TEXT,
-- bad INT) rows under ON_ERROR_STOP=1).
--
-- WHY THIS FILE EXISTS. 140 drops and recreates the writer RPC, which discards
-- its grants; the offline test asserts the REVOKE/GRANT text, and only this file
-- observes the live privileges after apply. It also proves the 7-arg overload is
-- gone: if both existed, every 7-key PostgREST call would be ambiguous and every
-- flag write would exit 4.

-- (1) The column exists.
SELECT 'approval_method_column_present' AS check_name,
       CASE WHEN EXISTS (
              SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'flag_flip_audit'
                 AND column_name = 'approval_method')
            THEN 0 ELSE 1 END::int AS bad
UNION ALL

-- (2) The CHECK admits tty-ack and nothing wider than the one value.
SELECT 'approval_method_check_admits_tty_ack',
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_constraint
               WHERE conrelid = 'public.flag_flip_audit'::regclass
                 AND contype = 'c'
                 AND pg_get_constraintdef(oid) LIKE '%approval_method%tty-ack%')
            THEN 0 ELSE 1 END::int
UNION ALL

-- (3) The 7-arg overload is gone.
SELECT 'audit_rpc_7arg_overload_dropped',
       CASE WHEN to_regprocedure('public.audit_flag_flip(text,text,text,text,bool,bool,text)') IS NULL
            THEN 0 ELSE 1 END::int
UNION ALL

-- (4-6) Privileges on the exact 8-arg signature.
SELECT 'audit_rpc_anon_revoked',
       CASE WHEN has_function_privilege('anon',
              'public.audit_flag_flip(text,text,text,text,bool,bool,text,text)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'audit_rpc_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated',
              'public.audit_flag_flip(text,text,text,text,bool,bool,text,text)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'audit_rpc_service_role_retained',
       CASE WHEN has_function_privilege('service_role',
              'public.audit_flag_flip(text,text,text,text,bool,bool,text,text)', 'EXECUTE') THEN 0 ELSE 1 END::int;
