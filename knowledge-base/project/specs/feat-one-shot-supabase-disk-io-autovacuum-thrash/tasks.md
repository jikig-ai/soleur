---
title: Tasks — fix autovacuum thrash on tiny hot-update tables
plan: knowledge-base/project/plans/2026-07-07-fix-supabase-autovacuum-thrash-disk-io-plan.md
lane: single-domain
date: 2026-07-07
---

# Tasks — fix autovacuum thrash (residual Supabase Disk IO drain)

## Phase 0 — Live read-only discovery
- [ ] 0.1 Query `pg_stat_all_tables` (public schema, ORDER BY autovacuum_count) on ref `ifsccnjhymdmidffkzhl` via Supabase MCP `execute_sql` — read-only; pin the baseline (autovacuum_count is cumulative).
- [ ] 0.2 Apply the decision rule: confirm the 3 named tables + include any `public` table with `autovacuum_count ≥ 20` AND `n_live_tup ≤ 100`. Exclude `auth.*` / `realtime.*` / `cron.*`.
- [ ] 0.3 Read current `reloptions` (`pg_class`) for the target tables so `.down.sql` restores true prior state.
- [ ] 0.4 Record the baseline row-set into the spec/PR for the Follow-Through diff.

## Phase 1 — Migration (core fix)
- [ ] 1.1 Create `apps/web-platform/supabase/migrations/123_tame_autovacuum_on_tiny_hot_tables.sql`: header comment (lineage #3358/#5736, learning 2026-05-06, related #5739, no-CONCURRENTLY note).
- [ ] 1.2 `ALTER TABLE public.<t> SET (autovacuum_vacuum_threshold=1000, autovacuum_vacuum_scale_factor=0, autovacuum_analyze_threshold=1000, autovacuum_analyze_scale_factor=0, fillfactor=70)` for each confirmed owned table.
- [ ] 1.3 Create `123_tame_autovacuum_on_tiny_hot_tables.down.sql`: `RESET` the same params per table.

## Phase 2 — Shape test
- [ ] 2.1 Create `apps/web-platform/test/supabase-migrations/123-tame-autovacuum.test.ts` (mirror `038-039-disk-io-fix.test.ts`): assert params + values per table; assert `.down.sql` RESET symmetry; assert no `ALTER TABLE auth.`/`realtime.`/`cron.`.
- [ ] 2.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/supabase-migrations/123-tame-autovacuum.test.ts` green.
- [ ] 2.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.

## Phase 3 — Follow-Through soak enrollment
- [ ] 3.1 Create `scripts/followthroughs/autovacuum-thrash-<issue>.sh` (read-only Supabase API query; exit 0 when each table's weekly autovacuum rate < 15).
- [ ] 3.2 Add tracker directive `<!-- soleur:followthrough script=… earliest=<deploy+7d> secrets=SUPABASE_ACCESS_TOKEN -->` + `follow-through` label.
- [ ] 3.3 Verify `SUPABASE_ACCESS_TOKEN` wired into `.github/workflows/scheduled-followthrough-sweeper.yml` (edit only if missing).

## Phase 4 — Ship
- [ ] 4.1 PR body: `Ref #5739` (NOT Closes), cite #3358/#5736 lineage; split AC into pre-merge / post-merge.
- [ ] 4.2 Post-merge: `web-platform-release.yml#migrate` + `verify-migrations` green; run discoverability reloptions read.
