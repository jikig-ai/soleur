-- 142_repair_conversation_engine_binding_backfill.sql
-- Migration 141 defaulted existing rows to pending before its bound-row
-- backfill, so its legacy-only predicate missed every pre-existing run.
-- Repair only rows with a persisted conversation run. No prompt or content
-- columns are read or changed.
-- The migration runner wraps this body and its ledger INSERT in one transaction.

-- A tenant role cannot authorize a marker transition with a custom GUC.
-- The SECURITY DEFINER bind RPC and the migration runner execute as postgres.
CREATE OR REPLACE FUNCTION public.guard_conversation_engine_binding_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.engine_binding_state IS DISTINCT FROM 'pending'
     AND current_user IS DISTINCT FROM 'postgres' THEN
    RAISE EXCEPTION 'conversation engine binding state is immutable' USING ERRCODE = '42501';
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.engine_binding_state IS DISTINCT FROM NEW.engine_binding_state
       AND current_user IS DISTINCT FROM 'postgres' THEN
      RAISE EXCEPTION 'conversation engine binding state is immutable' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER conversations_engine_binding_state_insert
  BEFORE INSERT ON public.conversations
  FOR EACH ROW EXECUTE FUNCTION public.guard_conversation_engine_binding_state();

UPDATE public.conversations AS c
   SET engine_binding_state = 'bound'
  FROM public.agent_engine_runs AS r
 WHERE r.conversation_id = c.id
   AND r.execution_kind = 'conversation'
   AND c.engine_binding_state IS DISTINCT FROM 'bound';
