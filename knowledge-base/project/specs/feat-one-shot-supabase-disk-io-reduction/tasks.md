# Tasks — Supabase Disk-IO write reduction

Plan: `knowledge-base/project/plans/2026-07-18-perf-supabase-disk-io-write-reduction-plan.md`
Lane: cross-domain · Brand-survival: single-user incident (CPO sign-off required)

## Phase 0 — Preconditions

- [ ] 0.1 Re-pull `disk_io_pressure_signal` + `/advisors/performance` at work start; confirm the 20
      unused_index / 58 auth_rls_initplan lists have not drifted from the plan's snapshot.
- [ ] 0.2 Confirm highest migration is still 131; reserve 132/133/134.
- [ ] 0.3 Confirm vitest `include:` globs (`apps/web-platform/vitest.config.ts`) for test placement;
      typecheck via `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 0.4 Verify FK `confdeltype` (pg_constraint) for the six FK-column drop candidates.

## Phase 1 — Drop unused indexes (migration 132)

- [ ] 1.1 Write `132_drop_unused_indexes.sql` — `DROP INDEX IF EXISTS` for the 14 mature indexes.
- [ ] 1.2 Write `132_drop_unused_indexes.down.sql` — recreate all 14 with exact defs (partial WHERE,
      column order preserved). No CONCURRENTLY (txn-wrapped runner).
- [ ] 1.3 File the labeled follow-up issue for the 6 deferred beta-CRM indexes (`disk-io`,`perf`,`deferred-scope-out`).
- [ ] 1.4 Round-trip test: apply 132 → apply 132.down restores the 14 in `pg_indexes`.

## Phase 2 — Wrap auth_rls_initplan hotspots (migration 134)

- [ ] 2.1 For each targeted policy (user_concurrency_slots, routine_runs, routine_run_progress,
      conversations, messages, users, kb_files, push_subscriptions ≈ 23 policies), pull current
      `USING`/`WITH CHECK` + `polpermissive` (from defining migration + live `pg_policies`).
- [ ] 2.2 Write `134_rls_initplan_hotspots.sql` — `ALTER POLICY` wrapping only `auth.<fn>()` in `(select …)`,
      predicate otherwise byte-identical. Surgical care on the 3 `users` guard policies.
- [ ] 2.3 Write `134_rls_initplan_hotspots.down.sql` — restore unwrapped form.
- [ ] 2.4 `pg_policy` shape assertion test: each targeted policy's `polqual`/`polwithcheck` contains
      `(SELECT auth.`, original predicate intact, `polpermissive` unchanged.
- [ ] 2.5 File follow-up issue for the ~35 deferred low-traffic policies.
- [ ] 2.6 Run `/soleur:gdpr-gate` on the RLS diff (expected: no material change; semantics preserved).

## Phase 3a — Concurrency-slot threshold (migration 133) — CONTRACT, first

- [ ] 3a.1 `133_concurrency_slot_heartbeat_backoff.sql` — `CREATE OR REPLACE acquire_slot` (from mig 093
      verbatim) with lazy-sweep `120 seconds`→`240 seconds`; preserve SECURITY DEFINER `search_path` pin.
- [ ] 3a.2 Re-schedule pg_cron `user_concurrency_slots_sweep` (mig 029 body) with 240 s predicate; cadence unchanged.
- [ ] 3a.3 `.down.sql` restores both to 120 s.
- [ ] 3a.4 Add cross-referencing comments naming all five coupling sites + the shared 240 s value.

## Phase 3b — TS heartbeat backoff — CONSUMER

- [ ] 3b.1 `ws-handler.ts` ~2969: extract slot heartbeat to `SLOT_HEARTBEAT_INTERVAL_MS = 60_000`; set
      `STALE_HEARTBEAT_THRESHOLD_SECONDS` = 240 (line 545).
- [ ] 3b.2 `agent-runner.ts:789` `STUCK_ACTIVE_THRESHOLD_SECONDS` = 240.
- [ ] 3b.3 `index.ts:159` comment → "240 s slot-heartbeat staleness threshold".
- [ ] 3b.4 `routine-run-progress.ts` `HEARTBEAT_INTERVAL_MS`=60_000, `STUCK_THRESHOLD_MS`=180_000.
- [ ] 3b.5 `worktree-write-lease.ts` `WORKTREE_LEASE_HEARTBEAT_MS`=50_000, `LEASE_LIVENESS_WINDOW_MS`=240_000.

## Phase 3c — Tests

- [ ] 3c.1 Invariant test: threshold ≥ 3× interval for all three systems; STUCK < ORPHAN (routine-run-progress).
- [ ] 3c.2 5-site consistency/drift-guard: 240 at ws-handler + agent-runner + mig 133 acquire_slot + pg_cron;
      no residual 120 staleness literal.
- [ ] 3c.3 Update existing tests pinning old constants (30_000/90_000/25_000/120s).

## Phase 4 — Verify & ship

- [ ] 4.1 `tsc --noEmit` + full vitest suite green.
- [ ] 4.2 CPO sign-off recorded; user-impact-reviewer at review.
- [ ] 4.3 PR body: baseline signal + post-deploy soak plan (re-call `disk_io_pressure_signal`), reference
      migrations 114/123 as date-anchored prose. Use `Ref #N` (not `Closes`) for any post-deploy-verified issue.
- [ ] 4.4 Post-merge: confirm 132/133/134 in `_schema_migrations`; 24 h soak re-pull (AC12).
