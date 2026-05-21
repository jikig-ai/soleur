---
title: dev-Supabase drift from unmerged feature-branch migrations breaks tenant-integration CI
date: 2026-05-21
category: database-issues
tags: [database-issues, web-platform, supabase, ci, dev-environment, high]
---

# Learning: dev-Supabase drift from unmerged feature-branch migrations breaks tenant-integration CI

## Problem

The `Tenant integration (dev-Supabase)` GitHub Actions workflow on `main` went red at 2026-05-21T10:46Z and stayed red across 4 consecutive runs. Every `*.tenant-isolation.test.ts` suite (15+ files) failed in `beforeAll` with:

```
new row for relation "scope_grants" violates check constraint "scope_grants_workspace_id_check"
```

The constraint did not exist in any migration on `origin/main`. It existed only in commit `5c2696d4` on the unmerged `feat-team-workspace-multi-user` branch (migration 055), which had been applied to dev-Supabase via `DATABASE_URL_POOLER` to support that branch's own local iteration. Migrations 053-057 from that branch were live on dev; none were on main. The dev schema was strictly ahead of main, and every `grant_action_class` call from main's RPC body wrote `workspace_id = NULL`, which the new CHECK rejected.

A second drift class compounded the failure: migration 057 (`057_byok_audit_workspace_id_rpcs.sql`, commit `c26e7053`) had also been applied to dev, widening `write_byok_audit` to a 6-parameter signature with `p_workspace_id`. PostgREST's schema cache then advertised only the 6-param overload; tests on main calling the 5-param signature received `PGRST202 "Could not find the function"`.

## Investigation

1. Initial triage hypothesis from issue #4241 named the failing CHECK as `scope_grants_tier_check` or `scope_grants_action_class_not_locked` — pattern-matching against the most-recently-touched constraints on main. Both were wrong.
2. `gh run view 26225869534 --log-failed` surfaced the actual constraint name in the PostgreSQL error message body: `scope_grants_workspace_id_check`.
3. `grep -rn scope_grants_workspace_id_check apps/web-platform/supabase/migrations/` on main returned 0 matches.
4. `git log --all -G scope_grants_workspace_id_check` traced the constraint to commit `5c2696d4` on `feat-team-workspace-multi-user`, never merged to main.
5. Reading that branch's `tasks.md` (`1a5cc259`) confirmed migrations 053-056 had been applied to dev with backfill counts logged.
6. After reverting 053-056, a second suite (`cross-tenant-read-denied`) failed with `PGRST202` on `write_byok_audit`. `SELECT oid::regprocedure FROM pg_proc WHERE proname = 'write_byok_audit'` returned only the 6-param signature — coming from migration 057 on the same branch (commit `c26e7053`), also applied to dev. Reverting 057 restored the 5-param signature and tests passed.

## Root cause

There was no workflow gate preventing `apps/web-platform/scripts/run-migrations.sh` from applying migrations whose filenames are not on `origin/main`. Operators iterating on multi-PR features (like `feat-team-workspace-multi-user`) applied migrations to dev via direct `psql` to validate their work locally, with no mechanism to surface that drift back to `main`-tracking CI runs. The shared dev-Supabase project amplified the impact: the next CI run on `main` ran against whatever schema dev happened to have, not against the schema expressed by `origin/main`.

## Fix

Two-part remediation:

### Part 1 — Restore dev to main's schema (operational)

In strict reverse order (which the down-migrations encode), applied paired `.down.sql` files via `psql` over the Doppler-injected `DATABASE_URL_POOLER` rewritten from transaction-mode `:6543` to session-mode `:5432` (multi-statement DDL requires session mode):

```
056_current_organization_jwt_hook.down.sql
055_workspace_keyed_rls_sweep.down.sql
054_workspace_member_attestations.down.sql
053_organizations_and_workspace_members.down.sql
057_byok_audit_workspace_id_rpcs.down.sql   # discovered after the first revert + re-test
```

`_schema_migrations` rows for the unmerged filenames were deleted (in this case 0 rows existed — the team-workspace apply path used direct `psql` without inserting tracking rows). `NOTIFY pgrst, 'reload schema'` was issued to flush the PostgREST function-signature cache.

