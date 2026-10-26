# Tasks — feat-one-shot-supabase-public-grants

Plan: `knowledge-base/project/plans/2026-10-26-feat-supabase-public-schema-grants-plan.md`
Deadline driver: Supabase Data API auto-grant flip on 2026-10-30.

## Phase 0 — Preconditions

- [ ] 0.1 Verify `auto_expose_new_tables` key support on pinned Supabase CLI 2.84.2 (`supabase/cli#5524`, securing-your-api docs); annotate the chosen mechanism in the plan/PR per the CLI-verification gate.
- [ ] 0.2 Confirm next free migration number is still 164 (re-scan `ls apps/web-platform/supabase/migrations/`); renumber up/down/verify trio together if a sibling landed.
- [ ] 0.3 Confirm ADR-303 is still the next free ADR ordinal against `origin/main` and pushed branches (probe all `origin/*` refs).
- [ ] 0.4 Resolve `decision-challenges.md` pending rulings: CPO sign-off (`requires_cpo_signoff: true`) MUST land before implementation begins.

## Phase A — Audit + snapshot generation

- [ ] 1.1 Create `apps/web-platform/scripts/dump-api-grants.sh` (or `.ts` matching `rls-parity-check.ts` conventions): read-only extraction over `information_schema.role_table_grants` + `column_privileges` + `role_usage_grants` for grantees `anon`/`authenticated`/`service_role`, all `public` relations (relkind r,v,m,S). Emit (a) GRANT DDL reproducing effective state (table-level where held; per-column where table-level revoked — the 006/079 shapes) and (b) per-relation classification block (RLS enabled? policies? serial/identity?).
- [ ] 1.2 Run the extraction via `doppler run -c prd` (read-only, the run-verify access class).
- [ ] 1.3 Hand-review the generated matrix; produce the narrowing follow-up list (relations holding default-era anon/auth grants with no evidence of API consumers).

## Phase B — Backfill migration + sentinel

- [ ] 2.1 Write `apps/web-platform/supabase/migrations/164_api_data_grants_snapshot.sql`: provenance header (generator + date + command), `to_regclass` preconditions per FK-lint convention, generated GRANT DDL grouped by relation with classification annotations. Transaction-safe DDL only (GRANT, no CONCURRENTLY-class constructs).
- [ ] 2.2 Write `164_api_data_grants_snapshot.down.sql` — documented no-op (see plan Technical Considerations; REVOKE-down is unsafe on prd).
- [ ] 2.3 Write `apps/web-platform/supabase/verify/164_api_data_grants_snapshot.sql` — per-relation `has_table_privilege`/`has_column_privilege`/`has_sequence_privilege` assertions for the full registered set; idempotent (verify-migrations re-runs it).

## Phase C — Local-stack parity pin

- [ ] 3.1 Set `auto_expose_new_tables = false` under `[api]` in `apps/web-platform/supabase/config.toml` (or implement the `supabase-local.sh` normalize fallback if 0.1 refutes the key).
- [ ] 3.2 Add a fuzz-side assertion that the local stack's `pg_default_acl` carries no api-role default table grants (the P6 faithfulness pin).

## Phase D — Guards

- [ ] 4.1 Create `apps/web-platform/test/rls-fuzz/table-grants.ts` — registry mirroring `rpc-cases.ts`: per public relation + sequence, `EXPOSED: { role: Set<verb> }` or `INTERNAL` with reason citing the Phase-A audit.
- [ ] 4.2 Edit `apps/web-platform/test/rls-fuzz/catalog.ts` — add `publicApiRelations()` + `publicApiSequences()` enumerators from `pg_class`.
- [ ] 4.3 Create `apps/web-platform/test/rls-fuzz/rls-grants.integration.test.ts` — gate asserting registered grant state per catalog member + catalog⇔registry parity. Red-proof: unclassified relation reds; mis-granted member reds.
- [ ] 4.4 Create `apps/web-platform/scripts/lint-migration-api-grants.sh` + `.test.sh` — noise-stripping detector (comments/dollar-bodies/strings, per `definer-grants.ts:100` precedent); per-relation GRANT-or-sentinel requirement + sequence arm; `.down.sql` skipped; cover the plan's Guard-1 mutation-matrix rows.
- [ ] 4.5 Edit `.github/workflows/tenant-integration.yml` — add `bash scripts/lint-migration-api-grants.sh --from-pr-diff` beside the FK-precondition step (~line 386).

## Phase E — Decision record + deferral

- [ ] 5.1 Author `knowledge-base/engineering/architecture/decisions/ADR-303-explicit-data-api-grants-and-two-tier-table-grant-guard.md` + reciprocal cross-ref into ADR-112's header.
- [ ] 5.2 File the grant-narrowing follow-up issue (Phase-A audit list attached; relates #4027; labels `domain/engineering`, `type/chore`).
- [ ] 5.3 Sweep `grep -rn 'ADR-303\|164_api_data_grants' knowledge-base/project/{plans,specs}/feat-one-shot-supabase-public-grants/` if renumbering occurred in 0.2/0.3.

## Verification (maps to plan ACs)

- [ ] 6.1 `bun run test:rls-fuzz` green including rls-grants gate (AC3, AC5, AC10).
- [ ] 6.2 `bash apps/web-platform/scripts/lint-migration-api-grants.test.sh` green (AC4).
- [ ] 6.3 Fixture red-proofs: ungranted create-table reds lint; unregistered relation reds fuzz gate (Guard matrices).
- [ ] 6.4 `verify/164` passes under `run-verify.sh` post-apply on prd; `rls-parity-check.ts` role_table_grants diff clean (AC2, AC6).
- [ ] 6.5 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean on edited TS files.
