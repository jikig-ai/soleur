# Tasks — feat-one-shot-10764-tenant-integration-red

Plan: `knowledge-base/project/plans/2026-10-26-fix-tenant-integration-session-sync-57014-plan.md`
Issue: #10764 (Red on main: tenant-integration)

## Phase 1 — Migration

- [ ] 1.1 Resolve next free migration prefix on fresh `origin/main` (`ls apps/web-platform/supabase/migrations/ | sort -n | tail`; beware in-flight prefixes: 164 git-data-erasure, 165–175 codex, 174/175 supabase-grants).
- [ ] 1.2 Create `apps/web-platform/supabase/migrations/NNN_users_restrictive_policy_subqueries.sql`:
  - three `plpgsql STABLE SECURITY INVOKER SET search_path = pg_catalog, public, pg_temp` functions (`users_own_health_snapshot()` → jsonb, `users_own_github_username()` → text, `users_own_kb_sync_history()` → jsonb), each a parameterized `SELECT <col> INTO v FROM public.users WHERE id = auth.uid()`; `REVOKE ALL … FROM PUBLIC`, `GRANT EXECUTE … TO authenticated`.
  - `DROP POLICY IF EXISTS` + `CREATE POLICY` (same names) with the self-subquery replaced by the function call, preserving USING/WITH-CHECK shapes verbatim.
- [ ] 1.3 Create `NNN_...down.sql` restoring the three original subquery policies + dropping the functions.
- [ ] 1.4 Create `apps/web-platform/supabase/verify/NNN_users_restrictive_policy_subqueries.sql` asserting: 3 functions exist, 3 policies exist by name, `pg_get_expr` references `users_own_`.

## Phase 2 — Verification

- [ ] 2.1 Apply to dev via the PR's own tenant-integration run (`ALLOW_UNMERGED_DEV_APPLY`), or manually via session-mode psql (`:5432`, never `:6543`).
- [ ] 2.2 Rolled-back reproducer under `statement_timeout='8s'` as `authenticated` → `UPDATE 0` in <1s, no `Seq Scan` InitPlan in `EXPLAIN`.
- [ ] 2.3 `doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/server/session-sync.tenant-isolation.test.ts` → green.
- [ ] 2.4 Self-update changed-value check: authenticated UPDATE of own `kb_sync_history` still rejected (deny semantics preserved).
- [ ] 2.5 Optional: one-line comment in `session-sync.tenant-isolation.test.ts` noting this incident + migration.
- [ ] 2.6 Optional manual unblock if needed before merge: `REVOKE UPDATE ON TABLE public.users FROM authenticated;` on dev restores the 42501 path (emergency note only, see plan Cut List).

## Phase 3 — Follow-ups

- [ ] 3.1 File issue: dev catalog-posture probe (grants/policies vs migration corpus) — the drift probe only watches `_schema_migrations`.
- [ ] 3.2 Comment/link on PR #11180's narrowing follow-up re: `users` table-level UPDATE wart (this incident as evidence).
- [ ] 3.3 File issue: dev `public.users` synthetic-fixture bloat (~295k rows) teardown sweep.
