# Learning: A pg_cron retention sweep whose window exceeds the table's max age grows unbounded silently

## Problem

Prod Supabase re-sent a Disk-IO Budget depletion warning (issue #5225) ~12 days after the 2026-06-02 remediation that was supposed to fix exactly this. The proactive monitor (`cron-supabase-disk-io`, migration 095) had already fired correctly on 2026-06-12 and filed #5225, but the table kept growing (123,416 → 128,589 rows over two days) and no operator had acted.

The monitor's diagnostic text said **"retention sweep may have stopped — check cron.job"**, and the auto-triage comment escalated that to **"the retention sweep cron has likely stopped."** Both were wrong.

## Root cause

The `processed_github_events_retention` pg_cron job (migration 094) WAS scheduled (`0 4 * * *`), active, and `succeeded` every single night — but every run reported **`DELETE 0`**. Live diagnostics:

- `cache_hit_pct = 100%` → not read-driven; the burn is write/churn-side (INSERT + index growth).
- `cron.job_run_details`: the retention job ran daily, status `succeeded`, message `DELETE 0`.
- Age distribution: the table's **oldest row was only ~24 days old** (oldest `received_at = 2026-05-21`), but the retention window was **90 days**. So `received_at < now() - interval '90 days'` matched **zero rows**, every night, forever.

The 90-day window was copied verbatim into migration 094 from the `processed_stripe_events` sibling (where 90d legitimately equals Stripe's replay horizon). But `processed_github_events` is a GitHub-webhook dedup table whose replay need is **3 days** (github.com deletes webhook delivery logs after 3 days; redelivery is impossible past then). At ~5k inserts/day, a 90-day window means the table bloats to a ~450k-row steady state before the first row is ever old enough to delete — and the constant INSERT + index write IO is what depletes the Disk-IO budget.

A contributing cause: a **stale `COMMENT ON TABLE`** in migration 052 claimed retention was *"Postgres autovacuum + 30-day partition rotation (natural cleanup; no TTL daemon)"* — factually false (the table is not partitioned, has no TTL daemon). That false comment is what led migration 094 to reach for a long, Stripe-shaped window instead of the table's real 3-day horizon.

## Solution

Migration 103 (`103_github_events_retention_7day.sql`):
1. Re-schedule `processed_github_events_retention` with `interval '7 days'` (>2× margin over GitHub's 3-day ceiling; second layer: the Inngest 24h `event.id` dedup).
2. **One-time** `DELETE FROM public.processed_github_events WHERE received_at < now() - interval '7 days'` in the same file so relief lands at deploy (~91k stale rows). `run-migrations.sh` wraps each file in `psql --single-transaction`, so re-schedule + purge are atomic.
3. Correct the stale `COMMENT ON TABLE` so the next retention change doesn't re-derive the wrong window.
4. Widen the monitor's over-ceiling reason string to name BOTH causes: "retention sweep stopped OR its window exceeds the table's replay horizon so it deletes nothing."

`releaseDedupRow` re-INSERTs a redelivered row with `received_at = now()`, so a row's timestamp always reflects its most recent claim — the 7-day purge can never delete a row inside an active redelivery cycle.

## Key Insight

**A retention sweep that runs successfully but reports `DELETE 0` indefinitely is a silent unbounded-growth bug, not a healthy sweep.** When a row-count tripwire fires on a table that has a retention cron, do NOT assume "the cron stopped" — pull `cron.job_run_details` (is it running? what does it return?) AND the table's age distribution (`min(received_at)` vs the DELETE window). If `max age of table < retention window`, the sweep is structurally incapable of deleting anything and the window is the defect.

Corollaries:
- **Don't copy a retention window between sibling dedup tables without re-deriving each table's own replay/aging horizon.** Stripe's 90 days ≠ GitHub's 3 days. The window must be derived from the data's actual replay need, not mirrored for symmetry.
- **A stale `COMMENT ON TABLE` propagates wrong design decisions across copied migrations.** Correct it at the source when you find it misled a later change.
- **Make a monitor's diagnostic text enumerate every cause its tripwire fires on.** A row-count-over-ceiling breach has ≥2 causes (cron stopped vs. window-too-long); a single-cause message ("sweep stopped") sends the operator down the wrong path.

## Session Errors

- **Edit on a worktree file was rejected ("File has not been read yet")** because the file had been Read at its bare-root path during diagnosis, not at the worktree path; the harness tracks read-state per absolute path. **Recovery:** Read the worktree copy, then edited. **Prevention:** already covered by hard rule `hr-when-in-a-worktree-never-read-from-bare` — in a worktree pipeline, Read from the worktree path before editing even when a bare-root copy was inspected during diagnosis.
- **Supabase MCP required interactive OAuth.** **Recovery:** used the Management API (`api.supabase.com/v1/projects/<ref>/database/query`) with `SUPABASE_ACCESS_TOKEN` from Doppler `prd`. **Prevention:** already covered by [[2026-05-06-supabase-management-api-bypasses-mcp-oauth]] — for read-only prod diagnostics, reach for the Doppler-token + REST path first, treat MCP as secondary.

## Tags
category: database-issues
module: supabase
related: [[2026-06-02-fix-supabase-disk-io-recurrence-and-sentry-monitor-plan]], [[2026-05-06-supabase-disk-io-structural-overhead-dominates-at-low-scale]], [[2026-05-06-supabase-management-api-bypasses-mcp-oauth]]
