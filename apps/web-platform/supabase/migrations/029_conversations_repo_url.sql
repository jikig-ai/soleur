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

COMMENT ON COLUMN public.conversations.repo_url IS
  'Snapshot of users.repo_url at conversation create time (free-text, '
  'not a FK). Readers scope by (user_id, repo_url) to hide conversations '
  'whose owning repo is no longer connected. Coupling invariant: any '
  'future normalization of users.repo_url MUST also rewrite this column '
  'in the same migration, or previously-connected conversations go dark.';

-- Backfill pre-migration rows with the user's current repo_url.
-- Caveats:
--   1. Users currently disconnected (users.repo_url IS NULL) leave their
--      conversations at repo_url = NULL — hidden from the Command Center
--      until they reconnect. Marked archived below so they remain
--      discoverable via the Archived filter.
--   2. Users who already swapped repos before this migration cannot have
--      historical rows recovered — we have no audit of past repo_url
--      values. Those rows get stamped with the user's CURRENT repo_url
--      (the known limitation documented in the plan). A future improvement
--      could ship a per-user "tag all pre-migration rows as archived"
--      batch if this becomes a complaint.
UPDATE public.conversations c
   SET repo_url = u.repo_url
  FROM public.users u
 WHERE c.user_id = u.id
   AND c.repo_url IS NULL;

-- Caveat 1 (see above): archive pre-migration rows whose user is
-- currently disconnected so the Archived filter can still surface them.
-- Uses COALESCE so rows already archived keep their original timestamp.
UPDATE public.conversations c
   SET archived_at = COALESCE(c.archived_at, NOW())
  FROM public.users u
 WHERE c.user_id = u.id
   AND u.repo_url IS NULL
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
