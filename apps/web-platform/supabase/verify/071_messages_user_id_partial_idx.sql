-- Verify sentinel: assert idx_messages_user_id exists and is partial.
-- CI runs this via verify-migrations job; failure blocks deploy.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'messages'
      AND indexname = 'idx_messages_user_id'
  ) THEN
    RAISE EXCEPTION 'idx_messages_user_id does not exist on public.messages';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_index i
    JOIN pg_class c ON c.oid = i.indexrelid
    WHERE c.relname = 'idx_messages_user_id'
      AND i.indpred IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'idx_messages_user_id exists but is not a partial index';
  END IF;
END $$;
