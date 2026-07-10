-- 128_conversations_kind_support.down.sql
-- Reverts 128_conversations_kind_support.sql.
-- NOTE: dropping the column discards any 'support' discriminator on existing
-- support conversations; those rows remain but become indistinguishable from
-- command_center rows (they keep repo_url = NULL, so the CC rail still hides
-- them). Safe to re-apply the up migration afterward (DEFAULT re-stamps).

DROP INDEX IF EXISTS public.idx_conversations_user_support;

ALTER TABLE public.conversations
  DROP CONSTRAINT IF EXISTS conversations_kind_check;

ALTER TABLE public.conversations
  DROP COLUMN IF EXISTS kind;
