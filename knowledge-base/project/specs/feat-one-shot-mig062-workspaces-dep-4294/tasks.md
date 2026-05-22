---
plan: knowledge-base/project/plans/2026-05-22-fix-tenant-integration-mig062-workspaces-schema-vs-ledger-drift-4338-plan.md
issue: 4338
branch: feat-one-shot-mig062-workspaces-dep-4294
lane: cross-domain
date: 2026-05-22
---

# Tasks: fix(ci) tenant-integration mig 062 schema-vs-ledger drift (#4338)

## Phase 0 — Preconditions
- [x] 0.1 Confirm CWD is `.worktrees/feat-one-shot-mig062-workspaces-dep-4294` and branch matches.
- [x] 0.2 Grep `apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql` for `CREATE TABLE IF NOT EXISTS public.workspaces` (expected: line 61).
- [x] 0.3 Verify Doppler `dev_scheduled` → `environment=dev` (`doppler configs get dev_scheduled -p soleur`).

## Phase 0.5 — Operator-paced: schema-vs-ledger inspection
- [x] 0.5.1 Snapshot dev `_schema_migrations` rows for 053-062 window; paste into PR body `<details>` block.
- [x] 0.5.2 Snapshot dev `to_regclass()` for organizations/workspaces/workspace_members/workspace_member_attestations/workspace_member_removals.
- [x] 0.5.3 Choose resolution branch A (DELETE stale ledger rows, let CI re-apply) or B (manual forward apply); apply.
- [x] 0.5.4 Re-run 0.5.2; confirm all 5 relations non-NULL.

## Phase 1 — Confirm green tenant-integration
- [ ] 1.1 Trigger fresh `gh workflow run tenant-integration.yml --ref feat-one-shot-mig062-workspaces-dep-4294`; wait for green.
- [ ] 1.2 Spot-check PR-J-added DSAR test suites (workspace-member-removals tenant-isolation, anonymise-removal-cascade — verify files exist before running).

## Phase 2 — Code fix: 062 precondition
- [x] 2.1 Prepend `DO $$ … RAISE EXCEPTION` precondition block to `apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql` asserting `to_regclass('public.workspaces') IS NOT NULL`.
- [ ] 2.2 Verify precondition fires correctly via transaction-scoped test against dev (BEGIN; DROP TABLE; assert NOTICE; ROLLBACK).

## Phase 3 — Apply-time defense: schema-presence probe in run-migrations.sh
- [x] 3.1 RED: write failing test in `apps/web-platform/scripts/lib/run-migrations-schema-probe.test.sh` that synthesizes a migration referencing a missing relation and asserts probe-mode runner exits non-zero.
- [x] 3.2 GREEN: add the `MIGRATION_SCHEMA_PRECONDITION_PROBE=1` opt-in probe to `apps/web-platform/scripts/run-migrations.sh` (between already-applied skip and `echo "Applying:"`).
- [x] 3.3 REFACTOR: ensure probe is best-effort (parse-failure does NOT block — falls through to FK parser).

## Phase 4 — Visibility: workflow preflight
- [x] 4.1 Add `Preflight schema-vs-ledger consistency check` step to `.github/workflows/tenant-integration.yml`, between drift-probe and apply-migrations steps; fail-loud on any `CREATE TABLE public.<name>` that is missing from dev while its parent migration's `_schema_migrations` row exists.
- [x] 4.2 Wire `MIGRATION_SCHEMA_PRECONDITION_PROBE=1` env var into the existing `Apply migrations to dev` step.

## Phase 5 — Documentation
- [x] 5.1 Write `knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md` (symptom, root cause, misdiagnosis trap, fix, generalized recipe).
- [x] 5.2 Add forward-pointer to new learning from `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`.

## Phase 6 — Ship
- [ ] 6.1 `/soleur:preflight` (mandatory pre-ship checks).
- [ ] 6.2 `/soleur:review` (multi-agent).
- [ ] 6.3 `/soleur:qa` (functional QA).
- [ ] 6.4 `/soleur:ship` (commit + PR + mark ready).
- [ ] 6.5 Post-merge: file follow-up tracking issue for `git fetch origin main` reliability gap (AC8).
- [ ] 6.6 Post-merge: verify prd unaffected via `gh workflow run web-platform-release.yml --ref main` (AC9).
