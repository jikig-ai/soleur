-- run-migrations.sh injects this before migration 145 in the SAME transaction
-- as its unchanged body and ledger insert. The table lock excludes both owner
-- RPCs and direct writes until the constrained backfill finishes. Do not run
-- this as a separate count query: that leaves a write window before the ALTER.
SET LOCAL lock_timeout = '30s';
SET LOCAL statement_timeout = '5min';
LOCK TABLE public.workspace_engine_settings IN ACCESS EXCLUSIVE MODE;
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
