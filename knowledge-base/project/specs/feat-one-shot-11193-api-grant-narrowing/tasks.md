# Tasks: chore(supabase): narrow default-era api-role table grants (#11193)

Plan: `knowledge-base/project/plans/2026-10-26-chore-narrow-default-era-api-grants-plan.md`

## Phase 1: Setup (census verification + RED)

- [ ] 1.1 Re-run the `_schema_migrations` reader census: `git grep -rn "_schema_migrations" -- apps/web-platform | grep -vE "migrations/|verify/|test/"` and classify every reader's client binding (psql `DATABASE_URL` vs api-role client). Result decides INTERNAL vs `service_role`-only for that relation (plan Note A).
- [ ] 1.2 Re-run the `users` authenticated-write census (plan Note C): every `.from("users").update|.upsert` call site classified by client binding (`createClient` cookie / `lib/supabase/client` browser / `getFreshTenantClient` tenant / service), every SECURITY INVOKER function touching `users`, every `.rpc(` reaching a `users` write. Minimum known set: `email`, `onboarding_completed_at`, `pwa_banner_dismissed_at`, `runtime_explainer_dismissed_at`, `nudges_dismissed`.
- [ ] 1.3 Verify the migration number is still free: `git ls-tree --name-only origin/main apps/web-platform/supabase/migrations/ | tail` + `gh pr list --state open --json files` sweep — take the next free number (planned: 178; 176 = PR #11224, 177 = PR #11115).
- [ ] 1.4 Write `apps/web-platform/test/supabase-migrations/178-api-data-grants-narrowing.test.ts` (RED): asserts per-relation `to_regclass` preconditions, REVOKE-before-re-GRANT ordering inside each DO block, one `check_name` row per relation in the verify file, and the census column list in the `users` GRANT.

## Phase 2: Core Implementation (GREEN)

- [ ] 2.1 Create `apps/web-platform/supabase/migrations/178_api_data_grants_narrowing.sql`: per-relation `DO $$ to_regclass` blocks — `REVOKE ALL … FROM anon, authenticated` (+ `FROM service_role` on `_schema_migrations` only if 1.1 confirms INTERNAL); re-GRANT `SELECT` to `authenticated` on `api_keys`, `audit_byok_use`, `audit_github_token_use`, `dsar_export_jobs`; `GRANT SELECT` + `GRANT UPDATE(<census cols>)` to `authenticated` on `users`; header comment carrying per-relation evidence one-liners (175 convention).
- [ ] 2.2 Create `apps/web-platform/supabase/migrations/178_api_data_grants_narrowing.down.sql` restoring the exact 174 verb sets.
- [ ] 2.3 Create `apps/web-platform/supabase/verify/178_api_data_grants_narrowing.sql`: `check_name`/`bad` rows — revoked verbs → 0 held per relation per role; kept grants held (`service_role` full set, `authenticated` SELECT, per-column `has_column_privilege` on `users`, `NOT has_table_privilege('authenticated','users','UPDATE')`).
- [ ] 2.4 Update `apps/web-platform/test/rls-fuzz/table-grants.ts`: OVERRIDES entries per the decision matrix — `INTERNAL`-kind for `_schema_migrations` (OVERRIDES, not the `INTERNAL` map — it collides with the parsed snapshot entry, plan Note A), `EXPOSED` with narrowed sets for the rest; provenance cites migration 178 + #11193.
- [ ] 2.5 Reroute `server/session-sync.ts` `recordKbSyncHistory` through `append_kb_sync_row` (`p_cap: 14`, `{date,count}` row shape) — pending ruling, assumed per plan Note B; fallback: add `kb_sync_history` to the column census.
- [ ] 2.6 Header evidence comments finalized in the migration file.

## Phase 3: Testing

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/supabase-migrations/178-api-data-grants-narrowing.test.ts` green.
- [ ] 3.2 `bash apps/web-platform/scripts/lint-migration-api-grants.sh --from-pr-diff` green.
- [ ] 3.3 `RLS_FUZZ_LOCAL=1` rls-grants gate green on a replayed stack (held==registered for all eight relations).
- [ ] 3.4 Dev rehearsal: apply 178 → `run-verify.sh` all `bad=0` → apply `.down.sql` → verify/174 rows pass → re-apply 178 → verify/178 `bad=0`; evidence in PR body.
- [ ] 3.5 Regression: the four authenticated SELECT surfaces (audit, audit/github, privacy, services) + `use-onboarding` dismissals + team-names nudge return no 42501 on the dev stack.
- [ ] 3.6 Confirm no file collision with PR #11224 (`176_*`, `rpc-cases.ts`, `dev-ledger-parity.test.sh`) and no edit to `174_api_data_grants_snapshot.sql`.
