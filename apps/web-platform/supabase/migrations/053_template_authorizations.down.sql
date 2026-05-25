-- 053_template_authorizations.down.sql
-- Reverse of 053_template_authorizations.sql.
-- DROP order per plan §Sharp Edges (reverse of CREATE):
--   1. Triggers
--   2. Trigger function
--   3. RPCs (anonymise → revoke → authorize)
--   4. Table (template_authorizations) — cascades indexes + policies
--   5. ALTER messages DROP CONSTRAINT messages_template_id_check
--   6. ALTER messages DROP COLUMN template_id
--
-- No outer BEGIN/COMMIT (Supabase runner wraps).

-- (1) Triggers
DROP TRIGGER IF EXISTS template_authorizations_no_delete ON public.template_authorizations;
DROP TRIGGER IF EXISTS template_authorizations_no_update ON public.template_authorizations;

-- (2) Trigger function
DROP FUNCTION IF EXISTS public.template_authorizations_no_mutate();

-- (3) RPCs
DROP FUNCTION IF EXISTS public.anonymise_template_authorizations(uuid);
DROP FUNCTION IF EXISTS public.revoke_template_authorization(text, text);
DROP FUNCTION IF EXISTS public.authorize_template(text, text, uuid);

-- (4) Table — cascades the partial-UNIQUE + revoked_idx + RLS policies.
DROP TABLE IF EXISTS public.template_authorizations;

-- (5) messages CHECK
ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_template_id_check;

-- (6) messages.template_id column
ALTER TABLE public.messages
  DROP COLUMN IF EXISTS template_id;
