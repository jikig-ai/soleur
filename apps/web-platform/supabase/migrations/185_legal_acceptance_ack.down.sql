-- 185_legal_acceptance_ack.down.sql
-- NOT A HOT ROLLBACK, and it refuses to run while any acknowledgement exists: dropping the table would make every
-- acknowledged decision look unreported (a false `row_without_event` for each) once the migration is re-applied. It exists
-- for the DEV reset of an unmerged edit of 185 (the table is empty there) and for a full revert of the feature. The
-- production rollback is to keep the schema; the endpoint's emitter is alert-only and never gates anything.
-- It touches nothing of migration 184.
-- It runs as ONE transaction (BEGIN ... COMMIT below): the ACCESS EXCLUSIVE lock taken by the check is held until the
-- COMMIT, i.e. through the DROPs, so no acknowledgement can be inserted between the check and the drop. Outside a
-- transaction the lock would be released when the DO block ends. (The migration runner never runs down files; this is
-- applied by hand.)
-- APPLY WITH: psql -v ON_ERROR_STOP=1 -f 185_legal_acceptance_ack.down.sql -- so a guard refusal exits nonzero and
-- nothing changes. Pasting the statements one at a time leaves the lock held, and the transaction open, until ROLLBACK.

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.legal_acceptance_ack') IS NOT NULL THEN
    -- Lock first: a row inserted between the check and the drop would otherwise be destroyed.
    LOCK TABLE public.legal_acceptance_ack IN ACCESS EXCLUSIVE MODE;
    IF EXISTS (SELECT 1 FROM public.legal_acceptance_ack) THEN
      RAISE EXCEPTION '185 down refused: public.legal_acceptance_ack holds acknowledgements; archive them first';
    END IF;
  END IF;
END $$;

DROP FUNCTION IF EXISTS public.legal_acceptance_ack_state(uuid, text, text);
DROP FUNCTION IF EXISTS public.ack_legal_acceptance(uuid, text, text);
DROP TABLE IF EXISTS public.legal_acceptance_ack;

COMMIT;
