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
- [x] 0.1 Confirmed mig `084_byok_delegation_withdrawals.sql` is the highest-numbered `CREATE OR REPLACE FUNCTION public.check_and_record_byok_delegation_use` (through 121). Cap RPC highest = 121.
- [x] 0.2 Confirmed markers executable-only (comment-strip then grep, count==1 each): `v_tripped := FOUND` + `FOR UPDATE` in mig 121; `FOR UPDATE` + `hourly_cap_exceeded` + `daily_cap_exceeded` in mig 084.
- [x] 0.3 `pg_get_functiondef` overload handling: probe concatenates all rows and asserts markers across all bodies (>1 overload safe); single-overload confirmed at live-probe run (Phase 6.2).

## Phase 1 — Probe extension (deliverable 1)
- [x] 1.1 `action.yml`: added inputs `sentry-dsn` (default `''`), `fail-on-rpc-body-drift` (default `'false'`); added output `rpc-body-drift-detected`. Marker map read from shared `byok-rpc-markers.json` via `jq`; static-allowlist / no-SQLi comment added.
- [x] 1.2 New step `id: rpc-body` after the ledger probe; psql `pg_get_functiondef` query via SQL-to-tempfile + `sh -c` DATABASE_URL_POOLER pattern; 0-rows (`__ABSENT__`) / concatenated-overload handling.
- [x] 1.3 Comment-strip body (`sed 's/--.*//'`) before `grep -qF` marker match; accumulate misses; set `rpc-body-drift-detected=true`. Severity tracks `fail-on-rpc-body-drift`.
- [x] 1.4 Bash Sentry `emit_sentry()` per `web-platform-release.yml:893-933` (DSN parse, `store/` POST, tags `feature`/`op`/`fn`, extra `missing_marker`, static `message`, 3-retry, DSN-unset/curl-fail → `::warning::`) — invoked ONLY when `fail-on-rpc-body-drift=='true'` AND DSN set.
- [x] 1.5 `exit 1` when `fail-on-rpc-body-drift=='true'` AND `drift=='true'`.
- [x] 1.6 `scheduled-dev-migration-drift.yml`: forwards `sentry-dsn` + `fail-on-rpc-body-drift: 'true'`.
- [x] 1.7 `tenant-integration.yml`: **no edit needed** — it forwards only `doppler-token`, so `sentry-dsn` defaults `''` + fail flag defaults `false` → `::warning::`-only, no Sentry (verified).

## Phase 2 — Shared marker map + structural source-side test (deliverable 1)
- [x] 2.1 Created `apps/web-platform/test/supabase-migrations/byok-rpc-markers.json` (single source of truth).
- [x] 2.2 Created `byok-rpc-body-markers.test.ts` reading that JSON; globs migrations (exclude `.down.sql`), picks highest-numbered `CREATE OR REPLACE FUNCTION public.<fn>` (anchored regex), extracts ONE function's def (dollar-quote isolation — sibling marker cannot leak), comment-strips, asserts markers; `throw` fail-loud + isolation negative fixtures. Green (10 tests), mutation-proven non-vacuous.

## Phase 3 — Introspection mechanism (deliverable 2, Option B primary)
- [x] 3.1 Added `postgres@^3.4.9` (porsager, zero-dep) to `apps/web-platform` devDependencies; regenerated BOTH `bun.lock` (`bun add --dev`) and `package-lock.json` (npm@11 `--package-lock-only`); `bun install --frozen-lockfile` parity confirmed.
- [~] 3.2 Option A fallback NOT used (Option B primary chosen — no migration).

## Phase 4 — Self-diagnosing atomicity failure (deliverable 2)
- [x] 4.1 `byok-kill-switch.atomicity.tenant-isolation.test.ts` computes `willFail` (trippedCount !== 1 || any per-pair mismatch).
- [x] 4.2 On `willFail`, fetches live body via porsager `sql\`SELECT pg_get_functiondef('...'::regprocedure)\`` over `DATABASE_URL_POOLER` (guarded `fetchLiveCapRpcBody`, never throws; fallback strings on unset/error).
- [x] 4.3 Live body embedded in `expect` **message** args only — no `.toBe`/`.toEqual` target changes (verified by diff; Invariant C strict).
- [x] 4.4 Filed follow-up #5938 (labels `observability`, `type/chore`) for a delegation-RPC semantic/atomicity test.

## Phase 5 — Verify
- [x] 5.1 `tsc --noEmit` clean.
- [x] 5.2 Structural test green.
- [x] 5.3 `actionlint` on `scheduled-dev-migration-drift.yml` OK; `bash -n` on extracted `action.yml` `run:` snippet clean (composite action.yml not actionlint'd).
- [x] 5.4 Probe snippet exercised via `bash` harness against all-markers + missing-marker fixtures (warning/error/exit-1/DSN-unset all correct). Full webplat unit suite: 9936 passed, 0 failed.

## Phase 6 — Post-merge (automated)
- [~] 6.1 Option A fallback only — skipped (Option B primary: no migration).
- [ ] 6.2 `gh workflow run scheduled-dev-migration-drift.yml` → green, no false-positive body-marker `::error::` (post-merge; the workflow lives on main).
- [ ] 6.3 Live atomicity smoke (`TENANT_INTEGRATION_TEST=1`, dev) → green (post-merge).
