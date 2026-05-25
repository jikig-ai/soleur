-- 070_action_sends_realtime_publication.down.sql (#4379 PR-B)
--
-- Symmetric idempotent drop. Reverting this migration disables Realtime
-- delivery for action_sends UPDATEs; LeaderLoopStatus falls through to the
-- 2s poll fallback (FR3) on every spawn — degraded UX but not broken.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'action_sends'
  ) THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.action_sends;
  END IF;
END $$;
