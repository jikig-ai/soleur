---
title: "Tasks — assert live byok RPC bodies in dev-migration-drift probe + self-diagnosing atomicity failure"
issue: 5920
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-03-feat-assert-byok-rpc-bodies-in-drift-probe-plan.md
---

# Tasks — #5920 byok RPC body drift guard

Derived from the finalized plan. See the plan for rationale, Research
Reconciliation (per-function marker map), and Sharp Edges.

## Phase 0 — Preconditions (verify, no code)
- [ ] 0.1 Confirm mig `084_byok_delegation_withdrawals.sql` is the highest-numbered `CREATE OR REPLACE FUNCTION public.check_and_record_byok_delegation_use` (through 121).
- [ ] 0.2 Confirm markers are executable-only (comment-strip then grep): `v_tripped := FOUND` + `FOR UPDATE` in mig 121; `FOR UPDATE` + `hourly_cap_exceeded` + `daily_cap_exceeded` in mig 084.
- [ ] 0.3 Confirm `pg_get_functiondef` returns a single overload per proname on dev (else Phase 1 iterates all oids).

## Phase 1 — Probe extension (deliverable 1)
- [ ] 1.1 `action.yml`: add inputs `sentry-dsn` (default `''`), `fail-on-rpc-body-drift` (default `'false'`); add output `rpc-body-drift-detected`.
- [ ] 1.2 New step `assert-byok-rpc-body-markers` after the ledger probe; per-function marker map; psql `pg_get_functiondef` query reusing the `sh -c` DATABASE_URL_POOLER pattern; 0-rows / >1-overload handling.
- [ ] 1.3 Comment-strip body (`sed 's/--.*//'`) before `grep -qF` marker match; accumulate misses; emit `::error::` with static literals only (fn + marker), set `rpc-body-drift-detected=true`.
- [ ] 1.4 Bash Sentry event emit per `web-platform-release.yml:893-933` (DSN parse, `store/` POST, tags `feature`/`op`/`fn`, extra `missing_marker`, 3-retry, DSN-unset/curl-fail → `::warning::`).
- [ ] 1.5 `exit 1` when `fail-on-rpc-body-drift=='true'` AND `rpc-body-drift-detected=='true'`.
- [ ] 1.6 `scheduled-dev-migration-drift.yml`: forward `sentry-dsn` + `fail-on-rpc-body-drift: 'true'`.
- [ ] 1.7 `tenant-integration.yml`: forward `sentry-dsn` (leave fail flag default `false`).

## Phase 2 — Structural source-side test (deliverable 1)
- [ ] 2.1 Create `apps/web-platform/test/supabase-migrations/byok-rpc-body-markers.test.ts` with `RPC_BODY_MARKERS` (same map as `action.yml`; cross-ref comment).
- [ ] 2.2 Glob migrations (exclude `.down.sql`), pick highest-numbered `CREATE OR REPLACE FUNCTION public.<fn>` (anchored regex), comment-strip, assert markers; `throw` fail-loud if no definer resolves (negative fixture).

## Phase 3 — Introspection RPC (deliverable 2, Option A)
- [ ] 3.1 Create `apps/web-platform/supabase/migrations/122_dev_pg_functiondef_introspection.sql` (+ `.down.sql`): `SECURITY DEFINER` `pg_functiondef(regprocedure) RETURNS text`, search_path pinned, REVOKE from PUBLIC/anon/authenticated, GRANT to service_role, `BEGIN;/COMMIT;`, no CONCURRENTLY.
- [ ] 3.2 deepen-plan: security-sentinel + data-integrity-guardian ratify grant scope; if rejected, pivot to Option B (porsager `postgres` devDep + `DATABASE_URL_POOLER`).

## Phase 4 — Self-diagnosing atomicity failure (deliverable 2)
- [ ] 4.1 In `byok-kill-switch.atomicity.tenant-isolation.test.ts` compute `willFail` (trippedCount !== 1 || any per-pair mismatch).
- [ ] 4.2 On `willFail`, fetch live body via `service.rpc("pg_functiondef", {...})` (guarded fallback string).
- [ ] 4.3 Embed live body in the `expect` **message** args only — no `.toBe`/`.toEqual` target changes (Invariant C stays strict).

## Phase 5 — Verify
- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 5.2 `./node_modules/.bin/vitest run test/supabase-migrations/byok-rpc-body-markers.test.ts` green.
- [ ] 5.3 `actionlint` the two workflows; `bash -c` syntax-check extracted `run:` snippets (NOT actionlint on the composite action.yml).
- [ ] 5.4 Probe snippet exercised via `bash -c` against all-markers + missing-marker fixtures.

## Phase 6 — Post-merge (automated)
- [ ] 6.1 Migration 122 applied to dev + prd via `web-platform-release.yml#migrate`; verify via `list_migrations` (both show 122).
- [ ] 6.2 `gh workflow run scheduled-dev-migration-drift.yml` → green, no false-positive body-marker `::error::`.
- [ ] 6.3 Live atomicity smoke (`TENANT_INTEGRATION_TEST=1`, dev) → green.
