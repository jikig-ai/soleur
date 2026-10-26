-- run-migrations.sh injects this before migration 167 in the SAME transaction
-- as its unchanged body and ledger insert. The locks exclude mode changes and
-- run inserts until the constrained backfill finishes. Do not run admission
-- checks as separate count queries: that leaves a write window before the ALTER.
SET LOCAL lock_timeout = '30s';
SET LOCAL statement_timeout = '5min';
LOCK TABLE public.workspace_engine_settings IN ACCESS EXCLUSIVE MODE;
LOCK TABLE public.agent_engine_runs IN SHARE MODE;
DO $codex_auth_mode_guard$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.workspace_engine_settings AS settings
     WHERE settings.default_engine_id = 'codex'
       AND (settings.default_auth_mode IS NULL
         OR settings.default_auth_mode NOT IN ('managed', 'api-key'))
  ) THEN
    RAISE EXCEPTION 'Codex auth-mode migration refused: unsupported source mode; obtain an explicit owner choice before retrying'
      USING ERRCODE = '22023';
  END IF;
END
$codex_auth_mode_guard$;
DO $codex_auth_mode_tie_guard$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM public.agent_engine_runs AS r
      JOIN public.workspace_engine_settings AS s ON s.workspace_id = r.workspace_id
     WHERE s.default_engine_id IS DISTINCT FROM 'codex'
       AND r.execution_kind = 'conversation'
       AND r.engine_id = 'codex'
       AND r.auth_mode IN ('managed', 'api-key')
       AND r.created_at = (
         SELECT max(latest.created_at)
           FROM public.agent_engine_runs AS latest
          WHERE latest.workspace_id = r.workspace_id
            AND latest.execution_kind = 'conversation'
            AND latest.engine_id = 'codex'
            AND latest.auth_mode IN ('managed', 'api-key')
       )
     GROUP BY r.workspace_id
    HAVING count(DISTINCT r.auth_mode) > 1
  ) THEN
    RAISE EXCEPTION 'Codex auth-mode migration refused: conflicting latest run timestamps; resolve ambiguous workspace state before retrying'
      USING ERRCODE = '22023';
  END IF;
END
$codex_auth_mode_tie_guard$;
