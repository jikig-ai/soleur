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
- [ ] 1.1 `action.yml`: add inputs `sentry-dsn` (default `''`), `fail-on-rpc-body-drift` (default `'false'`); add output `rpc-body-drift-detected`. Read the marker map from shared `byok-rpc-markers.json` via `jq`; add a "fn allowlist / marker map is compile-time static" comment.
- [ ] 1.2 New step `assert-byok-rpc-body-markers` after the ledger probe; psql `pg_get_functiondef` query reusing the `sh -c` DATABASE_URL_POOLER pattern; 0-rows / >1-overload handling.
- [ ] 1.3 Comment-strip body (`sed 's/--.*//'`) before `grep -qF` marker match; accumulate misses; set `rpc-body-drift-detected=true`. **Severity tracks `fail-on-rpc-body-drift`:** true → `::error::` (static literals only) + Sentry; false → `::warning::`, no Sentry.
- [ ] 1.4 Bash Sentry event emit per `web-platform-release.yml:893-933` (DSN parse, `store/` POST, tags `feature`/`op`/`fn`, extra `missing_marker`, **static** `message`, 3-retry, DSN-unset/curl-fail → `::warning::`) — invoked ONLY when `fail-on-rpc-body-drift=='true'`.
- [ ] 1.5 `exit 1` when `fail-on-rpc-body-drift=='true'` AND `rpc-body-drift-detected=='true'`.
- [ ] 1.6 `scheduled-dev-migration-drift.yml`: forward `sentry-dsn` + `fail-on-rpc-body-drift: 'true'` (sole Sentry + fail authority).
- [ ] 1.7 `tenant-integration.yml`: do NOT forward `sentry-dsn`; leave fail flag default `false` (PR CI = `::warning::`-only). Verify whether any edit is needed at all.

## Phase 2 — Shared marker map + structural source-side test (deliverable 1)
- [ ] 2.1 Create `apps/web-platform/test/supabase-migrations/byok-rpc-markers.json` (single source of truth; shape per plan Phase 2).
- [ ] 2.2 Create `byok-rpc-body-markers.test.ts` importing that JSON; glob migrations (exclude `.down.sql`), pick highest-numbered `CREATE OR REPLACE FUNCTION public.<fn>` (anchored regex), comment-strip, assert markers are body-resident; `throw` fail-loud if no definer resolves (negative fixture).

## Phase 3 — Introspection mechanism (deliverable 2, Option B primary)
- [ ] 3.1 (Option B primary) Add `postgres` (porsager) to `apps/web-platform/package.json` devDependencies + commit lockfile (`cq-before-pushing-package-json-changes`).
- [ ] 3.2 (Option A fallback only, if devDep rejected) Create `122_dev_functiondef_introspection.sql` (+ `.down.sql`): `SECURITY DEFINER` `dev_functiondef(regprocedure) RETURNS text` (NOT `pg_`-prefixed), search_path pinned, REVOKE from PUBLIC **+ anon + authenticated** explicitly, GRANT to service_role, `BEGIN;/COMMIT;`, no CONCURRENTLY.

## Phase 4 — Self-diagnosing atomicity failure (deliverable 2)
- [ ] 4.1 In `byok-kill-switch.atomicity.tenant-isolation.test.ts` compute `willFail` (trippedCount !== 1 || any per-pair mismatch).
- [ ] 4.2 On `willFail`, fetch live body — Option B: porsager `sql\`SELECT pg_get_functiondef('...'::regprocedure)\`` over `DATABASE_URL_POOLER`; Option A: `service.rpc("dev_functiondef", {...})`. Guarded fallback string on error.
- [ ] 4.3 Embed live body in the `expect` **message** args only — no `.toBe`/`.toEqual` target changes (Invariant C stays strict).
- [ ] 4.4 File a follow-up tracking issue (label `observability`) for a delegation-RPC semantic/atomicity test (no live semantic backstop today).

## Phase 5 — Verify
- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 5.2 `./node_modules/.bin/vitest run test/supabase-migrations/byok-rpc-body-markers.test.ts` green.
- [ ] 5.3 `actionlint` the two workflows; `bash -c` syntax-check extracted `run:` snippets (NOT actionlint on the composite action.yml).
- [ ] 5.4 Probe snippet exercised via `bash -c` against all-markers + missing-marker fixtures.

## Phase 6 — Post-merge (automated)
- [ ] 6.1 (Option A fallback only) Migration 122 applied to dev + prd via `web-platform-release.yml#migrate`; verify via `list_migrations`. **Under Option B (primary): no migration — skip.**
- [ ] 6.2 `gh workflow run scheduled-dev-migration-drift.yml` → green, no false-positive body-marker `::error::`.
- [ ] 6.3 Live atomicity smoke (`TENANT_INTEGRATION_TEST=1`, dev) → green.
