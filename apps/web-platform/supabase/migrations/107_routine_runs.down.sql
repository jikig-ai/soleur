-- 107_routine_runs.down.sql — revert 107_routine_runs.sql
DROP VIEW IF EXISTS public.routine_runs_latest;
DROP FUNCTION IF EXISTS public.anonymise_routine_runs(uuid);
DROP FUNCTION IF EXISTS public.write_routine_run(text, text, text, text, text, uuid, uuid, timestamptz, timestamptz, integer, text);
DROP TRIGGER IF EXISTS routine_runs_no_update ON public.routine_runs;
DROP TRIGGER IF EXISTS routine_runs_no_delete ON public.routine_runs;
DROP FUNCTION IF EXISTS public.routine_runs_no_mutate();
DROP TABLE IF EXISTS public.routine_runs;
