# Migration checklist — 091_rename_organization_and_default_names

Migration: `apps/web-platform/supabase/migrations/091_rename_organization_and_default_names.sql`
Verify sentinel: `apps/web-platform/supabase/verify/091_rename_organization_and_default_names.sql`

## prd apply — pending

The migration applies to prd on merge via the existing
`web-platform-release.yml#migrate` job (per the plan's Phase 2.8 IaC-ack — this is
a pure code change against the already-provisioned web-platform; no operator
apply step). The `verify-migrations` job in the same release workflow then runs
the committed verify sentinel, which asserts post-apply:

- 0 `organizations` rows with NULL/empty `name`
- 0 `workspaces` rows with NULL/empty `name`
- `rename_organization` RPC exists
- `rename_organization` is NOT EXECUTE-able by `authenticated` (the P1 owner-gate-bypass guard)

Preflight Check 1 SKIPs on this documented deferral and re-verifies post-merge via
the release workflow's `verify-migrations` job. No manual psql apply.

## dev apply — not required pre-merge

dev apply is exercised by the same release pipeline path; local psql is unavailable
in the build sandbox (psql not installed), so the migration shape is validated by
`test/supabase-migrations/091-rename-organization.test.ts` (16 source-regex
invariants) + the global `migration-rpc-grants` lint (378 fns scanned).
