-- Reverts 164: drop the six RPCs, then the two tables. REFUSES while the ledger holds rows:
-- dropping a populated ledger discards the only durable record of owed Art. 17 erasures.
DO $$
BEGIN
  IF to_regclass('public.git_data_erasure_pending') IS NOT NULL
     AND EXISTS (SELECT 1 FROM public.git_data_erasure_pending) THEN
    RAISE EXCEPTION 'Refusing to drop git_data_erasure_pending: it holds pending erasures. Resolve or export them first.';
  END IF;
END $$;

DROP FUNCTION IF EXISTS public.git_data_erasure_pending_ages();
DROP FUNCTION IF EXISTS public.git_data_erasure_owner_gone(uuid);
DROP FUNCTION IF EXISTS public.oldest_git_data_erasure_pending_age();
DROP FUNCTION IF EXISTS public.resolve_git_data_erasure_pending(uuid);
DROP FUNCTION IF EXISTS public.claim_git_data_erasure_pending(int, interval);
DROP FUNCTION IF EXISTS public.record_git_data_erasure_pending(uuid, text, timestamptz);
DROP INDEX IF EXISTS public.git_data_erasure_pending_requested_at_idx;
DROP TABLE IF EXISTS public.git_data_erasure_counts;
DROP TABLE IF EXISTS public.git_data_erasure_pending;
