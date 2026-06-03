-- Verify 092_transfer_ownership_caller_override.sql.
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row
-- fails CI verify-migrations.
--
-- Sentinels confirm post-apply state from migration 092 (#4765):
--   * the 4-arg transfer_workspace_ownership RPC exists
--   * it is NOT EXECUTE-able by `authenticated` (the P1 owner-gate-bypass
--     guard — it must be service_role-only because it takes a forgeable
--     p_caller_user_id caller-override param; identical class to the
--     rename_organization guard in verify/091)
--   * the old 3-arg (uuid, uuid, text) overload no longer exists (DROPped),
--     so no authenticated-reachable form survives

-- (1) 4-arg transfer_workspace_ownership RPC exists
SELECT 'transfer_workspace_ownership_4arg_exists' AS check_name,
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc p
         JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname = 'transfer_workspace_ownership'
           AND pg_get_function_identity_arguments(p.oid)
               = 'p_workspace_id uuid, p_new_owner_user_id uuid, p_attestation_text text, p_caller_user_id uuid'
       ) THEN 0 ELSE 1 END::int AS bad
UNION ALL
-- (2) 4-arg form is NOT executable by authenticated (P1 guard)
SELECT 'transfer_workspace_ownership_not_granted_to_authenticated',
       CASE WHEN has_function_privilege(
         'authenticated',
         'public.transfer_workspace_ownership(uuid, uuid, text, uuid)',
         'EXECUTE'
       ) THEN 1 ELSE 0 END::int
UNION ALL
-- (3) the old 3-arg overload no longer exists (DROPped by 092)
SELECT 'transfer_workspace_ownership_3arg_dropped',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc p
         JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname = 'transfer_workspace_ownership'
           AND pg_get_function_identity_arguments(p.oid)
               = 'p_workspace_id uuid, p_new_owner_user_id uuid, p_attestation_text text'
       ) THEN 1 ELSE 0 END::int;
