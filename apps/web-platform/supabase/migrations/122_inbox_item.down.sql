-- 122_inbox_item.down.sql
-- Reversal of 122_inbox_item.sql — unschedule the retention cron, drop the RPC,
-- the indexes, the table (which drops the RLS policy with it), and the ledger
-- row. is_workspace_owner is SHARED (mig 098) and is NEVER dropped here.
-- A rollback is intentionally lossy (drops all inbox_item rows) — operational
-- ephemera, not statutory evidence.

-- 1. pg_cron retention sweep (mig 094/102 down shape; guard pg_cron-absent CI).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'inbox_item_retention') THEN
    PERFORM cron.unschedule('inbox_item_retention');
  END IF;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- 2. RPC.
DROP FUNCTION IF EXISTS public.set_inbox_item_state(uuid, text);

-- 3. Indexes (the table drop would cascade these; explicit per house style).
DROP INDEX IF EXISTS public.inbox_item_dedup_key_uniq;
DROP INDEX IF EXISTS public.inbox_item_workspace_created_idx;
DROP INDEX IF EXISTS public.inbox_item_created_idx;

-- 4. Table (drops the inbox_item_owner_select policy with it).
DROP TABLE IF EXISTS public.inbox_item;

-- 5. Ledger row. Required for re-apply — run-migrations.sh skips filenames
--    already present in public._schema_migrations.
DELETE FROM public._schema_migrations WHERE filename = '122_inbox_item.sql';
