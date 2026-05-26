---
date: 2026-05-25
category: build-errors
status: applied
related_pr: "#4417, hotfix PR (this)"
related_mig: "068_attachments_workspace_shared.sql"
---

# `COMMENT ON POLICY ... ON storage.objects` fails with "must be owner of relation objects" via the canonical migration runner

## Problem

Mig 068 (#4318 PR #4417) shipped a `COMMENT ON POLICY "Users read own + co-member attachment objects" ON storage.objects IS '...'` statement to document the policy split. The migration applied successfully through `CREATE FUNCTION`, `REVOKE`, `GRANT`, `COMMENT` (on the function), `DROP POLICY`, and four `CREATE POLICY` statements — then errored at the COMMENT ON POLICY step with:

```
ERROR:  must be owner of relation objects
```

`psql --single-transaction` rolled the whole stream back, so prd was left in pre-mig-068 state with the mig 045 `FOR ALL` policy still active. Zero corruption — but the migrate job failed, verify-migrations skipped, deploy skipped, and the new auto-applied prd image never ran. The PR's behavioral changes (presign + url widening, account-delete cascade step 3.901) were merged into main but had no effect because the supporting RPCs and policies weren't applied.

## Root cause

Supabase's prd database manages `storage.objects` ownership via the `supabase_storage_admin` role. The canonical migration runner uses Doppler's `prd.DATABASE_URL` which authenticates as `postgres.<project-ref>` via the pooler — a different role with elevated privileges over `public.*` but NOT ownership of `storage.objects`.

Postgres permits non-owners to execute SOME operations on storage.objects:
- `DROP POLICY` ✓ (Supabase grants this explicitly via `ALTER DEFAULT PRIVILEGES`)
- `CREATE POLICY` ✓ (same)
- `COMMENT ON POLICY ... ON storage.objects` ✗ (requires table ownership; not granted)

The asymmetry is silent — `\dp+` doesn't show it; only the apply-time error surfaces it.

## Solution

Replace `COMMENT ON POLICY` with in-body `--` prose comments. The text is still in the migration file for future readers; `\dp+ storage.objects` queries won't surface it, but the migration file is the canonical reference anyway.

```sql
-- COMMENT ON POLICY would fail here under the canonical runner's
-- service-role account (storage.objects owned by supabase_storage_admin).
-- Keep the rationale as in-body prose instead.
--
-- Policy "Users read own + co-member attachment objects":
--   Read-path widened per #4318...
```

If a structured COMMENT is needed for future tooling (some Supabase Studio surfaces, or a custom MCP scanner), apply via the Supabase Management API (which has supabase_storage_admin context) as a separate one-off operator step — NOT through the standard migration runner.

## Key insight

**The migration runner's privilege boundary is a hard constraint on what SQL the migration body can contain.** Some statements LOOK like normal SQL but require ownership of platform-managed tables (storage.objects, auth.users, realtime.*). The asymmetry is invisible at lint time, invisible at dev (smaller DBs often have looser ownership), and surfaces only at the moment of prd apply — by which time the PR is merged and rolling back to clear the failure is operator work.

Generalize: for any platform-managed table (anything outside `public.*`), assume the migration runner can ONLY run statements explicitly permitted by Supabase's `ALTER DEFAULT PRIVILEGES` grants. The minimal verified set:
- `CREATE POLICY` ✓ (verified mig 019, 045, 068 v2)
- `DROP POLICY ... IF EXISTS` ✓ (verified mig 045, 068 v1 partial-success)
- `COMMENT ON POLICY` ✗ (mig 068 v1 — this learning)
- `ALTER TABLE storage.objects ...` ✗ (not attempted but presumed unsafe)

For NEW migration patterns touching platform-managed tables, validate the smallest reproducer against dev BEFORE landing on prd — or use the elevated Supabase MCP / Management API path for the one-off ownership-required operations.

## Prevention

1. **Sentinel test** at `apps/web-platform/test/supabase-migrations/<mig>.test.ts`: add a negative-space lint asserting `COMMENT ON POLICY` does NOT appear anywhere in any migration file targeting `storage.objects`. Same for `ALTER TABLE storage.*`.

2. **Migration template**: add a "platform-table restrictions" warning to the template at `apps/web-platform/supabase/migrations/_template.sql` (if one exists) listing the verified-safe operation set.

3. **`/soleur:plan` migration prescription**: when a plan touches `storage.objects` or `auth.*`, the planner should explicitly enumerate the permitted operation set and refuse to prescribe ownership-required statements.

## Files

- `apps/web-platform/supabase/migrations/068_attachments_workspace_shared.sql` (hotfix PR strips the COMMENT ON POLICY)
- `apps/web-platform/scripts/run-migrations.sh` (the runner)
- `apps/web-platform/test/supabase-migrations/068-attachments-workspace-shared.test.ts` (mig-shape lint — add the negative-space assertion in a follow-up)

## Reference

- PR #4417 mig 068 v1 apply failure (run 26418490443, job 77768432523, 2026-05-25T20:33:12Z)
- Prior class: operator-side R-9 spike at Phase 0 hit the same restriction via the Doppler pooler; documented in `knowledge-base/project/specs/feat-attachments-rls-bundle-pr2-4318/phase-0-worklog.md` §"Dev mig 068 apply blocked by `supabase_storage_admin` ownership". The Phase 0 finding correctly predicted this would fail in CI too; the prediction was lost in scope cuts between Phase 0 and ship.
