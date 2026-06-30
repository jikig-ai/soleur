-- Verify 114_disk_io_top_wal_statements.sql.
--
-- Contract: every row returns `check_name` + `bad` (INTEGER). Any `bad > 0` row
-- fails CI verify-migrations.
--
-- 114 extends disk_io_pressure_signal() with the WAL-concentration lens
-- (top_wal_statements + max_wal_pct, sourced from extensions.pg_stat_statements)
-- while PRESERVING the 095 fields. Pin both the additions and the preservations,
-- plus the read-only operator-infra grant posture.

-- (1) still EXECUTABLE by service_role (the cron's only caller).
SELECT 'disk_io_signal_not_executable_by_service_role' AS check_name,
       (NOT has_function_privilege(
          'service_role',
          'public.disk_io_pressure_signal()',
          'EXECUTE'))::int AS bad
UNION ALL
-- (2) NOT executable by anon/authenticated (operator infra — never tenant-facing).
SELECT 'disk_io_signal_executable_by_anon',
       (has_function_privilege(
          'anon',
          'public.disk_io_pressure_signal()',
          'EXECUTE'))::int AS bad
UNION ALL
SELECT 'disk_io_signal_executable_by_authenticated',
       (has_function_privilege(
          'authenticated',
          'public.disk_io_pressure_signal()',
          'EXECUTE'))::int AS bad
UNION ALL
-- (3) the new WAL-concentration fields are present in the function body.
SELECT 'disk_io_signal_missing_top_wal_statements',
       (position('top_wal_statements' IN
          pg_get_functiondef('public.disk_io_pressure_signal()'::regprocedure)) = 0)::int AS bad
UNION ALL
SELECT 'disk_io_signal_missing_max_wal_pct',
       (position('max_wal_pct' IN
          pg_get_functiondef('public.disk_io_pressure_signal()'::regprocedure)) = 0)::int AS bad
UNION ALL
-- (4) the WAL source is the schema-qualified pg_stat_statements (search_path is
--     pinned public, pg_temp, so an unqualified reference would not resolve).
SELECT 'disk_io_signal_missing_pg_stat_statements_source',
       (position('extensions.pg_stat_statements' IN
          pg_get_functiondef('public.disk_io_pressure_signal()'::regprocedure)) = 0)::int AS bad
UNION ALL
-- (5) the 095 fields are PRESERVED (CREATE OR REPLACE must not regress them).
SELECT 'disk_io_signal_dropped_cache_hit_pct',
       (position('cache_hit_pct' IN
          pg_get_functiondef('public.disk_io_pressure_signal()'::regprocedure)) = 0)::int AS bad
UNION ALL
SELECT 'disk_io_signal_dropped_dedup_table_rows',
       (position('dedup_table_rows' IN
          pg_get_functiondef('public.disk_io_pressure_signal()'::regprocedure)) = 0)::int AS bad;
