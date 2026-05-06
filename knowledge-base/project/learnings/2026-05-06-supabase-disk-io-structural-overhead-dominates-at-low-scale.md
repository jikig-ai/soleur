# Learning: Supabase Disk IO Budget alerts at low scale point to STRUCTURAL overhead, not user queries

**Date:** 2026-05-06
**Source session:** Brainstorm for prod Disk IO Budget alert (`feat-supabase-disk-io-budget`, issue #3358, draft PR #3356).
**Category:** performance-issues / database-issues
**Tags:** category=performance-issues, module=supabase, postgres, realtime, pg_cron

## Problem

Supabase emailed an overnight alert that prod project `ifsccnjhymdmidffkzhl` (soleur-web-platform, eu-west-1, Micro tier, 87 MB/s baseline disk IO) was depleting its Disk IO Budget. The intuition reach was "find the IO-heavy user query and index it." The actual top consumers had nothing to do with user queries.

## Investigation

`pg_stat_statements` ordered by `total_exec_time` showed:

1. **Realtime WAL parser** (`SELECT wal->>$5 as type, ...`) — 1,119,896 ms / 219,793 calls / 325M block hits / 100% cache hit.
2. **Realtime WAL parser variant** — 88,151 ms / 25,437 calls.
3. `SELECT name FROM pg_timezone_names` — 74,174 ms / 102 calls (Studio dashboard query, 727 ms each).
4. **`INSERT INTO cron.job_run_details`** — 68,783 ms / 20,478 calls.

`pg_stat_user_tables` showed live-row counts of 58 conversations, 126 messages, 0 live concurrency slots — essentially an empty database. Combined daily write churn across all `public.*` tables was a few hundred operations.

`cron.job` had a single scheduled job — `delete from public.user_concurrency_slots where last_heartbeat_at < now() - interval '120 seconds';` running every minute (1,440 runs/day). Each pg_cron run produces 3 writes to `cron.job_run_details` (insert + 2 updates) on top of the actual work. Net: ~5,760 cron-internal writes/day for a sweep that deleted 38 rows in 14+ days.

## Root cause

Two structural cost centers, both independent of user activity:

1. **Realtime polls the WAL stream every ~100 ms** (the configured publication on `conversations` + `messages` from migration 034 amplifies WAL traffic, but the polling itself runs whether or not anything changed). This explains the 219K calls in the window.

2. **pg_cron's plumbing writes 3 rows to `cron.job_run_details` per run**, regardless of whether the job's actual SQL did any work. A schedule of `* * * * *` for a sweep that mostly does nothing is structurally hostile to the IO budget.

User-row churn was not in the top 15 by exec time. Indexing user queries would have been wasted effort.

## Working solution

This learning captures the diagnostic ordering, not the fix (the fix lands on `feat-supabase-disk-io-budget` per spec). Two-lever path:

- **Lever (a) — slow the pg_cron sweep:** `cron.alter_job(jobid, schedule := '*/5 * * * *')` (or `*/15`) via a forward migration. Reversible with the same call.
- **Lever (b) — audit the Realtime publication:** decide whether the consumer in `apps/web-platform/hooks/use-conversations.ts:232-279,294-316` actually needs the postgres_changes subscription, or if scoping (event-type / row filters) or replacement (on-demand fetch) suffices.

## Key insight

For Supabase Disk IO Budget alerts on a small/young instance, **pull `cron.job` schedule and the Realtime publication scope BEFORE inspecting business queries.** Structural overhead dominates at low scale. The order of diagnosis should be:

1. `pg_stat_statements` top 10 by `total_exec_time` — does Realtime or `cron.*` dominate? If yes, structural fix.
2. `cron.job` — what's scheduled and how often? Run-counts via `cron.job_run_details`.
3. Realtime publication membership — `SELECT * FROM pg_publication_tables WHERE pubname = 'supabase_realtime';` Are hot tables in the publication for no UI reason?
4. ONLY THEN inspect `pg_stat_user_tables` and business queries.

This inverts the instinct ("indexable hot query") with the empirical pattern at low scale ("structural plumbing dominates").

## Reusable diagnostics

```bash
SUPA_TOKEN=$(doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain)
REF=ifsccnjhymdmidffkzhl
QPATH="https://api.supabase.com/v1/projects/$REF/database/query"

# Top 15 queries by total exec time
Q='SELECT round(total_exec_time::numeric, 1) AS total_ms, calls, round(mean_exec_time::numeric, 2) AS mean_ms, shared_blks_read, shared_blks_hit, left(query, 220) AS query FROM pg_stat_statements WHERE query NOT ILIKE '\''%pg_stat_statements%'\'' ORDER BY total_exec_time DESC LIMIT 15'
curl -sS -X POST -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" "$QPATH" -d "{\"query\": $(jq -Rn --arg q "$Q" '$q')}"

# Cron schedule + run counts in last 24h
Q='SELECT jobid, schedule, command, active FROM cron.job ORDER BY jobid'
curl -sS -X POST -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" "$QPATH" -d "{\"query\": $(jq -Rn --arg q "$Q" '$q')}"

Q='SELECT jobid, count(*) AS runs FROM cron.job_run_details WHERE start_time > now() - interval '\''24 hours'\'' GROUP BY jobid ORDER BY runs DESC'
curl -sS -X POST -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" "$QPATH" -d "{\"query\": $(jq -Rn --arg q "$Q" '$q')}"

# Top tables by write churn + dead tuples
Q='SELECT schemaname, relname, n_tup_ins AS ins, n_tup_upd AS upd, n_tup_del AS del, n_live_tup AS live, n_dead_tup AS dead, last_autovacuum, autovacuum_count AS av FROM pg_stat_user_tables WHERE schemaname IN ('\''public'\'','\''cron'\'','\''realtime'\'') ORDER BY (n_tup_ins+n_tup_upd+n_tup_del) DESC LIMIT 15'
curl -sS -X POST -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" "$QPATH" -d "{\"query\": $(jq -Rn --arg q "$Q" '$q')}"

# Realtime publication membership
Q='SELECT * FROM pg_publication_tables WHERE pubname = '\''supabase_realtime'\'''
curl -sS -X POST -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" "$QPATH" -d "{\"query\": $(jq -Rn --arg q "$Q" '$q')}"
```

## Prevention

- Future Supabase IO-budget alerts: lead with the four queries above, in that order. The brainstorm `references/` could embed them as a runbook block, but the discoverability bar is met by this learning file alone — the next page hitting an IO alert will land here via `learnings-researcher`.
