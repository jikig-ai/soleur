-- 123_tame_autovacuum_on_tiny_hot_tables.down.sql
--
-- Manual rollback for 123. RESET the per-table storage parameters back to the
-- cluster defaults (pg_class.reloptions returns to NULL — verified as the true
-- prior state during Phase-0 discovery on 2026-07-07: all three tables had
-- reloptions = NULL before this migration).
--
-- NOTE: .down.sql files are explicitly skipped by scripts/run-migrations.sh
-- (case ... *.down.sql) continue) — this is manual-rollback-only and will NOT
-- auto-apply. See docs/migration-rollback.md.

ALTER TABLE public.user_concurrency_slots RESET (
  autovacuum_vacuum_threshold,
  autovacuum_vacuum_scale_factor,
  autovacuum_analyze_threshold,
  autovacuum_analyze_scale_factor,
  fillfactor
);

ALTER TABLE public.mint_rate_window RESET (
  autovacuum_vacuum_threshold,
  autovacuum_vacuum_scale_factor,
  autovacuum_analyze_threshold,
  autovacuum_analyze_scale_factor,
  fillfactor
);

ALTER TABLE public.runtime_mint_intent RESET (
  autovacuum_vacuum_threshold,
  autovacuum_vacuum_scale_factor,
  autovacuum_analyze_threshold,
  autovacuum_analyze_scale_factor,
  fillfactor
);
