-- 045_attachments_storage_rls.sql
-- PR-D scope (#3244 §4): close cross-tenant attachment read vector by adding
-- the INSERT/UPDATE/DELETE Storage policies that migration 019 left out, plus
-- the missing message_attachments INSERT policy.
--
-- Migration 019 created the chat-attachments bucket + the storage.objects
-- SELECT policy and the message_attachments SELECT policy, but no INSERT/
-- UPDATE/DELETE policies. Pre-PR-D, persistAndDownloadAttachments() was
-- service-role at the application layer, so the missing write policies
-- never surfaced. PR-D's call-site swap to tenant client makes these
-- policies load-bearing for both write paths and read paths.
--
-- Refs: #3244 (umbrella), #3854 (PR-C), #3869 items 4-5.
--
-- Design notes:
--
--   * Storage.objects policy uses FOR ALL with USING and NO WITH CHECK.
--     Per 2026-04-18-rls-for-all-using-applies-to-writes.md: when WITH
--     CHECK is omitted, the USING expression also applies to INSERT/
--     UPDATE row-being-written. Adding `WITH CHECK (true)` here would
--     silently disable tenant isolation on writes — DO NOT add one in
--     a future migration without re-reading that learning.
--
--   * message_attachments policy joins through messages →
--     conversations.user_id. DELETE handled by FK ON DELETE CASCADE
--     from messages → conversations, so no explicit DELETE policy is
--     defined here (brainstorm Open Question §3 provisional decision —
--     follow-up issue if un-attach UX is requested).
--
--   * RLS evaluates after table-level GRANT. The `authenticated` role
--     already holds INSERT/UPDATE/DELETE on storage.objects (granted by
--     supabase-storage extension defaults) and message_attachments
--     (granted by supabase's anon/authenticated role bootstrap). Phase
--     0.4b GRANT presence check confirms this at apply time.

-- 1. storage.objects FOR ALL policy — INSERT/UPDATE/DELETE for chat-attachments
--    bucket scoped to the caller's user-folder prefix. SELECT policy with the
--    same predicate already exists from migration 019.
CREATE POLICY "Users can write own attachment objects"
  ON storage.objects FOR ALL
  USING (
    bucket_id = 'chat-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- 2. message_attachments INSERT policy. SELECT policy already exists from
--    migration 019 with the same join shape.
CREATE POLICY "Users can insert own message attachments"
  ON public.message_attachments FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.messages m
      JOIN public.conversations c ON c.id = m.conversation_id
      WHERE m.id = message_attachments.message_id
        AND c.user_id = auth.uid()
    )
  );
