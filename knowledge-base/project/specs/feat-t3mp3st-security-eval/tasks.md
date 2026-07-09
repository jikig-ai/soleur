---
feature: t3mp3st-security-eval
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-09-feat-rls-authz-fuzz-harness-plan.md
issue: 6256
---

# Tasks: Scoped runtime authz/RLS-fuzz harness

Coverage = full (RPC + storage.objects + CI), operator-selected 2026-07-09.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- The only "infra" is an ephemeral local Supabase-CLI Docker stack used as a disposable
     test DB — not provisioned servers/vendors/DNS/secrets. IaC routing gate N/A (ADR-103). -->

## Phase 0 — Local stack + faithfulness spike (riskiest first)
- [ ] 0.1 `supabase start` local stack; pin postgres/CLI image to the prod-matching version.
- [ ] 0.2 Apply all migrations to the local DSN (`supabase db reset` / `run-migrations.sh`).
- [ ] 0.3 Seed 2 synthetic workspaces (A, B) + 1 owner + `workspace_member` each (`*@example.test`, fixed UUIDs).
- [ ] 0.4 Spike gate (all must hold): inside `SET LOCAL ROLE authenticated` — `current_user='authenticated'`, `NOT rolsuper`, `NOT rolbypassrls`, `authenticated` does not own target tables; `auth.uid()`, `is_workspace_member`, one `*_jti_not_denied` policy all evaluate. Fail ⇒ stop.

## Phase 1 — Catalog-driven enumeration + per-table seeding
- [ ] 1.1 Enumerate isolation set from `pg_policies` (`TO authenticated` PERMISSIVE referencing `is_workspace_member`/tenancy predicate) ∪ jti-deny set (`%_jti_not_denied`).
- [ ] 1.2 Extract each table's isolation-key predicate from its policy `qual` (not hardcoded `workspace_id`).
- [ ] 1.3 Per table: as `service_role`, seed one tenant-A row; assert `service_role` reads `count=1` (precondition).

## Phase 2 — Core fuzz matrix (SQLSTATE-aware)
- [ ] 2.1 SELECT: tenant-B (`sub=userB`) reads `count=0` of A's seeded row.
- [ ] 2.2 INSERT/UPDATE/DELETE: attempt on A's row → assert SQLSTATE `42501`; any non-42501 = test ERROR; `service_role` re-read confirms A's row unchanged.
- [ ] 2.3 jti two-sided: denied jti blocked AND allowed jti permitted on same row.
- [ ] 2.4 Positive controls: tenant-A self-read `count=1`; `service_role` bypass. Claim-swap shown inert.
- [ ] 2.5 Mutation self-test: `DISABLE ROW LEVEL SECURITY` on one table (rolled back) ⇒ harness goes RED.

## Phase 2b — RPC bypass + storage.objects (full coverage)
- [ ] 2b.1 Enumerate `SECURITY DEFINER` fns `GRANT EXECUTE TO authenticated`; classify definer-vs-invoker (exclude invoker with rationale).
- [ ] 2b.2 Drive each definer fn with tenant-B claims + tenant-A params (`p_workspace_id=wsA`, etc.); assert denial/empty; fail on any uncovered definer fn.
- [ ] 2b.3 `storage.objects`: seed a tenant-A object; assert tenant-B cannot SELECT/UPDATE/DELETE via `storage.objects` (SQLSTATE-aware).

## Phase 3 — Prod-parity diff + report
- [ ] 3.1 `rls-parity-check.ts`: read prod catalog (pg_policies qual/with_check, relrowsecurity/relforcerowsecurity, grants to anon/authenticated, role attrs, `pg_get_functiondef` of auth.uid/jwt/is_workspace_member/jti helpers) via the `run-verify.sh` `doppler -c prd` psql path; diff vs local; any diff = red.
- [ ] 3.2 Per-`(table,op,verdict)` report; one leak/positive-control fail = hard FAIL + non-zero exit.

## Phase 4 — CI wiring
- [ ] 4.1 `.github/workflows/rls-authz-fuzz.yml`: on PRs touching `apps/web-platform/supabase/migrations/**` + manual dispatch; spin up Supabase-CLI local stack; run `test:rls-fuzz` + parity diff; red on leak/drift; local-only DSN.

## Phase 5 — Wiring, guards, ADR
- [ ] 5.1 `package.json`: add `test:rls-fuzz` + `rls:parity` (vitest / node; local DSN only).
- [ ] 5.2 DSN fail-closed allowlist (localhost/127.0.0.1/::1/CI host; parse-host, no DNS); unit test.
- [ ] 5.3 Author `ADR-103-runtime-authz-rls-fuzz-harness.md` (decision + `## Alternatives Considered`; no C4 change; no deferred blind spots).

## Phase 6 — Verify
- [ ] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 6.2 `./node_modules/.bin/vitest run test/rls-authz-fuzz.integration.test.ts` green against local stack; parity diff clean.
- [ ] 6.3 All ACs (AC1–AC13) checked.
