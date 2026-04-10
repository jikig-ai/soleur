-- Add kb_sync_history JSONB column to track knowledge-base file counts over time.
-- Stores an array of {date, count} objects, trimmed to 14 entries by application code.
-- Used by the admin analytics dashboard for KB growth sparklines.
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS kb_sync_history jsonb NOT NULL DEFAULT '[]';

-- Defense-in-depth: prevent client-side updates to kb_sync_history.
-- Primary protection: migration 006 restricts the authenticated role's UPDATE
-- privilege to only the email column. This RESTRICTIVE policy is belt-and-suspenders
-- in case column-level grants are later broadened.
-- Only the service role (used by session-sync after syncPush) should write this column.
CREATE POLICY "Users cannot update kb_sync_history directly"
  ON public.users
  AS RESTRICTIVE
  FOR UPDATE
  USING (true)
  WITH CHECK (
    kb_sync_history IS NOT DISTINCT FROM (SELECT kb_sync_history FROM public.users WHERE id = auth.uid())
  );
