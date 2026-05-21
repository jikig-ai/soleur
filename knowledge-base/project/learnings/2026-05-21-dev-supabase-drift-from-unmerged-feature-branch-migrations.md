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

**Step 0 — obtain the `.down.sql` files.** The paired down-migrations live on the originating feature branch (here `feat-team-workspace-multi-user`), NOT on `main`. An agent or operator running this procedure from a `main` checkout must first fetch the branch or read directly from the commits that introduced the forward migrations:

```bash
# Option A — fetch the branch (works while it exists):
git fetch origin feat-team-workspace-multi-user
git show origin/feat-team-workspace-multi-user:apps/web-platform/supabase/migrations/056_current_organization_jwt_hook.down.sql > /tmp/down-056.sql

# Option B — fetch by introducing commit SHA (works even if the branch is deleted):
git show 5c2696d4:apps/web-platform/supabase/migrations/056_current_organization_jwt_hook.down.sql > /tmp/down-056.sql
# 5c2696d4 introduced 053-056; c26e7053 introduced 057.
```

**Step 1 — apply the down-migrations in strict reverse order** (which the down-migrations encode) via `psql` over the Doppler-injected `DATABASE_URL_POOLER` rewritten from transaction-mode `:6543` to session-mode `:5432` (multi-statement DDL requires session mode):

```
056_current_organization_jwt_hook.down.sql
055_workspace_keyed_rls_sweep.down.sql
054_workspace_member_attestations.down.sql
053_organizations_and_workspace_members.down.sql
057_byok_audit_workspace_id_rpcs.down.sql   # discovered after the first revert + re-test
```

**Step 2 — reconcile `_schema_migrations`.** Delete tracking rows for the unmerged filenames so the runner re-applies them once they land on main. In this incident, 0 rows existed because the team-workspace apply path used direct `psql` without inserting tracking rows; that is exactly the blind spot Part 2's runtime probe inherits (see below). `NOTIFY pgrst, 'reload schema'` flushes the PostgREST function-signature cache and is required when any RPC's signature changed.

### Part 2 — Workflow gate + drift probe (durable)

- **Apply-time gate (`apps/web-platform/scripts/run-migrations.sh`):** before the `already_applied` check inside the apply loop, `git ls-tree origin/main -- apps/web-platform/supabase/migrations/<filename>` is checked. Empty result means the filename is not on main; the runner exits 1 with `::error::` unless `ALLOW_UNMERGED_DEV_APPLY=1` (opt-in operator ack for the local-iteration valve; dev is unshared and synthetic-only per `hr-dev-prd-distinct-supabase-projects`, so this is distinct from the prd-only ack class governed by `hr-menu-option-ack-not-prod-write-auth`). A single `git fetch origin main` runs once before the loop so the local fetch state is current; failures emit a visible warning so a stale ref does not silently route every file through the ack-bypass path.
- **Runtime drift probe (`.github/workflows/tenant-integration.yml`):** before `Apply migrations to dev`, the workflow reads `SELECT filename FROM public._schema_migrations`, cross-references each row against `git ls-tree origin/main`, and emits `::warning::` annotations (not `::error::`) for any rows whose file is not on main. Warning severity is intentional — it surfaces drift on every CI run without blocking the local-iteration valve the apply-time gate intentionally opens.

**Known coverage gaps** (intentional, not bugs):

