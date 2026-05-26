-- 039_drop_messages_from_realtime_publication.sql
--
-- Remove public.messages from the supabase_realtime publication added by
-- migration 034. The Realtime WAL parser is the dominant disk IO consumer
-- on prod (1.12M ms / 219K calls / 325M block hits in the captured window),
-- driven by ~10 polls/sec regardless of user activity.
--
-- Confirmed via repo grep that no production code subscribes to
-- public.messages via Realtime — all 16 hits across apps/web-platform are
-- in *test* files (mock builders). The only production Realtime consumer
-- is apps/web-platform/hooks/use-conversations.ts:238, which subscribes
-- to public.conversations (kept in the publication).
--
-- public.conversations remains in the publication. This migration only
-- narrows the WAL fan-out, not the live-update surface of the dashboard.
--
-- Rollback: re-add via `ALTER PUBLICATION supabase_realtime ADD TABLE
-- public.messages;` (idempotent guard pattern from migration 034).
--
-- See: knowledge-base/project/plans/2026-05-06-fix-supabase-disk-io-cron-realtime-plan.md
-- Issue: #3358

DO $$
BEGIN
  -- Idempotent guard: only act if messages is currently in the publication.
  IF EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.messages;
  END IF;
END $$;
