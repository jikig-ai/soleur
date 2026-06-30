---
date: 2026-06-30
category: performance-issues
module: supabase-ops
tags: [supabase, disk-io, wal, pg_stat_statements, work_mem, management-api, webhook-dedup]
related_pr: 5736
related_issues: [5738, 5739]
---

# Learning: Diagnosing a Supabase "Disk IO Budget depleting" warning (write-IO, not read-IO) and changing Postgres config via the Management API

## Problem

Supabase emailed a "depleting its Disk IO Budget" warning for prod project
`soleur-web-platform` (ref `ifsccnjhymdmidffkzhl`). The instinct is to reach for
missing indexes / table bloat / a compute upgrade. All three would have been the
wrong layer.

## Key Insight — on a small, fully-cached DB, Disk IO is WRITE-dominated

Live telemetry (via the Supabase MCP `execute_sql`):

- `pg_stat_database`: DB was **46 MB** with a **100% cache hit rate** (`blks_hit`
  2.0B vs `blks_read` 1,636). Data fully fits in RAM → reads do not touch disk.
  So missing indexes / seq-scans / bloat are NOT the problem on a cached DB.
- The budget was consumed by **writes**: ~**12 GB/day WAL** (every commit fsyncs)
  + ~**3.4 GB/day temp-file** spillage (`temp_bytes` 62 GB cumulative;
  `work_mem` was only 2 MB so sorts spill).
- **The decisive query is `pg_stat_statements` ordered by `wal_bytes`** — it
  attributes WAL (= the dominant write disk-IO) per normalized statement. Here a
  single `INSERT INTO processed_github_events(delivery_id)` was **63% of all WAL**
  (738 MB; ~4 KB/insert because each triggered full-page writes). NOT table sizes,
  NOT `pg_stat_user_tables` seq-scans — those mislead on a cached DB.

Diagnosis ladder that works: `pg_stat_database` (cache-hit% + temp_bytes + a
WAL-rate delta over a short window via `pg_wal_lsn_diff(pg_current_wal_lsn(),'0/0')`)
→ `pg_stat_statements ORDER BY wal_bytes DESC` (the culprit) → `pg_stat_statements
ORDER BY temp_blks_written DESC` (temp spillers; note pgss EVICTS at `pgss.max`, so
heavy historical statements may be absent — measure the current rate instead).

The fix was therefore **workload reduction** (stop writing the WAL), not a compute
add-on: a "drop-before-dedup" reorder of the GitHub webhook handler so the
`processed_github_events` dedup INSERT fires only for deliveries that actually
dispatch (PR #5736). Secondary: raise `work_mem` to cut temp spills.

## Key Insight — Supabase Postgres config (work_mem, log_temp_files) cannot be set via SQL; use the Management API

- `ALTER DATABASE postgres SET work_mem = '4MB'` (and `log_temp_files`) via the
  Supabase MCP / `postgres` role → **`ERROR: 42501: permission denied to set
  parameter`**. The managed `postgres` role is not superuser for these GUCs.
- The correct path is the **Management API**, authenticated with a token from
  Doppler (`soleur/prd` has `SUPABASE_ACCESS_TOKEN` and `SUPABASE_PAT`):
  - Read:  `GET  https://api.supabase.com/v1/projects/{ref}/config/database/postgres`
  - Write: **`PUT`** (NOT `PATCH` — `PATCH` returns `404 "Cannot PATCH …"`)
    with body `{"work_mem":"4MB"}`.
  - Compute size / RAM (to size `work_mem` safely): `GET …/billing/addons` →
    `available_addons[].variants[].meta.memory_gb`. No `compute_instance` in
    `selected_addons` ⇒ the default **Micro (1 GB RAM, 87 MB/s baseline disk IO)**.
- **The change applies ASYNCHRONOUSLY.** After a successful `PUT` (GET confirms the
  override is stored) the running value can still read the old number for many
  minutes — `pg_settings.source = 'configuration file'`, `pending_restart = false`.
  Supabase's reconciler writes the conf + reloads on its own cycle (often the next
  restart/deploy). `work_mem` is reload-only (no restart needed), but a forced
  immediate apply requires a brief DB restart — not worth it for a secondary tune;
  let it ride the next deploy.
- Size `work_mem` against instance RAM: on a 1 GB Micro, 2 MB → 4 MB is safe
  (worst-case ~60 backends × 4 MB has headroom); avoid 8 MB+ on 1 GB.

## Session Errors

1. **`send_later` MCP tool unavailable** — returned "can only be called from
   within a CCR session." Recovery: didn't schedule a re-measure; computed the
   temp/WAL rate inline from two `pg_stat_database` reads instead. Prevention:
   `send_later`/`create_trigger` need a CCR session context; in a plain CLI session,
   measure inline or re-query in a later turn. (one-off — environment-specific.)
2. **`ALTER DATABASE … SET work_mem` permission denied (42501)** — Recovery: used
   the Management API. Prevention: this learning (Supabase GUC = Management API,
   never SQL). (recurring.)
3. **Management API `PATCH` config → 404** — Recovery: switched to `PUT`.
   Prevention: this learning (config update verb is PUT). (recurring.)
4. **Observer effect on temp-file rate** — my own `pg_stat_statements` diagnostic
   queries spill ~2 MB temp each (large sort of normalized query texts at
   `work_mem=2MB`), inflating the measured temp rate. Prevention: discount your own
   monitoring queries when measuring temp-spill rate on a low-`work_mem` instance;
   Supabase's own dashboard/advisor pgss queries are themselves a steady temp
   contributor. (one-off, but worth noting.)

## Prevention / Reusable Procedure

When a Supabase Disk IO Budget warning fires:
1. `pg_stat_database`: if cache_hit ≈ 100% and the DB is small, STOP looking at
   indexes/bloat — it's write-IO.
2. `pg_stat_statements ORDER BY wal_bytes DESC` → the #1 WAL writer is the lever.
3. Reduce that write's frequency (workload reduction) before upgrading compute.
4. For `work_mem`/`log_temp_files`: Management API `PUT …/config/database/postgres`
   with a Doppler `SUPABASE_ACCESS_TOKEN`; expect async apply.
