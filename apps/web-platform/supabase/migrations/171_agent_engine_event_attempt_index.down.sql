BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
DROP INDEX IF EXISTS public.agent_engine_events_attempt_id_idx;
COMMIT;