1. **Direct-`psql` DDL is invisible to the probe.** The probe reads `_schema_migrations` and trusts that table as the catalog of applied DDL. The original incident left ZERO rows in `_schema_migrations` because the team-workspace apply path used direct `psql` without inserting tracking rows — so the probe, as designed, would NOT have detected the very incident that motivated it. The apply-time gate closes this for future runner-mediated applies; operators using direct `psql` for local iteration must manually revert before pushing to a branch that triggers tenant-integration. A future iteration could compare against `pg_catalog` introspection (table/constraint/function shape vs. a hash of on-main migration content) to close this entirely — out of scope here.
2. **Filename-identity, not content-identity.** `git ls-tree origin/main` returns a blob entry for matching filenames regardless of whether the dev-applied body matches main's body. A migration renamed-and-resubmitted under a new prefix surfaces as drift on the OLD name (benign false-positive — cleaning up the stale tracking row is the right move). Content drift (same filename, different body) is silent. A `content_sha256` column on `_schema_migrations` would close this; out of scope here.
3. **Same-integer-prefix collision is not caught.** Multiple `NNN_*.sql` files with distinct names (e.g., main already has both `053_append_kb_sync_row_rpc.sql` and `053_template_authorizations.sql`) coexist in `_schema_migrations` as distinct rows and apply in alphabetical order. The convention "one migration per integer prefix" is enforced only by reviewer discipline at PR time.

The two layers are complementary FOR runner-mediated drift: the gate catches future drift attempts via the runner; the probe catches residual drift left by past runner-mediated applies. Both are blind to direct-`psql` bypass (gap 1) and to content drift (gap 2).

## Key takeaways

1. **The PostgreSQL error message body is the canonical disambiguator.** Issue #4241 named the wrong CHECK because the operator pattern-matched against recently-touched constraints. The actual constraint name is in the SQLSTATE 23514 message body verbatim (`new row for relation "X" violates check constraint "Y"`). Always read the error message before hypothesizing.
2. **Revert + re-test surfaces compound drift.** The first revert (053-056) unmasked a second drift class (057's RPC signature widening) that was hidden behind the first failure. Plan reverts in iterations: revert, re-run the suite, observe the next failure mode, repeat.
3. **`_schema_migrations` is filename-keyed, not content-keyed; shared dev amplifies drift.** Two `053_*.sql` files with different names coexist as distinct rows and the runner applies both; a feature branch's local iteration writes to the same project that `main`-tracking CI reads from. Once a feature branch with the same prefix as `main`'s newest migration lands, renumber-on-rebase is a hard requirement. The two-layer gate is the structural fix for the "branch wrote to dev" half; operator discipline is the only fix for the "same-prefix collision" half until a runner-side assertion lands.
4. **PostgREST schema cache lag.** RPC signature changes via `DROP FUNCTION ... CREATE FUNCTION` (vs `CREATE OR REPLACE` overloading) can leave PostgREST advertising a stale schema for ~seconds to minutes. `NOTIFY pgrst, 'reload schema'` forces an immediate refresh. For rolling-deploy-safe RPC changes, prefer overloading (additive `CREATE OR REPLACE` with a distinct parameter list) per learning `2026-05-12-stub-handlers-as-silent-undercount-vectors.md`.
5. **Pooler port determines DDL capability.** `DATABASE_URL_POOLER` on Supabase pooler `:6543` is transaction-mode and rejects multi-statement DDL with SQLSTATE 42601. Rewrite to `:5432` for session mode whenever a migration file contains `BEGIN; ... COMMIT;` blocks or multiple top-level statements.

## References

- Issue: #4241
- Commits: `5c2696d4` (feat-team-workspace-multi-user Phase 1, migrations 053-056), `c26e7053` (Phase 3, migration 057), `1a5cc259` (tasks.md dev-apply log), `2092b9b4` (PR-I merge with same-prefix 053).
- Workflow gate: `apps/web-platform/scripts/run-migrations.sh` (apply-time check).
- Drift probe: `.github/workflows/tenant-integration.yml` (runtime annotation).
- Related hard rules: `hr-dev-prd-distinct-supabase-projects`, `hr-menu-option-ack-not-prod-write-auth`, `hr-no-ssh-fallback-in-runbooks`, `hr-no-dashboard-eyeball-pull-data-yourself`.
- Related workflow gates: `wg-when-a-workflow-gap-causes-a-mistake-fix`.
- Sibling learning: `2026-03-28-unapplied-migration-command-center-chat-failure.md` (same class — schema-vs-code drift, different direction).
