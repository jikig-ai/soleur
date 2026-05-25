---
title: Tasks — fix(ci) tenant-integration suite broken by dev-Supabase drift from unmerged team-workspace migrations
issue: 4241
branch: feat-one-shot-tenant-integration-23514-4241
plan: knowledge-base/project/plans/2026-05-21-fix-tenant-integration-dev-drift-from-unmerged-workspace-migrations-plan.md
lane: cross-domain
date: 2026-05-21
---

# Tasks

## 1. Setup

### 1.1 Preconditions
- [ ] **1.1.1** Confirm worktree CWD and branch (`feat-one-shot-tenant-integration-23514-4241`).
- [ ] **1.1.2** Confirm `grep -rn "scope_grants_workspace_id_check" apps/web-platform/supabase/migrations/` returns 0 on main (no source for the constraint).
- [ ] **1.1.3** Assert Doppler `dev_scheduled` resolves to `environment=dev` before any psql call.
- [ ] **1.1.4** Snapshot dev's `scope_grants` constraints to `/tmp/scope_grants_before.txt` for diff verification.

### 1.2 Stage down-migrations from team-workspace branch
- [ ] **1.2.1** Fetch down-migration files from `5c2696d4` into `/tmp/down-{053,054,055,056}.sql`.
- [ ] **1.2.2** Inspect each for explicit `DROP IF EXISTS` semantics; confirm 055.down drops `scope_grants_workspace_id_check`.

## 2. Core Implementation

### 2.1 Revert team-workspace migrations on dev (reverse order)
- [ ] **2.1.1** Apply `down-056.sql` via `DATABASE_URL_POOLER` session-mode (`:5432`).
- [ ] **2.1.2** Apply `down-055.sql` (removes `scope_grants_workspace_id_check`, `workspace_id` column, sweep RLS policies).
- [ ] **2.1.3** Apply `down-054.sql` (drops `workspace_member_attestations` WORM + RPCs).
- [ ] **2.1.4** Apply `down-053.sql` (drops `organizations`, `workspaces`, `workspace_members`, `is_workspace_member` helper, backfill).

### 2.2 Reconcile `_schema_migrations`
- [ ] **2.2.1** `DELETE FROM public._schema_migrations WHERE filename IN ('053_organizations_and_workspace_members.sql', '054_workspace_member_attestations.sql', '055_workspace_keyed_rls_sweep.sql', '056_current_organization_jwt_hook.sql');`
- [ ] **2.2.2** Re-snapshot `pg_constraint` for `scope_grants`; diff against `/tmp/scope_grants_before.txt`. Only delta MUST be `scope_grants_workspace_id_check` removed.
- [ ] **2.2.3** Verify `to_regclass('public.organizations')`, `public.workspaces`, `public.workspace_members`, `public.workspace_member_attestations` all return NULL.

### 2.3 Workflow gate — block unmerged dev applies
- [ ] **2.3.1** Edit `apps/web-platform/scripts/run-migrations.sh`: add precondition near the apply loop that requires `ALLOW_UNMERGED_DEV_APPLY=1` when the target filename is NOT on `origin/main` (`git ls-tree origin/main -- apps/web-platform/supabase/migrations/${filename}` returns empty).
- [ ] **2.3.2** Edit `.github/workflows/tenant-integration.yml`: add `Detect dev-vs-main migration drift` step BEFORE `Apply migrations to dev` that emits `::warning::` (NOT `::error::`) when `_schema_migrations` contains a filename not on `origin/main`. Reference issue #4241 in the warning text.

## 3. Testing

### 3.1 Local re-run of tenant-isolation suite
- [ ] **3.1.1** `cd apps/web-platform && doppler run -p soleur -c dev_scheduled -- env TENANT_INTEGRATION_TEST=1 npm run test:ci -- test/server/ --project unit --reporter=verbose` exits 0.
- [ ] **3.1.2** Spot-check 3 named suites: `scope-grants/lifecycle.test.ts` (4 cases), `template-authorizations-worm.test.ts`, `scope-grants/cross-tenant-read-denied.test.ts`.

### 3.2 Workflow-gate verification
- [ ] **3.2.1** Synthetic unmerged-filename test: create `apps/web-platform/supabase/migrations/099_test_unmerged.sql` locally; `bash apps/web-platform/scripts/run-migrations.sh --bootstrap=skip` against `dev_scheduled` exits non-zero. Remove synthetic file before push.
- [ ] **3.2.2** With `ALLOW_UNMERGED_DEV_APPLY=1`, the same invocation exits 0 (gate is opt-in).
- [ ] **3.2.3** `Detect dev-vs-main migration drift` step on the post-revert dev state exits 0 with NO warning (clean state).

### 3.3 Push & CI verification
- [ ] **3.3.1** Push branch; confirm `Tenant integration (dev-Supabase)` check is green on the PR.

## 4. Documentation

### 4.1 Capture learning
- [ ] **4.1.1** Write `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md` capturing (a) symptom 23514 on grant_action_class, (b) root cause apply-to-dev from unmerged branch, (c) misdiagnosis trap (wrong CHECK named in issue), (d) revert procedure, (e) gate.

### 4.2 Team-workspace follow-up
- [ ] **4.2.1** Open follow-up tracking issue against `feat-team-workspace-multi-user` requesting 053→057 renumber on rebase. (Post-merge operator action — AC7.)

## 5. Acceptance Criteria (mirrored from plan)

### Pre-merge (PR)
- [ ] AC1: 0 source matches for `scope_grants_workspace_id_check` on PR HEAD.
- [ ] AC2: `to_regclass('public.organizations')` returns NULL post-revert.
- [ ] AC3: `lifecycle.test.ts` 4-case suite exits 0 with errors null.
- [ ] AC4: Next push produces green `Tenant integration (dev-Supabase)` check.
- [ ] AC5: Unmerged-migration gate blocks `run-migrations.sh` without `ALLOW_UNMERGED_DEV_APPLY=1`.
- [ ] AC6: Drift probe in workflow exits 0 with no warning on clean dev.

### Post-merge (operator)
- [ ] AC7: Follow-up tracking issue opened against `feat-team-workspace-multi-user` for renumber-on-rebase.
