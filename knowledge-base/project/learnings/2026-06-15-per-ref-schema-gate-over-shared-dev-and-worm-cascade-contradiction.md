# Learning: WORM-vs-cascade FK contradictions + per-ref schema gates over shared dev

**Date:** 2026-06-15
**Issue:** #5372 (Tenant integration dev-Supabase failing — GDPR Art-17 account-delete cascade)
**Tags:** category: database-issues, integration-issues; module: supabase-migrations, ci-gates, account-delete

## Problem

`Tenant integration (dev-Supabase)` was red on `main` for ~4h. Every test that tears down a tenant user failed: GoTrue `auth.admin.deleteUser` returned `status=500 code=unexpected_failure`, ending (after 5 `withGoTrueRetry` attempts) with `Database error deleting user` / `Account deletion failed at auth-delete`.

Root cause (live-reproduced against dev, NOT the issue's stated hypothesis): an **orphan unmerged migration** `104_routine_runs.sql` (from open WIP PR #5342) had been applied to shared dev via `ALLOW_UNMERGED_DEV_APPLY=1`. Its `routine_runs` table carried **STATEMENT-level** WORM triggers (`FOR EACH STATEMENT`, unconditional `RAISE EXCEPTION P0001`) alongside `ON DELETE SET NULL` FKs to `public.users`. Deleting a user fires the FK cascade `UPDATE routine_runs SET actor_id=NULL WHERE actor_id=$1` — and a **statement-level** trigger fires on that UPDATE **even against 0 matching rows**, so deletion broke for *every* user, even a brand-new one with no `routine_runs` rows.

## Key Insights

1. **A WORM (append-only) trigger contradicts an `ON DELETE SET NULL/CASCADE` FK to a parent that gets deleted.** The cascade fires a child UPDATE (SET NULL) or DELETE (CASCADE) that the WORM trigger rejects. Critically, the cascade runs **inside GoTrue's own transaction**, where `account-delete.ts` cannot set the `app.worm_bypass` GUC — so a GUC carve-out on the trigger does **not** fix it. The convention for WORM tables referencing `users` is `ON DELETE RESTRICT` + **pre-anonymise** the FK column in `account-delete.ts` before auth-delete (the `audit_byok_use` pattern), never SET NULL/CASCADE.

2. **Statement-level WORM triggers are a sharper foot-gun than row-level.** A `FOR EACH STATEMENT` BEFORE UPDATE/DELETE trigger fires on the cascade's 0-row statement; a `FOR EACH ROW` trigger does not. So an *empty* table can still break deletion. "Empty table = harmless" is false.

3. **A CI gate that scans SHARED dev live schema must be PER-REF-scoped, or it false-reds main exactly like a blanket orphan-block.** Shared dev accumulates objects from every open migration-PR (`ALLOW_UNMERGED_DEV_APPLY`). A gate that errors on a contradiction it finds in the live schema will fire on *another PR's* leave-behind during a `push:main` run. Fix: error (`::error::`+exit 1) only when the offending relation is **owned by a migration in the current checkout** (its name appears in `supabase/migrations/*.sql` on this ref); downgrade a leave-behind from another ref to `::warning::`. Net: the owning PR's CI fails (enforcement teeth), main + unrelated PRs stay green, a genuinely-merged bad migration still errors. See ADR-061.

4. **`CASE col WHEN ... THEN '<text>' ELSE col END` truncates the text literals when `col` is type `"char"`.** `confdeltype` is `"char"` (single byte). An `ELSE con.confdeltype` branch unifies the whole CASE to `"char"`, clipping `'SET NULL'`→`'S'`. Drop the ELSE (when a WHERE clause makes it dead) or cast `con.confdeltype::text`.

5. **The behavioural regression test is the real backstop; the schema gate is a fail-fast early-warning.** The gate's "raising trigger" detection is a `prosrc` heuristic (`RAISE EXCEPTION`/`ASSERT`) — sound for the codebase's uniform idiom but not a proof. The end-to-end minimal-user `deleteAccount` test catches any raise idiom the heuristic misses.

## Solution

- One-time dev revert (`scripts/revert-dev-routine-runs-drift.sql`) dropping the orphan objects + its single `_schema_migrations` row (leaving #5363's harmless `105_turn_summary` orphan alone to avoid schema-vs-ledger drift).
- New per-ref gate `scripts/preflight-worm-cascade-contradiction.sh` (wired into `tenant-integration.yml` after apply, before tests).
- Migration `106_denied_jti_founder_cascade.sql`: an independently-motivated Art-17 fold-in (denied_jti.founder_id RESTRICT→CASCADE; the deny key is `jti`, founder_id is metadata).
- The durable source fix lives in PR #5342 (blocking review comment); the gate enforces it (its CI fails until fixed).

## Session Errors

1. **Plan premise wrong (bisect merged migrations / "missing ON DELETE" / fix-migration-on-main).** Recovery: the plan subagent live-reproduced against dev and corrected the premise before implementation. **Prevention:** plan hypotheses about a symptom's mechanism are starting points — reproduce against the live system before coding (already a /work Sharp Edge).
2. **Plan's "blocking orphan-drift gate on push:main" was self-defeating** (would persistently false-red main). Recovery: escalated to operator, redesigned to a targeted gate. **Prevention:** captured as ADR-061 + insight #3; any future shared-dev gate must be per-ref-scoped.
3. **First targeted-gate design still false-red-main (no per-ref scoping).** Recovery: caught by multi-agent review (architecture-strategist); fixed with the ownership gate. **Prevention:** when a gate scans shared mutable state, the review-spawn prompt should ask "can another ref's state trip this on main?" — the multi-agent review caught it, which is the system working.
4. **`pg` not installed locally + ESM import path (`pg/lib` not `pg/index.js`).** Recovery: `bun add pg` in `/tmp`, `createRequire`. One-off; the `/tmp`+bun fallback is already documented in the work skill's Supabase fallback chain.
5. **SQL `CASE`/`confdeltype` truncation.** Recovery: dropped the ELSE. **Prevention:** insight #4.

## Prevention

- New gate + regression tests now guard the WORM-vs-cascade class at apply time.
- ADR-061 documents the per-ref-scoping requirement for the next gate author.
