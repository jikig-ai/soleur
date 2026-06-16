---
feature: routines-runs-detail
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-16-feat-routines-runs-detail-plan.md
issue: 5412
---

# Tasks — Routines runs detail + filters + per-routine drawer (PR-4)

## Phase 1 — RED
- [ ] 1.1 `test/server/routines/list-routines.test.ts`: extend mock `chain` with `.eq()/.gte()` (return `chain`); assert `listRecentRuns({routineId})`→`.eq("routine_id")`, `{status}`/`{triggerSource}`→`.eq`, `{since}`→`.gte("started_at")`; tuple cursor still works with a filter; **RUN_COLS includes run_id+actor_class, EXCLUDES actor_id/delegating_principal**.
- [ ] 1.2 `test/server/routines/runs-route-filters.test.ts` (new): runs route validates filter params — rejects/ignores bad status/triggerSource, non-EXPECTED_CRON_FUNCTIONS routineId, unparseable since; passes valid through; "running" not accepted as status.
- [ ] 1.3 `test/components/routines/routines-surface.test.tsx`: tab label "Draft a routine with Concierge" (no ✨/new); filter bar renders + change → scoped refetch; run row click → detail panel showing actor_class text (no UUID); routine click → drawer (metadata + scoped log); drawer row → detail panel.

## Phase 2 — GREEN
- [ ] 2.1 `server/routines/list-routines.ts`: recursive OrderedQuery `.eq()/.gte()`; optional routineId/status/triggerSource/since opts applied before cursor `.or()/.limit()`; widen RUN_COLS (+run_id,+actor_class); update RunSummary/RecentRun.
- [ ] 2.2 `app/api/dashboard/routines/runs/route.ts`: parse + validate 4 filter params (status∈{completed,failed} NOT running; triggerSource∈{scheduled,manual,agent}; routineId∈EXPECTED_CRON_FUNCTIONS; since ISO-or-ignore); pass to listRecentRuns.
- [ ] 2.3 `server/routines-tools.ts`: update routine_runs_list tool description (run_id+actor_class in payload); no actor_id.
- [ ] 2.4 `components/routines/routines-surface.tsx`: tab rename; filter bar (routine/status All-Completed-Failed/trigger/range); per-run detail panel REPLACING the inline failed-row expansion (one path, reused by tab+drawer); actor_class→label map w/ fallback (no "(you)"); per-routine slide-over drawer (metadata + manualTrigger badge + scoped routineId log + keyset Load more); add run_id/actor_class to client interfaces.

## Phase 3 — Verify
- [ ] 3.1 tsc clean.
- [ ] 3.2 routines + runs-route + component tests green; full webplat suite green.
- [ ] 3.3 soleur:qa (ship): filters, detail panel (no actor UUID), scoped drawer.

## Exit
- [ ] Review → ship. Closes #5412. No prd migration.
