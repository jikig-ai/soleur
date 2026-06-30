-- 114_disk_io_top_wal_statements.down.sql
-- Reversal of 114_disk_io_top_wal_statements.sql.
--
-- 114 was a CREATE OR REPLACE that ADDED top_wal_statements + max_wal_pct to an
-- EXISTING function (first created by 095). A bare DROP would remove the function
-- entirely and break the cron; the correct reversal restores the prior (095)
-- body verbatim. SECURITY DEFINER + search_path pin + REVOKE/GRANT are repeated
-- so this down file is itself compliant with the migration RPC-grant + search_path
-- lint (which scans .down.sql files too).

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
    'sampled_at', now()
  );
$$;

REVOKE ALL ON FUNCTION public.disk_io_pressure_signal()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.disk_io_pressure_signal()
  TO service_role;
