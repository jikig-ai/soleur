-- 184_legal_acceptance.down.sql
-- NOT A HOT ROLLBACK, and it refuses to run while any decision exists: the table is a write-once record and this file
-- must never be the way a record is destroyed. It exists for the DEV reset of an unmerged edit of 184 (the table is
-- empty there) and for a full revert of the feature after the application code is gone and counsel has agreed the
-- retained rows may be archived and dropped. The production rollback is to keep the schema and leave the flag off.

DO $$ BEGIN
  IF to_regclass('public.legal_acceptance') IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.legal_acceptance) THEN
      RAISE EXCEPTION '184 down refused: public.legal_acceptance holds decision rows (write-once record); archive them under counsel review first';
    END IF;
  END IF;
END $$;

DROP FUNCTION IF EXISTS public.verify_legal_acceptance(uuid, text, text);
DROP FUNCTION IF EXISTS public.record_legal_acceptance(text, text, text, text, text);
DROP FUNCTION IF EXISTS public.mark_legal_reauth_verified(uuid, text, text, text);
DROP FUNCTION IF EXISTS public.claim_legal_reauth_attempt(uuid, text, text, text);
DROP FUNCTION IF EXISTS public.issue_legal_reauth(uuid, text, text, text);

-- The checksum function takes the table's row type, so it goes before the table; the trigger function goes after
-- the table (the triggers drop with it).
DROP FUNCTION IF EXISTS public.legal_acceptance_row_hash(public.legal_acceptance);
DROP TABLE IF EXISTS public.legal_reauth_event;
DROP TABLE IF EXISTS public.legal_acceptance;
DROP FUNCTION IF EXISTS public.legal_acceptance_guard();
