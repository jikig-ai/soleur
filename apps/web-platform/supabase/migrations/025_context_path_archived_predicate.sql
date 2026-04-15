-- Fix the UNIQUE partial index on conversations.context_path so its
-- predicate matches how the KB-sidebar lookup + 23505 fallback in
-- server/ws-handler.ts filter rows.
--
-- Before: WHERE context_path IS NOT NULL
-- After:  WHERE context_path IS NOT NULL AND archived_at IS NULL
--
-- Why: the handler's resume-by-context_path lookup filters
-- `archived_at IS NULL`, but the index's WHERE clause did not.
-- Consequence: if a user archived a KB conversation, the archived row
-- still occupied the unique slot. Next time they opened the same KB doc:
--   1. createConversation INSERT -> 23505 unique_violation
--   2. fallback lookup filters archived_at IS NULL -> 0 rows
--   3. throws "Failed to resolve existing context_path conversation"
-- The path was permanently bricked for that user.
--
-- Making the index predicate match the lookup filter lets a new
-- conversation take the slot when the old one is archived. See review
-- finding #2382.
--
-- CONCURRENTLY is not used here because Supabase's migration runner
-- executes inside a transaction block; production operators should run
-- this via psql with a manual CONCURRENTLY pass if downtime windows
-- require it. For the current single-instance Hetzner deploy, the
-- in-transaction form is acceptable and atomic.

DROP INDEX IF EXISTS public.conversations_context_path_user_uniq;

CREATE UNIQUE INDEX conversations_context_path_user_uniq
  ON public.conversations (user_id, context_path)
  WHERE context_path IS NOT NULL AND archived_at IS NULL;
