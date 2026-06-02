-- 095_disk_io_pressure_signal.sql
--
-- Read-only signal RPC for the proactive Disk-IO monitor
-- (apps/web-platform/server/inngest/functions/cron-supabase-disk-io.ts).
--
-- WHY AN RPC: the monitor needs pg_catalog stat views (pg_stat_database,
-- pg_stat_user_tables) that PostgREST does not expose to the service-role
-- client. A SECURITY DEFINER function owned by the migration role (which has
-- pg_monitor) can read them and return an aggregate JSON, callable via
-- supabase-js .rpc(). This avoids provisioning a Supabase Management API PAT
-- into the web-platform runtime container (the app already has the service-role
-- key, but not a Management API token) — same posture as the other read-only
-- cron probes (cron-workspace-sync-health).
--
-- The 2026-06-02 diagnosis was WRITE-driven: cache hit = 100.000% (1,614 disk
-- reads vs 1.04B cache hits), so the budget burn is writes, not reads. The
-- signal therefore exposes:
--   * cache_hit_pct      — a read-pressure REGRESSION tripwire (drops below
--                          ~99% if a future change introduces table scans).
--   * dedup_table_rows   — live-row counts for the two unbounded dedup tables
--                          the 094 retention sweeps now bound. A climbing count
--                          is the early warning that a retention cron stopped
--                          (the exact recurrence this feature prevents).
--   * top_write_churn    — top-5 public tables by (ins+upd+del), diagnostic
--                          context folded into the alert so the operator sees
--                          WHICH table is driving writes without SSH.
--
-- The gated counts are O(1) catalog reads (n_live_tup is an estimate, not a
-- scan). top_write_churn does a bounded top-5 sort over the in-memory
-- pg_stat_user_tables view (no on-disk IO, no heap scan) — it is diagnostic
-- context only, not a verdict input. Either way the monitor adds negligible IO.
--
-- VISIBILITY DEPENDENCY: this function reads cluster-wide stat rows, which
-- require the OWNER role to hold pg_monitor (or be superuser); a role without it
-- sees only its own backend's rows (others NULL-masked). On Supabase, migrations
-- run as `postgres` (a pg_monitor member), so this holds. The post-deploy
-- manual-trigger check (a non-null cache_hit_pct on first fire) is the runtime
-- confirmation that the owner role has the required visibility.
--
-- search_path pinned public, pg_temp per cq-pg-security-definer-search-path-pin-pg-temp.
-- Read-only: REVOKE from all, GRANT EXECUTE to service_role only (the cron's
-- caller). No authenticated/anon access — this is operator infrastructure.
--
-- See: knowledge-base/project/plans/2026-06-02-fix-supabase-disk-io-recurrence-and-sentry-monitor-plan.md Phase 3

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
