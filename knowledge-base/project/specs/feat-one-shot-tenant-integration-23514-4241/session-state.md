# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-21-fix-tenant-integration-dev-drift-from-unmerged-workspace-migrations-plan.md
- Status: complete

### Errors
None.

### Decisions
- Root cause re-diagnosed live: actual failing constraint is `scope_grants_workspace_id_check` (mig 055 from unmerged `feat-team-workspace-multi-user`), not the constraints named in issue body.
- Fix scope: revert dev-schema (mig 053–056 down + `_schema_migrations` cleanup) + add workflow gate in `run-migrations.sh` requiring `ALLOW_UNMERGED_DEV_APPLY=1` + per-CI-run drift `::warning::` probe in `tenant-integration.yml`.
- Brand-survival threshold: none (CI-only regression on dev Supabase; prd unaffected).
- Out-of-scope: mig 053 number collision between team-workspace branch and PR-I; tracked as AC7 follow-up issue, not folded into this PR.
- Deepen pass verified 8/8 AGENTS.md rule IDs, 4/4 commits, 3/3 PR states; fixed SQL `LIKE '05_'` wildcard bug → explicit `IN (...)` enum; corrected stale rollback citation to non-existent `apply-migration.ts`.

### Components Invoked
- `soleur:plan` (commit `624d190a`)
- `soleur:deepen-plan` (commit `de6fa4d4`)
