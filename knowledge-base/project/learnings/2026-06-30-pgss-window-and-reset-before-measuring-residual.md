# Learning: pg_stat_statements window + reset-before-measuring-residual

## Problem

Issue #5739 cited Auth/GoTrue `pg_stat_statements` call counts (e.g. 1,586
`recovery_token` UPDATEs, 1,948 `refresh_tokens` INSERTs) as a possible runaway
loop and as evidence that auth was "the ~18% residual WAL source" after the 63%
webhook-dedup fix (#5736). Both framings were unverified against the actual stats
window.

Two traps:

1. **Counts without a window read as a loop.** `pg_stat_statements` is cumulative
   since the last reset. Reading `pg_stat_statements_info.stats_reset` showed the
   counts spanned **55 days** (reset 2026-05-06, read 2026-06-30), so 1,586 calls
   = ~29/day for 5 active users — normal magic-link/recovery volume, **not a loop**.
2. **Residual share is unmeasurable on a contaminated window.** #5736 merged but
   pgss had not been reset, so cumulative stats still showed the fixed source
   (`processed_github_events`) at 62.9%. The true post-fix auth share could not be
   known until a clean window was established.

## Solution

- Before treating any `pg_stat_statements` count as a loop/churn signal, read
  `SELECT stats_reset FROM pg_stat_statements_info` and divide counts by the window
  length and by active-user count. A "high" cumulative number is usually a long
  window, not a hot path.
- When a dominant WAL/IO source's fix lands and you need to measure the *residual*,
  run `SELECT pg_stat_statements_reset()` to start a clean post-fix window, then
  soak before re-measuring. Snapshot the pre-reset top-N first (into the
  brainstorm/issue) so cumulative history is preserved in an artifact.
- Pull this data yourself via the Supabase MCP `execute_sql` (read-only SELECTs;
  the reset is stats-only, no data mutation) rather than eyeballing a dashboard
  (`hr-no-dashboard-eyeball-pull-data-yourself`).

## Key Insight

A cumulative counter is meaningless without its reset timestamp, and a "residual"
cannot be measured while the dominant source it's residual *to* is still in the
window. Read the window, then (when a fix has landed) reset and soak — before
designing any optimization, especially a security-sensitive one (JWT TTL).

## Session Errors

None detected. The pgss-window correction was an investigation finding, not an
execution error. (Environmental note: no CCR environment was configured, so the
7-day soak re-measurement could not be scheduled as an autonomous fresh-session
agent; it was made turnkey via a copy-paste query posted to #5739 instead.)

## Tags
category: database-issues
module: supabase-auth-wal
issue: 5739
related: 5738, 5736
