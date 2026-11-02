-- Reverse 179_delete_oauth_credential.sql.
-- No schema change to reverse: the migration only adds the function.

DROP FUNCTION IF EXISTS public.delete_oauth_credential(uuid);
