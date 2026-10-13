# Migration checklist — feat-routines-management (#5345)

Migration: `apps/web-platform/supabase/migrations/107_routine_runs.sql` (+ `.down.sql`)

## dev apply — done

Applied to dev-Supabase by the `tenant-integration` CI workflow (green on the
PR head). The `account-delete.routine-runs-cascade.integration.test.ts`
integration test runs against dev and verifies the RESTRICT-FK + `anonymise_routine_runs`
Art-17 cascade on a real row.

## prd apply — pending

Deferred to merge. `apps/web-platform/.github/workflows/web-platform-release.yml`
applies new migrations to prd-Supabase on push to `main`, and its
`verify-migrations` job runs the sentinels post-deploy. There is no pre-merge
prd apply for this PR — the `routine_runs` table does not exist on prd until the
release workflow runs. Preflight Check 1 (DB migration status) therefore SKIPs
pre-merge per its documented-deferral path; ship Phase 7 Step 3.6 + the release
workflow's `verify-migrations` job are the post-merge verification surface.
