-- 102_email_triage_items.down.sql
-- Reversal of 102_email_triage_items.sql — unschedule the dedup retention
-- cron, drop the WORM triggers + trigger function, the three RPCs, the
-- partial index, and the three tables. Dropping email_triage_items is the
-- ONLY path that destroys triage rows (the WORM trigger goes with it) — a
-- rollback is intentionally lossy, mirroring 094's "retention is lossy by
-- design" stance.

-- 1. pg_cron retention sweep (mig 094 down-file shape).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'processed_resend_events_retention') THEN
    PERFORM cron.unschedule('processed_resend_events_retention');
  END IF;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- 2. WORM triggers + trigger function.
DROP TRIGGER IF EXISTS email_triage_items_no_update ON public.email_triage_items;
DROP TRIGGER IF EXISTS email_triage_items_no_delete ON public.email_triage_items;
DROP FUNCTION IF EXISTS public.email_triage_items_no_mutate();

-- 3. RPCs.
DROP FUNCTION IF EXISTS public.set_email_triage_status(uuid, text);
DROP FUNCTION IF EXISTS public.purge_email_triage_items();
DROP FUNCTION IF EXISTS public.anonymise_email_triage_items(uuid);

-- 4. Indexes (table drops would cascade these; explicit per house style).
DROP INDEX IF EXISTS public.email_triage_items_user_received_idx;
DROP INDEX IF EXISTS public.email_triage_items_llm_ceiling_idx;
DROP INDEX IF EXISTS public.email_triage_items_archived_idx;
DROP INDEX IF EXISTS public.processed_resend_events_received_at_idx;

-- 5. Tables.
DROP TABLE IF EXISTS public.email_triage_items;
DROP TABLE IF EXISTS public.processed_resend_events;
DROP TABLE IF EXISTS public.probe_tokens;

-- 6. Ledger row. Required for re-apply: run-migrations.sh skips filenames
--    already present in public._schema_migrations, and the verify sentinels
--    key off the ledger — leaving the row would make 102 unreapplyable after
--    a rollback.
DELETE FROM public._schema_migrations WHERE filename = '102_email_triage_items.sql';