### Part 2 — Workflow gate + drift probe (durable)

- **Apply-time gate (`apps/web-platform/scripts/run-migrations.sh`):** before the `already_applied` check inside the apply loop, `git ls-tree origin/main -- apps/web-platform/supabase/migrations/<filename>` is checked. Empty result means the filename is not on main; the runner exits 1 with `::error::` unless `ALLOW_UNMERGED_DEV_APPLY=1` (opt-in operator ack mirroring `hr-menu-option-ack-not-prod-write-auth`). A single `git fetch --quiet origin main` runs once before the loop so the local fetch state is current; failures are tolerated so the runner is usable offline.
- **Runtime drift probe (`.github/workflows/tenant-integration.yml`):** before `Apply migrations to dev`, the workflow reads `SELECT filename FROM public._schema_migrations`, cross-references each row against `git ls-tree origin/main`, and emits `::warning::` annotations (not `::error::`) for any rows whose file is not on main. Warning severity is intentional — it surfaces drift on every CI run without blocking the local-iteration valve the apply-time gate intentionally opens.

The two layers are complementary: the gate catches future drift attempts via the runner; the probe catches residual drift left by direct `psql` applies that bypass the runner entirely.

## Key takeaways

1. **The PostgreSQL error message body is the canonical disambiguator.** Issue #4241 named the wrong CHECK because the operator pattern-matched against recently-touched constraints. The actual constraint name is in the SQLSTATE 23514 message body verbatim (`new row for relation "X" violates check constraint "Y"`). Always read the error message before hypothesizing.
2. **Revert + re-test surfaces compound drift.** The first revert (053-056) unmasked a second drift class (057's RPC signature widening) that was hidden behind the first failure. Plan reverts in iterations: revert, re-run the suite, observe the next failure mode, repeat.
3. **`_schema_migrations` is filename-keyed, not content-keyed.** Two `053_*.sql` files with different names coexist as distinct rows; the runner happily applies both. The convention (one migration per integer prefix) is enforced only by reviewer discipline at PR time. Once a feature branch with the same prefix as `main`'s newest migration lands, renumber-on-rebase is a hard requirement.
4. **Shared dev-Supabase projects amplify per-branch drift.** A feature branch's local iteration writes to the same project that `main`-tracking CI reads from. The two-layer gate (apply-time + runtime probe) is the structural fix; no amount of operator discipline closes the gap permanently.
5. **PostgREST schema cache lag.** RPC signature changes via `DROP FUNCTION ... CREATE FUNCTION` (vs `CREATE OR REPLACE` overloading) can leave PostgREST advertising a stale schema for ~seconds to minutes. `NOTIFY pgrst, 'reload schema'` forces an immediate refresh. For rolling-deploy-safe RPC changes, prefer overloading (additive `CREATE OR REPLACE` with a distinct parameter list) per learning `2026-05-12-stub-handlers-as-silent-undercount-vectors.md`.
6. **Pooler port determines DDL capability.** `DATABASE_URL_POOLER` on Supabase pooler `:6543` is transaction-mode and rejects multi-statement DDL with SQLSTATE 42601. Rewrite to `:5432` for session mode whenever a migration file contains `BEGIN; ... COMMIT;` blocks or multiple top-level statements.

## References

- Issue: #4241
- Commits: `5c2696d4` (feat-team-workspace-multi-user Phase 1, migrations 053-056), `c26e7053` (Phase 3, migration 057), `1a5cc259` (tasks.md dev-apply log), `2092b9b4` (PR-I merge with same-prefix 053).
- Workflow gate: `apps/web-platform/scripts/run-migrations.sh` (apply-time check).
- Drift probe: `.github/workflows/tenant-integration.yml` (runtime annotation).
- Related hard rules: `hr-dev-prd-distinct-supabase-projects`, `hr-menu-option-ack-not-prod-write-auth`, `hr-no-ssh-fallback-in-runbooks`, `hr-no-dashboard-eyeball-pull-data-yourself`.
- Related workflow gates: `wg-when-a-workflow-gap-causes-a-mistake-fix`.
- Sibling learning: `2026-03-28-unapplied-migration-command-center-chat-failure.md` (same class — schema-vs-code drift, different direction).
