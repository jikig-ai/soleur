-- Partial index on messages(user_id) for the active (non-anonymised) row set.
-- Covers: dsar-export participation probe, account-delete cascade RPC,
-- mig 068 anonymise_departed_user_across_workspaces.
-- Partial WHERE keeps the index compact: post-cascade rows (user_id IS NULL)
-- are excluded since no query path filters on a NULL user_id.
--
-- Ref: #4453 (PR #4417 review P1 — performance-oracle finding)

CREATE INDEX IF NOT EXISTS idx_messages_user_id
  ON public.messages (user_id)
  WHERE user_id IS NOT NULL;

COMMENT ON INDEX public.idx_messages_user_id IS
  'Partial index covering non-anonymised messages for user-scoped queries '
  '(DSAR participation probe, account-delete cascade, storage purge). '
  'Ref: #4453.';
