-- Snapshot only; no query text, client addresses or backend IDs are returned.
-- A caller must enforce read-only transaction, timeout and per-arm failure state.
WITH observed AS MATERIALIZED (
  SELECT usename, usesysid::bigint AS role_oid,
         CASE WHEN application_name IS NULL THEN 'unknown' ELSE 'other' END AS application_class,
         CASE WHEN state IN ('active', 'idle', 'idle in transaction', 'idle in transaction (aborted)', 'fastpath function call', 'disabled')
              THEN state ELSE 'unknown' END AS state_class,
         CASE WHEN xact_start IS NULL THEN 'none_or_hidden'
              WHEN xact_start > clock_timestamp() THEN 'unknown'
              WHEN clock_timestamp() - xact_start < interval '1 minute' THEN 'under_1m'
              WHEN clock_timestamp() - xact_start < interval '15 minutes' THEN '1m_to_15m'
              ELSE '15m_or_more' END AS transaction_age_bucket
  FROM pg_catalog.pg_stat_activity
  WHERE datname = current_database()
  LIMIT 257
), summary AS (
  SELECT CASE WHEN pg_catalog.pg_has_role(current_user, 'pg_read_all_stats', 'USAGE')
              THEN 'full_stats_privilege' ELSE 'restricted' END AS visibility,
         count(*) AS observed_count
  FROM observed
)
SELECT json_build_object('kind', 'session_summary', 'visibility', visibility,
                         'observed_count', observed_count,
                         'capped', observed_count > 256,
                         'future_reconnects', 'unknown')::text
FROM summary
UNION ALL
SELECT json_build_object('kind', 'session', 'role_oid', role_oid, 'role_name', usename,
                         'application_class', application_class, 'state_class', state_class,
                         'transaction_age_bucket', transaction_age_bucket,
                         'write_capability', 'unknown')::text
FROM observed;
