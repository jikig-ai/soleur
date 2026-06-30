-- 114_disk_io_top_wal_statements.sql
--
-- Extends the disk-IO monitor signal RPC (migration 095) with a WAL-concentration
-- lens so a single statement dominating prod WAL pages is surfaced WITHOUT an
-- operator looking at a dashboard (hr-no-dashboard-eyeball-pull-data-yourself).
--
-- WHY: PR #5736 found a webhook dedup INSERT (processed_github_events) that was
-- 63% of prod WAL — the dominant Supabase Disk-IO consumer — yet shipped through
-- review + green CI because our lenses checked DB *correctness* and read
-- *latency*, never write *frequency × per-write WAL cost*. The 095 signal already
-- exposes cache_hit_pct (read regression), dedup_table_rows (retention stopped),
-- and top_write_churn (which table by ins+upd+del). But (ins+upd+del) row churn
-- is NOT WAL bytes: a small high-frequency write with full-page-writes can
-- dominate WAL while barely moving the row counters. This migration adds the
-- per-statement WAL truth source so the cron can alert on it directly.
--
-- WHAT THIS ADDS (preserving every existing return field):
--   * top_wal_statements — top 5 statements by pg_stat_statements.wal_bytes, each
--       {query (normalized, first ~120 chars), calls, wal_bytes, pct_of_wal}.
--       pg_stat_statements already normalizes literals to $1 placeholders, so the
--       query text carries no row values (no PII) — same posture as the other
--       operator-infra fields here.
--   * max_wal_pct — scalar: the single largest statement's share of total WAL
--       (max(wal_bytes)/sum(wal_bytes)*100). The cron alerts when this exceeds a
--       threshold (the #5736 INSERT would have read ~63 here).
--
-- pg_stat_statements lives in the `extensions` schema on Supabase (verified:
-- v1.11), so it is FULLY QUALIFIED below — the SET search_path = public, pg_temp
-- pin (cq-pg-security-definer-search-path-pin-pg-temp) deliberately does NOT
-- include `extensions`, so an unqualified reference would not resolve.
--
-- VISIBILITY DEPENDENCY (unchanged from 095): reading other backends' rows in
-- pg_stat_statements requires the OWNER to hold pg_monitor/pg_read_all_stats; on
-- Supabase migrations run as `postgres` (a pg_monitor member), so the SECURITY
-- DEFINER owner sees all statements. A role without it would see only its own
-- backend's queries.
--
-- search_path pinned public, pg_temp; SECURITY DEFINER; REVOKE from all + GRANT
-- EXECUTE to service_role only (the cron's caller) — same shape as 095.
--
-- See: knowledge-base/project/plans/2026-06-02-fix-supabase-disk-io-recurrence-and-sentry-monitor-plan.md Phase 3
-- See: apps/web-platform/server/inngest/functions/cron-supabase-disk-io.ts (op=wal-concentration)

CREATE OR REPLACE FUNCTION public.disk_io_pressure_signal()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'cache_hit_pct', (
      SELECT CASE
        WHEN COALESCE(sum(blks_hit) + sum(blks_read), 0) = 0 THEN 100.0
        ELSE round(
          sum(blks_hit)::numeric / (sum(blks_hit) + sum(blks_read)) * 100,
          3
        )
      END
      FROM pg_catalog.pg_stat_database
      WHERE datname = current_database()
    ),
    'dedup_table_rows', COALESCE((
      SELECT jsonb_object_agg(relname, n_live_tup)
      FROM pg_catalog.pg_stat_user_tables
      WHERE schemaname = 'public'
        AND relname IN ('processed_github_events', 'processed_stripe_events')
    ), '{}'::jsonb),
    'top_write_churn', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('table', relname, 'writes', writes))
      FROM (
        SELECT relname, (n_tup_ins + n_tup_upd + n_tup_del) AS writes
        FROM pg_catalog.pg_stat_user_tables
        WHERE schemaname = 'public'
        ORDER BY (n_tup_ins + n_tup_upd + n_tup_del) DESC
        LIMIT 5
      ) churn
    ), '[]'::jsonb),
    'top_wal_statements', COALESCE((
      SELECT jsonb_agg(
               jsonb_build_object(
                 'query', left(s.query, 120),
                 'calls', s.calls,
                 'wal_bytes', s.wal_bytes,
                 'pct_of_wal', CASE
                   WHEN t.total_wal > 0
                   THEN round(s.wal_bytes::numeric / t.total_wal * 100, 2)
                   ELSE 0
                 END
               )
               ORDER BY s.wal_bytes DESC
             )
      FROM (
        SELECT query, calls, wal_bytes
        FROM extensions.pg_stat_statements
        ORDER BY wal_bytes DESC NULLS LAST
        LIMIT 5
      ) s
      CROSS JOIN (
        SELECT COALESCE(sum(wal_bytes), 0)::numeric AS total_wal
        FROM extensions.pg_stat_statements
      ) t
    ), '[]'::jsonb),
    'max_wal_pct', (
      SELECT CASE
        WHEN COALESCE(sum(wal_bytes), 0) = 0 THEN 0
        ELSE round(max(wal_bytes)::numeric / sum(wal_bytes) * 100, 2)
      END
      FROM extensions.pg_stat_statements
    ),
    'sampled_at', now()
  );
$$;

REVOKE ALL ON FUNCTION public.disk_io_pressure_signal()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.disk_io_pressure_signal()
  TO service_role;
