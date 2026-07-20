-- 118_tool_attempts.sql
--
-- TR3 tool-attempt telemetry (#5843, parent #5772 lever 2; ADR-070 amendment).
-- A fail-open, opt-in, web-only collector records WHICH available tools the
-- agent attempts per workflow phase on the cc-soleur-go Concierge path,
-- aggregated ONE ROW PER conversation-session, so the never-needed-per-phase
-- subset can be computed empirically:
--
--     never-needed-per-phase = available(per-path config) − attempted(observed)
--
-- WHY aggregated-row (not insert-per-tool-call): an insert-per-call design would
-- add per-tool WAL + index write IO on the hot prod agent path for every user
-- (the exact Disk-IO failure class 114/115 + PR #5736 addressed). The collector
-- accumulates counts in an in-memory closure and flushes ONE jsonb row at query
-- teardown (soleur-go-runner closeQuery → cc-dispatcher handleCcCloseQuery).
--
-- PRIVACY (CRITICAL-2, plan §User-Brand Impact): the row is ANONYMOUS per
-- session. There is deliberately NO session_id / user_id / conversation_id
-- column — the SDK `BaseHookInput.session_id` is UNIQUE-indexed to `user_id`
-- (028_conversations_user_id_session_id_unique.sql), so persisting it would make
-- the row joinable to auth.uid(). The in-memory accumulator keys on a
-- closure-minted `crypto.randomUUID()` that never reaches this table. `counts`
-- carries only phase names (a fixed enum) and tool names (sanitized); NO
-- tool_input is ever recorded (NO-ECHO). Nothing here is personal data.
--
-- LAWFUL_BASIS: legitimate_interest (aggregated, anonymous tool-usage telemetry
--   to compute the never-needed-per-phase tool set for #5772 lever 2; no personal
--   data, no user/session join, TTL-bounded).
-- RETENTION: 90 days via pg_cron `tool_attempts_retention` (below). One row per
--   cc conversation-session; low volume. Analytics-only — absence is not an
--   incident (see plan §Observability).
--
-- Atomicity: run-migrations.sh runs each file under `psql --single-transaction`,
-- so the CREATE TABLE + cron schedule commit/rollback as one unit. The
-- `EXCEPTION WHEN duplicate_object` guard is belt-and-suspenders (mirror 103/107).
-- Per 2026-04-18-supabase-migration-concurrently-forbidden: NO CREATE INDEX
-- CONCURRENTLY (Supabase wraps each migration in a transaction).
--
-- See: knowledge-base/project/plans/2026-07-01-feat-tr3-tool-attempt-telemetry-plan.md

-- ============================================================================
-- tool_attempts: anonymous, aggregated one-row-per-session tool-attempt log.
-- Service-role-only: RLS is ENABLED with NO policies, so anon/authenticated get
-- default-deny; the service client (BYPASSRLS) is the sole writer/reader. Writes
-- are a plain `.insert()` via createServiceClient() (server/tool-attempt-
-- telemetry.ts), mirroring the processed_github_events service-role convention.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.tool_attempts (
  id          uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at  timestamptz  NOT NULL DEFAULT now(),
  -- { "<phase|unrouted>": { "<sanitized_tool_name>": <int> } }. Phase keys are a
  -- fixed workflow enum; tool keys are sanitizeToolNameForLog'd. NO tool_input.
  counts      jsonb        NOT NULL
);

ALTER TABLE public.tool_attempts ENABLE ROW LEVEL SECURITY;
-- No RLS policies by design → default-deny for anon/authenticated. service_role
-- bypasses RLS (Supabase BYPASSRLS attribute); it is the only reader/writer.

COMMENT ON TABLE public.tool_attempts IS
  'TR3 anonymous aggregated tool-attempt telemetry (#5843, ADR-070). One jsonb '
  'row per cc-soleur-go conversation-session: counts = {phase|unrouted: {tool: '
  'int}}. NO session/user/conversation column (anonymous per CRITICAL-2); NO '
  'tool_input (NO-ECHO). Service-role-only via createServiceClient(). Retention: '
  '90d via pg_cron tool_attempts_retention. Used once to compute #5772 lever-2 '
  'never-needed-per-phase set (available − attempted).';

-- ============================================================================
-- Retention: daily pg_cron purge of rows older than 90 days (mirror 103/107).
-- Guarded unschedule-before-schedule + EXCEPTION WHEN duplicate_object so a
-- re-apply is idempotent.
-- ============================================================================

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'tool_attempts_retention') THEN
    PERFORM cron.unschedule('tool_attempts_retention');
  END IF;
  PERFORM cron.schedule(
    'tool_attempts_retention',
    '0 4 * * *',
    $$DELETE FROM public.tool_attempts WHERE created_at < now() - interval '90 days'$$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron_block$;
