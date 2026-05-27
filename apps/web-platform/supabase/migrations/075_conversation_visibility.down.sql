-- 075_conversation_visibility.down.sql

DROP INDEX IF EXISTS conversations_visibility_workspace_idx;

DROP FUNCTION IF EXISTS public.set_conversation_visibility(uuid, text);

DROP POLICY IF EXISTS conversations_owner_or_shared ON public.conversations;

-- Restore the original workspace-wide policy from mig 059.
CREATE POLICY conversations_workspace_member_all ON public.conversations
  FOR ALL TO authenticated
  USING (public.is_workspace_member(workspace_id, auth.uid()))
  WITH CHECK (public.is_workspace_member(workspace_id, auth.uid()));

-- Restore UPDATE grant on visibility column before dropping it.
GRANT UPDATE(visibility) ON public.conversations TO authenticated;

ALTER TABLE public.conversations DROP COLUMN IF EXISTS visibility;
