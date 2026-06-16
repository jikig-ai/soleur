-- 104_outbound_email.down.sql
-- Reverses 104_outbound_email.sql. Drop RPCs before the tables they reference.
-- No action_sends / scope_grants changes were made (those are reused unchanged),
-- so nothing to revert there.

-- outbound_sends (WORM audit) — triggers + RPCs before the table.
DROP FUNCTION IF EXISTS public.anonymise_outbound_sends(uuid);
DROP FUNCTION IF EXISTS public.record_outbound_send(text, text, text, text, text);
DROP FUNCTION IF EXISTS public.outbound_send_exists(text, text);
DROP TRIGGER IF EXISTS outbound_sends_no_delete ON public.outbound_sends;
DROP TRIGGER IF EXISTS outbound_sends_no_update ON public.outbound_sends;
DROP FUNCTION IF EXISTS public.outbound_sends_no_mutate();
DROP INDEX IF EXISTS public.outbound_sends_dedup_unique;
DROP INDEX IF EXISTS public.outbound_sends_owner_sent_idx;
DROP TABLE IF EXISTS public.outbound_sends;

-- email_suppression — RPCs before the table.
DROP FUNCTION IF EXISTS public.anonymise_email_suppression(uuid);
DROP FUNCTION IF EXISTS public.is_recipient_suppressed(text);
DROP FUNCTION IF EXISTS public.suppress_recipient(text, text);

DROP INDEX IF EXISTS public.email_suppression_owner_recipient_unique;
DROP TABLE IF EXISTS public.email_suppression;
