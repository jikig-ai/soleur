# Tasks — rls-fuzz teardown deadlock fix (#9779)

Derived from `knowledge-base/project/plans/2026-10-08-fix-rls-fuzz-teardown-deadlock-plan.md`.
lane: cross-domain (fail-closed default — no spec.md) · brand_survival_threshold: none · closes #9779.

> **Contract (load-bearing — read before touching any file):**
> `withTransientRetry` wraps `sql`-HANDLE calls only. Never wrap a
> transaction-scoped `t` handle — an aborted txn re-raises `25P02`, masking the
> real `40P01` from the outer retry. `Sql`-only helpers self-wrap; `Sql|Txn`
> helpers are wrapped at each bare-`sql` call site.

## Phase 0 — Preconditions

- [x] 0.1 Read `apps/web-platform/test/rls-fuzz/harness-fixture.ts`,
      `catalog.ts`, and all six `*.integration.test.ts` files in that directory.
- [x] 0.2 Re-run both plan-time census commands (plan AC6) and confirm the
      pre-fix counts still hold (~33 bare `await sql` sites, ~13 bare-`sql`
      helper call sites). If the counts moved, re-derive the site list — the
      allowlist semantics, not the number, is the invariant.
- [x] 0.3 Confirm the suite runs unchanged: `./node_modules/.bin/vitest run test/rls-fuzz`
      from `apps/web-platform/` is a no-op pass locally when
      `RLS_FUZZ_LOCAL` is unset (all integration files `describe.skipIf`).
      Real DB verification is the PR's own `RLS authz fuzz` check (AC8) — do
      NOT start a local Supabase stack just for this.

## Phase 1 — Failing test first (`cq-write-failing-tests-before`)

- [x] 1.1 Create `apps/web-platform/test/rls-fuzz/harness-fixture.test.ts`
      covering `withTransientRetry`/`rolledBackRaw` against a stubbed
      `{ begin: vi.fn() }` sql object with an injectable `sleep`:
      - [x] 1.1.1 transient `{code:"40P01"}` once then success → resolves fn's
            value; `begin` called twice (AC1)
      - [x] 1.1.2 `{code:"42501"}` and a plain `Error` → propagate on attempt 1,
            no retry (AC2)
      - [x] 1.1.3 permanent `40P01` → propagates after exactly 3 attempts (AC3)
      - [x] 1.1.4 `55P03` behaves identically to `40P01` (AC1 set membership)
      - [x] 1.1.5 normal `fn` completion returns `out` and the `ROLLBACK`
            sentinel never escapes or triggers a retry (AC4)
      - [x] 1.1.6 injected `sleep` spy observes delays in [80, 120) ms (AC5)
- [x] 1.2 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/rls-fuzz/harness-fixture.test.ts`
      — expect RED (module has no `withTransientRetry` export yet).

## Phase 2 — `harness-fixture.ts`

- [x] 2.1 Import `sqlStateFromError` from `../../lib/postgres-errors`; add
      `TRANSIENT_SQLSTATES = new Set(["40P01","55P03"])`,
      `TRANSIENT_MAX_ATTEMPTS = 3`, and exported `withTransientRetry(fn,
      opts?: { sleep? })` — docstring carries the `t`-handle prohibition and
      the `server/concurrency.ts` parity note.
- [x] 2.2 Wrap `rolledBackRaw`'s `sql.begin` in `withTransientRetry` (sentinel
      consumed inside the wrapped closure; wrapper only sees real errors).
- [x] 2.3 Extract `seedTwoTenantTx(t)`/`seedRpcCtxTx(t)` internals;
      `seedTwoTenant(sql)`/`seedRpcCtx(sql)` become
      `withTransientRetry(() => sql.begin((t) => seed…Tx(t)))` — committed txn,
      `assertTwoTenant` rides inside. Public signatures unchanged.
- [x] 2.4 Re-run 1.2's command — GREEN (AC1–AC5).

## Phase 3 — Census sweep (all bare-`sql` surfaces)

- [x] 3.1 `catalog.ts`: wrap each of the 5 bare `await sql` queries inside the
      8 exported `Sql`-typed functions.
- [x] 3.2 `rls-authz-fuzz.integration.test.ts`: wrap `t.seed(sql, ctx)` (~45),
      `countRows(sql,…)` (~88, ~152), `denied_jti` insert (~184), AC10
      `information_schema` query (~228).
- [x] 3.3 `rls-excluded-deepened.integration.test.ts`: wrap
      `seedEmailTriageItem(sql, ctx)` (~33), `countById(sql,…)` (~68, ~73);
      move the ~6-statement `beforeAll` seed cluster into one committed
      `sql.begin` under `withTransientRetry`.
- [x] 3.4 `rls-row-hijack.integration.test.ts`: wrap `h.seed(sql, ctx)` (~102).
- [x] 3.5 `rls-storage.integration.test.ts`: `beforeAll` seed cluster into
      committed `sql.begin` + retry; wrap `countObject(sql)` (~46, ~83).
- [x] 3.6 `rls-user-isolation.integration.test.ts`: wrap `t.seed(sql, ctx)`
      (~38), `countRows(sql,…)` (~71, ~120).

## Phase 4 — Verification

- [x] 4.1 Census A and B both return empty (AC6 commands, verbatim from plan).
- [x] 4.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/rls-fuzz/harness-fixture.test.ts` green (AC7).
- [x] 4.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean
      (worktree rule: never `npm run -w`; never `npx vitest`).
- [ ] 4.4 `git diff --name-only origin/main...HEAD` touches only
      `apps/web-platform/test/rls-fuzz/**` + knowledge-base artifacts (AC9).
- [ ] 4.5 PR's own `RLS authz fuzz` check is green AND the run log shows the
      suite executed — not skipped (AC8).
