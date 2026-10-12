-- Add context_path column to conversations for KB-document-scoped threads.
-- Each (user_id, context_path) pair points at one conversation; re-opening a
-- KB file resumes that thread. The UNIQUE partial index enforces this, and
-- combined with an ON CONFLICT path on insert, resolves the two-tab race
-- (second tab's insert sees the first tab's row instead of creating a dup).
--
-- Backfill is intentionally skipped: pre-migration KB threads remain
-- un-badged in the conversation inbox. Decision recorded in the parent
-- plan `knowledge-base/project/plans/2026-04-15-feat-kb-chat-sidebar-plan.md`
-- section 2.1 — a best-effort content_path derivation from the first user
-- message would have produced fragile results for a small historical
-- window, so the cost outweighs the display benefit (see AC18 of the
-- parent plan).
--
-- If a future operator needs to backfill, the pattern is:
--   UPDATE public.conversations
--      SET context_path = <derived-from-first-user-message>
--    WHERE created_at < '<cutoff>' AND context_path IS NULL;
-- Note that the partial UNIQUE index will reject duplicates — pre-compute
-- the (user_id, context_path) map and coalesce duplicates before UPDATE.
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS context_path text;

CREATE UNIQUE INDEX IF NOT EXISTS conversations_context_path_user_uniq
  ON public.conversations (user_id, context_path)
  WHERE context_path IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_conversations_context_path
  ON public.conversations (context_path)
  WHERE context_path IS NOT NULL;
