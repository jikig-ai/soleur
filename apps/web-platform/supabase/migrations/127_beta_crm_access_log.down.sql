-- 127_beta_crm_access_log.down.sql
-- Reverse of 127_beta_crm_access_log.sql (feat-beta-crm-ui #6172).
-- Drops the read-audit RPC + the append-only access-log table. The table CASCADE
-- also removes its RLS policies and indexes. mig-126 (beta_contacts et al.) is
-- untouched.

DROP FUNCTION IF EXISTS public.crm_get_contact_detail(uuid);

DROP TABLE IF EXISTS public.beta_contact_access_log CASCADE;
