-- 123_tame_autovacuum_on_tiny_hot_tables.sql
--
-- Stop autovacuum THRASH on three tiny public hot-update tables — the residual
-- Supabase Disk IO Budget drain after the WAL problem was solved.
--
-- Lineage (third remediation in the prod Disk IO Budget line):
--   #3358 (038/039) slowed the pg_cron sweep + dropped public.messages from
--     Realtime.
--   #5736 (114) added the WAL-concentration monitor; the webhook-dedup fix
--     crushed statement-attributed WAL from ~12 GB/day to ~17 MB/day.
--   THIS migration: the remaining drain is not WAL volume but the *vacuums the
--     writes trigger*.
--
-- Diagnosis (pg_stat_all_tables + pg_stat_statements, 7-day window,
-- stats_reset 2026-06-30 12:40 UTC, prod ref ifsccnjhymdmidffkzhl):
--   table                    live rows  updates/7d  autovacuums/7d
--   user_concurrency_slots        0       6,836        142
--   mint_rate_window              7       2,616         50
--   runtime_mint_intent           7       2,532         49
-- Postgres' default autovacuum trigger (autovacuum_vacuum_threshold=50 +
-- autovacuum_vacuum_scale_factor=0.2) fires after only ~50 dead tuples on a
-- tiny table, so these 0–16-row tables were fully vacuumed 49–142×/week. Each
-- vacuum reads the table + ALL its indexes, writes WAL, and fsyncs — a fixed
-- per-vacuum IOPS cost that, ×3 tables, is what now drains the Micro budget.
--
-- The fix: raise the per-table dead-tuple threshold ~20× (fires every ~1,000
-- dead tuples instead of ~50 → projected ~2–7 vacuums/week/table) and pin
-- fillfactor=70 so the 100%-HOT mint-table updates stay in-page and index
-- bloat stays bounded as more dead tuples accumulate between vacuums.
-- scale_factor=0 removes the %-of-rows term (meaningless at 0–16 rows) so the
-- trigger is a deterministic absolute dead-tuple count.
--
-- Safety:
--   * ALTER TABLE ... SET (autovacuum_* , fillfactor) takes a SHARE UPDATE
--     EXCLUSIVE lock, performs NO table rewrite, and does NOT block concurrent
--     SELECT/INSERT/UPDATE/DELETE — zero-downtime by construction. No
--     CONCURRENTLY needed (this is not index DDL); safe inside Supabase's
--     per-migration transaction.
--   * fillfactor applies to FUTURE page writes only; these hot tables rewrite
--     their pages within minutes of deploy. Do NOT add VACUUM FULL / CLUSTER —
--     non-transactional, fails inside the migration txn, and unnecessary at
--     this table size.
--   * Raising the dead-tuple threshold does NOT defer anti-wraparound vacuum
--     (a separate transaction-age trigger, not gated by
--     autovacuum_vacuum_threshold) — the tables stay wraparound-safe.
--
-- Scope boundary: ONLY the three public tables we own are altered. auth.* and
-- realtime.* are Supabase-managed (GoTrue / Realtime) and MUST NOT be altered
-- here (the migration role `postgres` would fail with 42501 must be owner) —
-- their write-churn reduction is tracked separately by OPEN issue #5739.
--
-- Closest sibling in intent: 038_slow_user_concurrency_slots_sweep.sql (same
-- disk-IO-reduction line, same first table).
--
-- See: knowledge-base/project/plans/2026-07-07-fix-supabase-autovacuum-thrash-disk-io-plan.md
-- See: knowledge-base/project/learnings/2026-05-06-supabase-disk-io-structural-overhead-dominates-at-low-scale.md
-- Related (out of scope): #5739

ALTER TABLE public.user_concurrency_slots SET (
  autovacuum_vacuum_threshold     = 1000,  -- was default 50
  autovacuum_vacuum_scale_factor  = 0,     -- drop the %-of-rows term (0–16 rows)
  autovacuum_analyze_threshold    = 1000,  -- stop analyze thrash too
  autovacuum_analyze_scale_factor = 0,
  fillfactor                      = 70     -- keep 30% page free for HOT updates
);

ALTER TABLE public.mint_rate_window SET (
  autovacuum_vacuum_threshold     = 1000,
  autovacuum_vacuum_scale_factor  = 0,
  autovacuum_analyze_threshold    = 1000,
  autovacuum_analyze_scale_factor = 0,
  fillfactor                      = 70
);

ALTER TABLE public.runtime_mint_intent SET (
  autovacuum_vacuum_threshold     = 1000,
  autovacuum_vacuum_scale_factor  = 0,
  autovacuum_analyze_threshold    = 1000,
  autovacuum_analyze_scale_factor = 0,
  fillfactor                      = 70
);
