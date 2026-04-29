-- 034_conversations_messages_realtime_publication.sql
-- Idempotently adds `conversations` and `messages` to the `supabase_realtime`
-- publication so Realtime `postgres_changes` subscriptions receive events on
-- those tables.
--
-- DISCOVERED: Phase 5b cross-tenant integration test (Phase 5b of plan
-- 2026-04-29-feat-command-center-conversation-nav-plan.md, the load-bearing
-- HARD MERGE GATE for the Command Center conversation rail) timed out on
-- `channel.subscribe` against the dev project. Diagnosis: the prd project
-- had `conversations` added to the publication via the Supabase dashboard
-- (manual config), but no migration ever replicated that to dev. This is a
-- dev/prd parity gap distinct from the rail PR's scope — closing it here
-- so any future Supabase project provisioned from the migration history
-- gets the publication membership automatically.
--
-- Tables added:
--   - public.conversations  (used by use-conversations.ts → command-center
--                            channel; cross-tenant isolation rests on
--                            postgres_changes broadcasts being filtered
--                            by user_id=eq + RLS).
--   - public.messages       (used by chat page Realtime stream for
--                            conversation message updates).
--
-- The pg_publication_tables existence check is the canonical idempotent
-- pattern for ALTER PUBLICATION — re-running this migration on a project
-- where the table is already a publication member is a no-op.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'conversations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;
END $$;
