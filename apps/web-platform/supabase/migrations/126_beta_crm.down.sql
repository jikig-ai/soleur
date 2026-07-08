-- 126_beta_crm.down.sql — reverses 126_beta_crm.sql.
-- Order: unschedule cron -> drop functions -> drop tables CASCADE
-- (children CASCADE from beta_contacts; the updated_at trigger drops with it).

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'beta_contacts_retention') THEN
    PERFORM cron.unschedule('beta_contacts_retention');
  END IF;
EXCEPTION
  WHEN undefined_table THEN NULL;  -- pg_cron absent (local/CI)
END $cron_block$;

DROP FUNCTION IF EXISTS public.crm_erase_contact(uuid);
DROP FUNCTION IF EXISTS public.crm_contact_set_stage(uuid, text);
DROP FUNCTION IF EXISTS public.crm_note_append(uuid, text, text[], date);
DROP FUNCTION IF EXISTS public.crm_contact_upsert(uuid, text, text, text, text, text, text, date, date, numeric, text, text, date);
DROP FUNCTION IF EXISTS public.beta_contacts_set_updated_at();

DROP TABLE IF EXISTS public.beta_contact_stage_transitions CASCADE;
DROP TABLE IF EXISTS public.interview_notes CASCADE;
DROP TABLE IF EXISTS public.beta_contacts CASCADE;
