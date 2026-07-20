# Tasks — Supabase Disk-IO write reduction

Plan: `knowledge-base/project/plans/2026-07-18-perf-supabase-disk-io-write-reduction-plan.md`
Lane: cross-domain · Brand-survival: single-user incident (CPO sign-off required)
**PR-split recommendation open (DC-1):** phases map to 3 shippable PRs (132 / 133+TS / 134) — operator decides.

## Phase 0 — Preconditions

- [ ] 0.1 Re-pull `disk_io_pressure_signal` + `/advisors/performance`; confirm 20 unused_index / 58 auth_rls_initplan lists unchanged.
- [ ] 0.2 Confirm highest migration still 131; reserve 132/133/134.
- [ ] 0.3 Confirm vitest `include:` globs; typecheck `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] 0.4 Verify FK `confdeltype` (pg_constraint) for the 6 FK-column drop candidates.
- [ ] 0.5 Snapshot LIVE `pg_get_expr(polqual/polwithcheck)` + polpermissive/polroles/polcmd for every RLS target (for AC5 before/after diff + down file).

## Phase 1 — Drop unused indexes (migration 132) [PR-A]

- [ ] 1.1 `132_drop_unused_indexes.sql` — `DROP INDEX IF EXISTS` ×14 mature indexes.
- [ ] 1.2 `132_drop_unused_indexes.down.sql` — recreate all 14 with exact defs (partial WHERE, DESC order). No CONCURRENTLY.
- [ ] 1.3 File labeled follow-up for the 6 deferred beta-CRM indexes (`disk-io`,`perf`,`deferred-scope-out`).
- [ ] 1.4 Round-trip test: apply 132 → 132.down restores `pg_indexes.indexdef` codepoint-for-codepoint (AC1).

## Phase 2 — Wrap auth_rls_initplan hotspots (migration 134) [PR-C]

- [ ] 2.1 Gate candidate list to advisor-confirmed `auth_rls_initplan` findings; EXCLUDE the `users` guard/profile policies (likely unflagged, highest mis-copy risk).
- [ ] 2.2 Source every predicate from LIVE `pg_policies` (NOT defining migration) — `conversations_owner_update/insert` + `kb_files_owner_update` authoritative def is mig 129 (is_workspace_member WITH CHECK MUST survive).
- [ ] 2.3 `134_rls_initplan_hotspots.sql` — `ALTER POLICY` wrapping only `auth.<fn>()` in `(select …)`; all else byte-identical.
- [ ] 2.4 `134_rls_initplan_hotspots.down.sql` — restore unwrapped from the 0.5 snapshot.
- [ ] 2.5 Before/after diff-invariant test (AC5): after-form minus `(select …)` wrapper == before-form; polpermissive/polroles/polcmd unchanged.
- [ ] 2.6 File follow-up for the ~35 deferred low-traffic policies.
- [ ] 2.7 Run `/soleur:gdpr-gate` on the RLS diff (expected: no material change).

## Phase 3a — Staleness thresholds SQL (migration 133) — CONTRACT, first [PR-B]

`133_heartbeat_threshold_backoff.sql` — 4 SQL objects, `CREATE OR REPLACE` verbatim from LIVE source, only the interval literal changed, SECURITY DEFINER/search_path/grants preserved:
- [ ] 3a.1 `acquire_conversation_slot(uuid,uuid,integer,uuid)` (mig 093) lazy sweep 120→240s.
- [ ] 3a.2 Reschedule `user_concurrency_slots_sweep` reproducing **mig 115** DO-block, cadence `'0 * * * *'` UNCHANGED, body 240s.
- [ ] 3a.3 `find_stuck_active_conversations` (mig 037, + mig-128 grant/comment) default `120`→`240`.
- [ ] 3a.4 `acquire_worktree_lease` (mig 116) takeover 120→240s.
- [ ] 3a.5 `.down.sql` restores all four to pre-133 LIVE state (115 at `'0 * * * *'`+120s, NOT 029).
- [ ] 3a.6 AC4 assertions: proconfig search_path pin + prosecdef=true survive; 4-arg signature; service_role EXECUTE retained; cadence `0 * * * *`.

## Phase 3b — TS heartbeat backoff — CONSUMER [PR-B]

- [ ] 3b.1 `ws-handler.ts` ~2969: extract slot heartbeat → `SLOT_HEARTBEAT_INTERVAL_MS = 60_000`.
- [ ] 3b.2 Introduce ONE shared `SLOT_STALENESS_THRESHOLD_SECONDS = 240`; import in ws-handler.ts (replaces STALE_HEARTBEAT_THRESHOLD_SECONDS) AND agent-runner.ts (replaces STUCK_ACTIVE_THRESHOLD_SECONDS).
- [ ] 3b.3 `ws-handler.ts:801` + `:2059`: replace bare `120_000` liveCutoff with `SLOT_STALENESS_THRESHOLD_SECONDS*1000`.
- [ ] 3b.4 `index.ts:159` comment + all `120`/`120 s` prose in ws-handler.ts/agent-runner.ts → 240 (AC6).
- [ ] 3b.5 `routine-run-progress.ts`: `HEARTBEAT_INTERVAL_MS`=60_000, `STUCK_THRESHOLD_MS`=180_000.
- [ ] 3b.6 `worktree-write-lease.ts`: `WORKTREE_LEASE_HEARTBEAT_MS`=50_000, `LEASE_LIVENESS_WINDOW_MS`=240_000.

## Phase 3e — Cap-hit immediate-reclaim mitigation [PR-B]

- [ ] 3e.1 `start_session` ledger-divergence recovery reaps user's slots with no live local socket, threshold-independent (AC14).

## Phase 3f — Tests [PR-B]

- [ ] 3f.1 Invariant test (AC7) importing LIVE symbols: threshold ≥ 3×interval all systems; STUCK<ORPHAN (routine-run-progress).
- [ ] 3f.2 Grep-based drift-guard (AC8): 0 residual `120_000`/`interval '120 seconds'` across ws-handler/agent-runner/133; 3× `interval '240 seconds'` + 037 default 240.
- [ ] 3f.3 AC14 test: stale-<240s slot with no socket → new acquire succeeds.
- [ ] 3f.4 Update existing tests pinning old constants (30_000/90_000/25_000/120s).

## Phase 4 — Verify, observability & ship

- [ ] 4.1 `tsc --noEmit` + full vitest suite green.
- [ ] 4.2 Add reap-site Sentry signal (plausibly-live reap w/ heartbeat_age_seconds) — the false-reap detector.
- [ ] 4.3 Soak follow-through probe `scripts/followthroughs/concurrency-slot-wal-backoff-<issue>.sh` (model on `autovacuum-thrash-6168.sh`; delta-rate over `pg_stat_user_tables.n_tup_upd`); PR-body directive + `follow-through` label; wire `secrets=SUPABASE_ACCESS_TOKEN` into scheduled-followthrough-sweeper.yml (AC13).
- [ ] 4.4 CPO sign-off recorded; user-impact-reviewer at review.
- [ ] 4.5 PR body: baseline signal + rollback-ordering note (redeploy old code BEFORE reverting mig 133) + post-deploy delta-rate soak plan; reference migrations 114/123 as date-anchored prose; `Ref #N` not `Closes` for post-deploy-verified issues.
- [ ] 4.6 Post-merge: confirm 132/133/134 in `_schema_migrations`; 7-day delta-rate soak (AC12).
