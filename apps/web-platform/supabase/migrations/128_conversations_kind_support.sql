-- 128_conversations_kind_support.sql
-- feat-wire-concierge-support-chat (Phase 2, ADR-109): B2 persisted repo-less
-- support conversations.
--
-- The 24/7 support chat routes through the same Concierge dispatch
-- (dispatchSoleurGo), which hard-requires a persisted `conversations` row
-- (ownership probe, workspace_id read, messages FK). Support users are frequently
-- repo-less, so support rows carry repo_url = NULL (the column is already nullable
-- per migration 029). This `kind` discriminator keeps support rows OUT of the
-- Command Center conversation rail and out of normal/DSAR conversation queries
-- WITHOUT a sentinel context_path (which every repo-scoped reader would assume is
-- repo-backed). CTO-decided B2 over B1 (ephemeral) — lower dispatch surgery and it
-- resolves the reconnect-replay cliff (the row exists, so replay works).
--
-- NOT using CONCURRENTLY: the Supabase migration runner wraps each file in a
-- transaction (see 029/025/027). Column add + partial index are transaction-safe.
--
-- RLS: unchanged. `conversations` RLS already scopes every row to
-- (user_id = auth.uid()) / workspace membership; a support row is owned by the
-- support user exactly like a Command Center row, so no policy change is needed.
-- The `kind` column is a read-side discriminator, not a new tenant boundary.

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'command_center';

-- Constrain to the known kinds so a typo'd writer fails loud rather than
-- silently creating an un-routable row. 'command_center' = the default
-- Concierge/Command-Center conversation (all pre-migration rows via DEFAULT);
-- 'support' = a repo-less in-app support-chat conversation.
ALTER TABLE public.conversations
  DROP CONSTRAINT IF EXISTS conversations_kind_check;
ALTER TABLE public.conversations
  ADD CONSTRAINT conversations_kind_check
  CHECK (kind IN ('command_center', 'support'));

COMMENT ON COLUMN public.conversations.kind IS
  'Conversation kind discriminator (feat-wire-concierge-support-chat / ADR-109). '
  '''command_center'' (default) = the repo-scoped Concierge/Command-Center '
  'conversation. ''support'' = a repo-less in-app support-chat conversation '
  '(repo_url NULL). Readers that enumerate Command-Center conversations MUST '
  'filter kind = ''command_center'' (or repo_url = <connected>, which already '
  'excludes NULL-repo_url support rows). Keep support rows out of DSAR/normal '
  'conversation exports unless a support-specific export is intended.';

-- Support-conversation lookup index (resolve-or-create the user's support
-- conversation on panel open). Partial — only support rows are indexed.
CREATE INDEX IF NOT EXISTS idx_conversations_user_support
  ON public.conversations (user_id, last_active DESC)
  WHERE kind = 'support';
