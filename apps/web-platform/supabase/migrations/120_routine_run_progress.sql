-- 120_routine_run_progress.sql
-- Durable agent-run lifecycle (#5766) — mutable, ephemeral live-state sidecar for
-- in-flight HEAVY claude-loop crons. Makes "running" a queryable DB fact (the gap
-- 107_routine_runs left: it is terminal-only, "running is a transient UI state").
--
-- Written from spawnClaudeEval (upsert on entry + ~30s heartbeat) and deleted from
-- the run-log Inngest middleware transformOutput on terminal write. One row per
-- in-flight run, keyed by run_id. Orphans (evicted, never replayed) are bounded by
-- the reader (rows older than max-run-duration are ignored) — NO pg_cron sweep,
-- row count is bounded by the ~16 heavy routines.
--
-- Deliberately the INVERSE of 107_routine_runs's design:
--   * NOT WORM — this is mutable live state (heartbeat UPDATEs every ~30s), not a
--     terminal audit row. No no_mutate trigger.
--   * ATTRIBUTION-FREE — no actor_id / delegating_principal / FK to public.users.
--     Attribution stays on the terminal 107 row (already covered by
--     anonymise_routine_runs). This keeps the live surface OUT of the Art-17
--     erasure machinery and the WORM cascade entirely — there is no PII to scrub.
--   * run_id (Inngest UUID) and routine_id (fnId) are system identifiers, not PII.
-- Per 2026-04-18-supabase-migration-concurrently-forbidden: NO CREATE INDEX
-- CONCURRENTLY (Supabase wraps each migration in a transaction).
--
-- Writes are service_role only (BYPASSRLS) — no INSERT/UPDATE/DELETE policy; the
-- helper uses getServiceClient(). No SECURITY DEFINER RPC (direct .upsert()), so
-- no search_path pin is required (cf. cq-pg-security-definer-*).
--
-- Single-operator RLS assumption (ADR-077): SELECT is auth.uid() IS NOT NULL,
-- mirroring 107. Because the table is attribution-free it cannot be workspace-
-- scoped by policy alone; a workspace_id + is_workspace_member() predicate is
-- required before multi-tenant enablement (deferred, with the other not-yet-
-- workspace-keyed tables).
--
-- LAWFUL_BASIS: legitimate_interest (operational run observability; single-operator tenant)
-- RETENTION: ephemeral — deleted on terminal write; orphans reader-bounded by max-run-duration (no PII)

-- ============================================================================
-- routine_run_progress: mutable in-flight live-state. One row per running heavy
-- cron, keyed by Inngest run_id. Operator-readable; service-role-written.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.routine_run_progress (
  id                 uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  routine_id         text         NOT NULL,                 -- fnId in EXPECTED_CRON_FUNCTIONS
  run_id             text         NOT NULL UNIQUE,          -- Inngest run id; UNIQUE index backs ON CONFLICT + point lookups
  attempt            smallint     NOT NULL DEFAULT 1,       -- Inngest attempt; >1 => resumed (badge source)
  started_at         timestamptz  NOT NULL DEFAULT now(),   -- preserved across upserts (do NOT reset on replay)
  last_heartbeat_at  timestamptz  NOT NULL DEFAULT now()    -- bumped ~30s; staleness => stuck (reader-computed)
);

-- Reader scans by heartbeat staleness (stuck + ignore-bound both key on this).
-- Cosmetic at ~16 rows; the load-bearing index is the auto-created UNIQUE(run_id).
CREATE INDEX IF NOT EXISTS routine_run_progress_heartbeat_idx
  ON public.routine_run_progress (last_heartbeat_at DESC);

ALTER TABLE public.routine_run_progress ENABLE ROW LEVEL SECURITY;

-- Operator-readable SELECT only (single-operator tenant), mirrors routine_runs.
-- Writes go through the service client (BYPASSRLS); no write policy is defined.
CREATE POLICY routine_run_progress_authenticated_select ON public.routine_run_progress
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- Belt-and-suspenders: lock non-service writers out even if a future policy is
-- added by mistake. service_role bypasses RLS and retains its default grants.
REVOKE INSERT, UPDATE, DELETE ON public.routine_run_progress FROM anon, authenticated;
