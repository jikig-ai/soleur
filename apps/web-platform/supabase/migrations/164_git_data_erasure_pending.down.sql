-- Reverts 164: drop the four RPCs, then the two tables (the ledger is empty before B2 ships;
-- dropping a populated ledger discards the only durable record of owed erasures).
DROP FUNCTION IF EXISTS public.oldest_git_data_erasure_pending_age();
DROP FUNCTION IF EXISTS public.resolve_git_data_erasure_pending(uuid);
DROP FUNCTION IF EXISTS public.claim_git_data_erasure_pending(int, interval);
DROP FUNCTION IF EXISTS public.record_git_data_erasure_pending(uuid, text);
DROP INDEX IF EXISTS public.git_data_erasure_pending_requested_at_idx;
DROP TABLE IF EXISTS public.git_data_erasure_counts;
DROP TABLE IF EXISTS public.git_data_erasure_pending;
