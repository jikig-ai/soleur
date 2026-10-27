-- Cascading attempt deletion must not scan the full event history per attempt.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
CREATE INDEX IF NOT EXISTS agent_engine_events_attempt_id_idx
  ON public.agent_engine_events (attempt_id);
COMMIT;
