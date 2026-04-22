-- 029_conversations_repo_url.sql
-- Scope conversations to the repository they were created against.
-- Fixes: command center + KB-context-path lookup leaking pre-disconnect
-- conversations into a freshly-connected repo (see plan
-- 2026-04-22-fix-command-center-stale-conversations-after-repo-swap-plan.md).
--
-- Nullable on purpose: pre-migration rows are backfilled with the user's
-- CURRENT repo_url. If the user had already disconnected before this
-- migration ran, users.repo_url is NULL and conversations.repo_url stays
-- NULL -- those rows will be hidden by the new query filter (desired --
-- matches disconnect semantics).
--
-- NOT using CONCURRENTLY: Supabase migration runner wraps each file in a
-- transaction (see migrations 025, 027 comments). Column add + index are
-- transaction-safe. If the table grows to a size where an index rebuild
-- becomes disruptive, ship a second migration via direct psql.

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS repo_url text;

-- Backfill pre-migration rows with the user's current repo_url.
-- For disconnected users (repo_url IS NULL), conversations.repo_url stays NULL.
UPDATE public.conversations c
   SET repo_url = u.repo_url
  FROM public.users u
 WHERE c.user_id = u.id
   AND c.repo_url IS NULL;

-- Partial index -- only populated rows are indexed (disconnected-user
-- conversations don't need index coverage; they're never queried).
CREATE INDEX IF NOT EXISTS idx_conversations_user_repo
  ON public.conversations (user_id, repo_url)
  WHERE repo_url IS NOT NULL;

-- Update the existing context_path UNIQUE index to include repo_url so
-- the same KB file path in two repos no longer collides. This drops and
-- recreates the index (established pattern -- see migration 025).
DROP INDEX IF EXISTS public.conversations_context_path_user_uniq;

CREATE UNIQUE INDEX conversations_context_path_user_uniq
  ON public.conversations (user_id, repo_url, context_path)
  WHERE context_path IS NOT NULL AND archived_at IS NULL;
