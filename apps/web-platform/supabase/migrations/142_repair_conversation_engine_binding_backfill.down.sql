-- Restore migration 141's trigger contract if this unmerged migration is
-- discarded from dev. The corrected bound markers remain; their prior values
-- cannot be identified safely after later binds.

DROP TRIGGER IF EXISTS conversations_engine_binding_state_insert ON public.conversations;

CREATE OR REPLACE FUNCTION public.guard_conversation_engine_binding_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.engine_binding_state IS DISTINCT FROM NEW.engine_binding_state
     AND current_setting('soleur.engine_binding_rpc', true) IS DISTINCT FROM '1' THEN
    RAISE EXCEPTION 'conversation engine binding state is immutable' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
