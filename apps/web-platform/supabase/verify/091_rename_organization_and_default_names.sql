-- Verify 091_rename_organization_and_default_names.sql.
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row
-- fails CI verify-migrations.
--
-- Sentinels confirm post-apply state from migration 091:
--   * no organization carries a NULL/empty name (backfill + trigger default)
--   * no workspace carries a NULL/empty name
--   * rename_organization RPC exists
--   * rename_organization is NOT EXECUTE-able by `authenticated` (the P1
--     owner-gate-bypass guard — it must be service_role-only because it takes
--     a forgeable caller-override param)

-- (1) no NULL/empty organization names
SELECT 'organizations_have_names' AS check_name,
       (SELECT count(*) FROM public.organizations
         WHERE name IS NULL OR btrim(name) = '')::int AS bad
UNION ALL
-- (2) no NULL/empty workspace names
SELECT 'workspaces_have_names',
       (SELECT count(*) FROM public.workspaces
         WHERE name IS NULL OR btrim(name) = '')::int
UNION ALL
-- (3) rename_organization RPC exists
SELECT 'rename_organization_exists',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_proc p
         JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'rename_organization'
       ) THEN 0 ELSE 1 END::int
UNION ALL
-- (4) rename_organization is NOT executable by authenticated (P1 guard)
SELECT 'rename_organization_not_granted_to_authenticated',
       CASE WHEN has_function_privilege(
         'authenticated',
         'public.rename_organization(uuid, text, uuid)',
         'EXECUTE'
       ) THEN 1 ELSE 0 END::int;
