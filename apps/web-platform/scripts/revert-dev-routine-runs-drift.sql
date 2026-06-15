-- revert-dev-routine-runs-drift.sql
-- One-time dev-Supabase drift revert for #5372.
--
-- CONTEXT: The orphan migration `104_routine_runs.sql` (from the OPEN WIP PR
-- #5342 `feat-routines-management`) was applied to dev at 2026-06-15 14:02 UTC
-- via ALLOW_UNMERGED_DEV_APPLY=1 and never reverted. Its WORM triggers
-- `routine_runs_no_update`/`routine_runs_no_delete` are STATEMENT-level and
-- raise P0001 unconditionally, while its FKs to public.users(id) are
-- ON DELETE SET NULL. A user delete fires a cascade `UPDATE routine_runs SET
-- actor_id=NULL WHERE actor_id=$1` that the statement-level trigger rejects
-- even against 0 rows — aborting the GDPR Art-17 account-delete cascade and
-- surfacing as the GoTrue `deleteUser` 500 that reddened `Tenant integration
-- (dev-Supabase)` on main. Root cause + analysis: issue #5372.
--
-- SAFETY: `public.routine_runs` and its companions DO NOT EXIST on origin/main
-- (verified: `git ls-tree origin/main -- apps/web-platform/supabase/migrations/`
-- has no `*routine_runs*` file; `104_outbound_email.sql` is the only merged 104).
-- This script ONLY drops the dev-only orphan objects and removes the single
-- orphan ledger row. It deliberately does NOT touch `105_turn_summary_message_
-- kind.sql` (a separate harmless orphan owned by the OPEN PR #5363) — removing
-- that ledger row without reverting its schema would create schema-vs-ledger
-- drift. Every statement is idempotent (`IF EXISTS`), so re-running is a no-op.
--
-- RUN (dev only):
--   cd apps/web-platform
--   doppler run -p soleur -c dev -- \
--     sh -c 'psql "$DATABASE_URL_POOLER" --no-psqlrc --single-transaction \
--            --set ON_ERROR_STOP=1 -f scripts/revert-dev-routine-runs-drift.sql'
--
-- The durable fix lives elsewhere: a blocking review comment + the
-- preflight-worm-cascade-contradiction gate (this PR) reject the contradiction
-- class at apply time before #5342 can re-introduce it.

-- 1. Drop the orphan RPC (explicit signature — overload-safe).
DROP FUNCTION IF EXISTS public.write_routine_run(
  text, text, text, text, text, uuid, uuid,
  timestamptz, timestamptz, integer, text
);

-- 2. Drop the table. CASCADE removes the two STATEMENT-level WORM triggers and
--    the two FKs to public.users along with it.
DROP TABLE IF EXISTS public.routine_runs CASCADE;

-- 3. Drop the now-unreferenced WORM trigger function.
DROP FUNCTION IF EXISTS public.routine_runs_no_mutate() CASCADE;

-- 4. Remove ONLY the orphan ledger row for the reverted migration.
DELETE FROM public._schema_migrations WHERE filename = '104_routine_runs.sql';
