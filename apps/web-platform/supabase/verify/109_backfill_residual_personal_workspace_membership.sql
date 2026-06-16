-- Verify 109_backfill_residual_personal_workspace_membership.sql.
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row fails CI
-- verify-migrations (and auto-closes any matching `follow-through` issue).
--
-- Sentinels confirm the post-apply state of the ADR-044 PR-1 residual backfill
-- (#5437): the always-enforce-workspace invariant — every user owns their
-- 1-member personal workspace (the owner-membership canary that
-- `is_workspace_owner` / `resolveActiveWorkspace` rely on).

-- (1) Zero users missing the owner-membership canary (the backfill's purpose +
--     the Post-merge AC's "membership-null count returns 0"). This is the
--     hard prerequisite for the PR-1 owner-gate.
SELECT 'users_missing_owner_canary' AS check_name,
       (SELECT count(*) FROM public.users u
        WHERE NOT EXISTS (
          SELECT 1 FROM public.workspace_members m
          WHERE m.user_id = u.id
            AND m.workspace_id = u.id
            AND m.role = 'owner'
        ))::int AS bad
UNION ALL
-- (2) No blank-named workspaces introduced (mig 091:208 set the canonical
--     'My Workspace'; the backfill must not reintroduce the NULL/empty names
--     mig 091 fixed).
SELECT 'workspaces_blank_name',
       (SELECT count(*) FROM public.workspaces
        WHERE name IS NULL OR btrim(name) = '')::int
UNION ALL
-- (3) No blank-named organizations introduced (same invariant).
SELECT 'organizations_blank_name',
       (SELECT count(*) FROM public.organizations
        WHERE name IS NULL OR btrim(name) = '')::int;
