-- 104_outbound_email.down.sql
-- Reverses 104_outbound_email.sql. Drop RPCs before the table they reference.
-- No action_sends / scope_grants changes were made (outbound reuses them
-- unchanged), so nothing to revert there.

DROP FUNCTION IF EXISTS public.anonymise_email_suppression(uuid);
DROP FUNCTION IF EXISTS public.is_recipient_suppressed(text);
DROP FUNCTION IF EXISTS public.suppress_recipient(text, text);

DROP INDEX IF EXISTS public.email_suppression_owner_recipient_unique;
DROP TABLE IF EXISTS public.email_suppression;
