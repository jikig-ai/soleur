-- 104_routine_runs.sql
-- Routines management UI (#5345 PR-1) — durable, append-only run-log for the
-- EXPECTED_CRON_FUNCTIONS crons. Written centrally by the run-log Inngest
-- middleware (terminal-only: one row per completed/failed run; "running" is a
-- transient UI state, not a DB fact).
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: the write RPC pins
-- SET search_path = public, pg_temp and qualifies relations as public.<table>.
-- Per 2026-04-18-supabase-migration-concurrently-forbidden: NO CREATE INDEX
-- CONCURRENTLY (Supabase wraps each migration in a transaction).
--
-- LAWFUL_BASIS: legitimate_interest (operational audit of operator-/agent-triggered routine runs; single-operator tenant)
-- RETENTION: indefinite (operational audit log; ~one row per routine run, low volume). Revisit if volume grows (cf. 103_github_events_retention_7day).

-- ============================================================================
-- routine_runs: append-only WORM run-log. One row per terminal routine run.
-- Operator-readable (single-operator tenant — all runs are the company's runs,
-- including scheduled runs where actor_id IS NULL). WORM enforced by trigger;
-- writes go through write_routine_run (SECURITY DEFINER, service-role only).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.routine_runs (
  id                    uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  routine_id            text         NOT NULL,                  -- fnId in EXPECTED_CRON_FUNCTIONS
  run_id                text,                                   -- Inngest run id
  status                text         NOT NULL,                  -- 'completed' | 'failed'
  trigger_source        text         NOT NULL,                  -- 'scheduled' | 'manual' | 'agent'
  actor_class           text         NOT NULL,                  -- 'system' | 'human' | 'agent'
  actor_id              uuid         REFERENCES public.users(id) ON DELETE SET NULL,
  delegating_principal  uuid         REFERENCES public.users(id) ON DELETE SET NULL,
  started_at            timestamptz  NOT NULL,
  ended_at              timestamptz  NOT NULL,
  duration_ms           integer      NOT NULL,
  error_summary         text,                                   -- failed runs: scrubbed + truncated (middleware)
  created_at            timestamptz  NOT NULL DEFAULT now()
);

ALTER TABLE public.routine_runs ENABLE ROW LEVEL SECURITY;

-- Operator-readable SELECT only (single-operator tenant: authenticated operator
-- sees every run, incl. scheduled runs with actor_id IS NULL). No INSERT/UPDATE/
-- DELETE policies; writes go through write_routine_run (SECURITY DEFINER) below.
CREATE POLICY routine_runs_authenticated_select ON public.routine_runs
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- WORM trigger function. Raised on UPDATE or DELETE (pure append-only).
CREATE OR REPLACE FUNCTION public.routine_runs_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'routine_runs is append-only (WORM)' USING ERRCODE = 'P0001';
END;
$$;

REVOKE ALL ON FUNCTION public.routine_runs_no_mutate() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER routine_runs_no_update
  BEFORE UPDATE ON public.routine_runs
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.routine_runs_no_mutate();

CREATE TRIGGER routine_runs_no_delete
  BEFORE DELETE ON public.routine_runs
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.routine_runs_no_mutate();

-- last-run-per-routine + Recent Runs (reverse-chronological) hot paths.
CREATE INDEX routine_runs_routine_started_idx
  ON public.routine_runs (routine_id, started_at DESC);
CREATE INDEX routine_runs_started_idx
  ON public.routine_runs (started_at DESC);

-- write_routine_run: append-only RPC, service-role only (called by the run-log
-- middleware on a routine's final attempt).
CREATE OR REPLACE FUNCTION public.write_routine_run(
  p_routine_id            text,
  p_run_id                text,
  p_status                text,
  p_trigger_source        text,
  p_actor_class           text,
  p_actor_id              uuid,
  p_delegating_principal  uuid,
  p_started_at            timestamptz,
  p_ended_at              timestamptz,
  p_duration_ms           integer,
  p_error_summary         text
) RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  INSERT INTO public.routine_runs(
    routine_id, run_id, status, trigger_source, actor_class, actor_id,
    delegating_principal, started_at, ended_at, duration_ms, error_summary
  )
  VALUES (
    p_routine_id, p_run_id, p_status, p_trigger_source, p_actor_class, p_actor_id,
    p_delegating_principal, p_started_at, p_ended_at, p_duration_ms, p_error_summary
  );
$$;

-- Named-role revoke is load-bearing (Supabase auto-grants EXECUTE to anon,
-- authenticated, service_role on every new function; REVOKE FROM PUBLIC does
-- not undo the explicit-role grants).
REVOKE ALL ON FUNCTION public.write_routine_run(text, text, text, text, text, uuid, uuid, timestamptz, timestamptz, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.write_routine_run(text, text, text, text, text, uuid, uuid, timestamptz, timestamptz, integer, text) TO service_role;

COMMENT ON TABLE public.routine_runs IS
  'Append-only WORM run-log for EXPECTED_CRON_FUNCTIONS crons (#5345). One row '
  'per terminal run; written by the run-log Inngest middleware on final attempt.';

-- Latest run per routine (DISTINCT ON). security_invoker so the underlying
-- routine_runs RLS (operator-select) is enforced for the querying session —
-- the dashboard Routines tab reads this for each row's last-run summary.
CREATE VIEW public.routine_runs_latest
  WITH (security_invoker = true) AS
  SELECT DISTINCT ON (routine_id)
    id, routine_id, run_id, status, trigger_source, actor_class,
    actor_id, delegating_principal, started_at, ended_at, duration_ms, error_summary
  FROM public.routine_runs
  ORDER BY routine_id, started_at DESC;

GRANT SELECT ON public.routine_runs_latest TO authenticated;
