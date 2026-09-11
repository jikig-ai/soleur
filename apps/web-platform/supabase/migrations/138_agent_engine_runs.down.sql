BEGIN;
DROP FUNCTION IF EXISTS public.set_workspace_default_engine(uuid, text);
DROP TABLE IF EXISTS public.agent_engine_events;
DROP TABLE IF EXISTS public.agent_engine_runs;
DROP TABLE IF EXISTS public.workspace_engine_settings;
COMMIT;
