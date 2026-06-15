---
title: Tasks — Fix auth.users delete-cascade CI failure (#5372)
plan: knowledge-base/project/plans/2026-06-15-fix-authusers-delete-cascade-dev-drift-plan.md
issue: 5372
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks — #5372 auth.users delete-cascade (dev-Supabase orphan-migration drift)

> Root cause (reproduced): orphan unmerged `104_routine_runs.sql` (PR #5342) applied to dev has STATEMENT-level
> WORM `no_update`/`no_delete` triggers contradicting its `ON DELETE SET NULL` FK → `P0001` aborts every
> `auth.users` delete (fires even on the 0-row cascade UPDATE, in GoTrue's GUC-less transaction).
>
> **DEVIATION from plan (operator-approved "Durable + targeted gate"):** Phase 2's "blocking orphan-drift gate
> on push:main" was found UNSAFE — shared dev accumulates orphans from every open migration-PR (e.g. #5363's
> 105_turn_summary), so blocking-on-main would persistently false-red main. Replaced with a TARGETED gate
> (`preflight-worm-cascade-contradiction.sh`) that flags the actual deletion-breaking class: STATEMENT-level
> raising BEFORE U/D triggers on tables with ON DELETE SET NULL/CASCADE FK to users (::error::), row-level
> (::warning::). Drift probe left warning-only. The source fix in #5342 is a precise blocking review comment
> (not a push onto its active branch); the new gate is the enforcement teeth (its CI fails until #5342 fixes).

## Phase 0 — Preconditions
- [x] 0.1 Confirm repro: `cd apps/web-platform && doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/server/account-delete.cascade.integration.test.ts` fails 3/3 (anchor: "Account deletion failed at auth-delete").
- [x] 0.2 Re-confirm dev `_schema_migrations` carries `104_routine_runs.sql` (+ `105_turn_summary_message_kind.sql`) absent from `origin/main`.
- [ ] 0.3 Confirm CPO sign-off on the single-user-incident threshold before implementation.

## Phase 1 — Revert dev orphan drift (the unblock)
- [x] 1.1 Author idempotent revert script under `apps/web-platform/scripts/` (model: `run-migrations.sh` `run_sql`/Doppler-`DATABASE_URL`; supabase-js service client since `psql` absent). Novel — no `_schema_migrations`-delete precedent exists.
- [x] 1.2 Script drops (all `IF EXISTS`): triggers `routine_runs_no_update`/`routine_runs_no_delete`, fn `routine_runs_no_mutate()`, RPC `write_routine_run` (if present), table `public.routine_runs`; deletes the two orphan rows from `_schema_migrations`.
- [x] 1.3 Safety guard: refuse to drop any object that also exists on `origin/main`.
- [x] 1.4 Run against dev; confirm discoverability_test passes (AC1, AC2). Capture output for PR body.

## Phase 2 — Make drift gate BLOCKING on main (prevent re-normalization)
- [ ] 2.1 Escalate `.github/actions/dev-migration-drift-probe/action.yml` orphan-file branch to `::error::` + non-zero exit ONLY on `push:main` (`github.event_name=='push' && github.ref=='refs/heads/main'`); keep `::warning::` on `pull_request`. Thread trigger context via input/wrapping step (composite actions don't see `github.event_name` directly).
- [ ] 2.2 Update action header comment citing #5372 as recurrence justifying severity bump over 2026-05-21 warning-by-design.
- [x] 2.3 Verify drift step runs before "Run tenant-isolation tests" in `tenant-integration.yml` (already L141 vs L229).
- [x] 2.4 Verify `scheduled-dev-migration-drift.yml` cron consumer still functions with new severity.

## Phase 3 — Regression gate (lock the invariant)
- [x] 3.1 `git grep` to confirm `account-delete.cascade.integration.test.ts` already asserts minimal-user `deleteAccount(soloUser)` success; only add a minimal-user-only case if missing (AC4).
- [x] 3.2 Confirm test path matches `vitest.config.ts` include glob `test/**/*.test.ts` (it does).
- [x] 3.3 After Phase 1 revert, the suite passes 3/3 on dev.

## Phase 4 — denied_jti.founder_id Art-17 fold-in (main-side completeness)
- [x] 4.1 Decide: anonymise-RPC step in `account-delete.ts` (+ forward migration + SECURITY DEFINER RPC, pin `search_path=public,pg_temp`) vs FK downgrade to `ON DELETE SET NULL` (forward migration). Prefer FK downgrade if `founder_id` is not load-bearing for deny-list correctness (verify via 036/068 deny-list migrations — the jti index is the deny key).
- [x] 4.2 Add forward migration at next free integer prefix on main, with `to_regclass('public.users')` precondition (FK-precondition lint).
- [ ] 4.3 If RPC path: wire the cascade step in `account-delete.ts` in correct FK order, before auth-delete.
- [x] 4.4 Deterministic test: seed a `denied_jti` row, assert the cascade succeeds.

## Phase 5 — Fix source bug in PR #5342 (cross-PR follow-through)
- [x] 5.1 File blocking note/required-change on PR #5342: resolve prefix-104 collision (renumber) AND WORM-vs-SET-NULL contradiction (add `app.worm_bypass` GUC carve-out to `routine_runs_no_mutate` per post-087 pattern + `anonymise_routine_runs` step in `account-delete.ts`, OR change FK to `ON DELETE CASCADE` + WORM no-delete carve-out).
- [x] 5.2 Record as `Ref #5342` (not code in this PR).

## Phase 6 — Verify + ship
- [x] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes (AC7).
- [x] 6.2 GDPR gate (Phase 2.7) run on the diff (regulated-data surface: account-delete cascade + migration).
- [ ] 6.3 PR body: `Ref #5372` if dev-revert is post-merge; otherwise `Closes #5372`. Split AC into Pre-merge / Post-merge(operator) per the plan.
- [ ] 6.4 If dev-revert ran post-merge: `gh issue close 5372` after discoverability_test passes.
- [x] 6.5 Add a re-eval note to open code-review issue #3370 linking #5372 (drift-family overlap, acknowledged not closed).
