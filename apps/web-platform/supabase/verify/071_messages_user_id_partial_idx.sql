-- Verify 071_messages_user_id_partial_idx.sql.
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row
-- fails CI verify-migrations.
--
-- Sentinels confirm post-apply state from migration 071:
--   * idx_messages_user_id exists on public.messages
--   * idx_messages_user_id is a partial index (has a WHERE predicate)

-- (1) idx_messages_user_id exists
SELECT 'idx_messages_user_id_exists' AS check_name,
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_indexes
         WHERE schemaname = 'public'
           AND tablename = 'messages'
           AND indexname = 'idx_messages_user_id'
       ) THEN 0 ELSE 1 END::int AS bad
UNION ALL
-- (2) idx_messages_user_id is a partial index (has predicate)
SELECT 'idx_messages_user_id_is_partial',
       CASE WHEN EXISTS (
         SELECT 1 FROM pg_index i
         JOIN pg_class c ON c.oid = i.indexrelid
         WHERE c.relname = 'idx_messages_user_id'
           AND i.indpred IS NOT NULL
       ) THEN 0 ELSE 1 END::int;
