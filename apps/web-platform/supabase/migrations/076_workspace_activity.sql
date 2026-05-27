-- 076_workspace_activity.sql
-- Closes #4521 PR-B: team activity feed — workspace_activity table.
--
-- Polling-based activity timeline per workspace. Events written by
-- SECURITY DEFINER RPC (service_role only). 90-day pg_cron retention purge.
-- actor_user_id NULLABLE + ON DELETE SET NULL for Art-17 cascade.
--
-- NOT added to supabase_realtime publication (per spec TR7, mig 039 precedent).

-- Precondition: workspaces table exists (mig 053).
DO $$ BEGIN
  IF to_regclass('public.workspaces') IS NULL THEN
    RAISE EXCEPTION 'public.workspaces does not exist — cannot apply 076';
  END IF;
END $$;

-- =====================================================================
-- 1. Create workspace_activity table
-- =====================================================================

CREATE TABLE public.workspace_activity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  event_type text NOT NULL,
  metadata jsonb DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.workspace_activity ENABLE ROW LEVEL SECURITY;

-- =====================================================================
-- 2. RLS policies
-- =====================================================================

-- Workspace members can SELECT activity for their workspace.
CREATE POLICY workspace_activity_member_select ON public.workspace_activity
  FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspace_id, auth.uid()));

-- JTI deny RESTRICTIVE policy (per mig 068 pattern — Kieran H1).
CREATE POLICY workspace_activity_jti_not_denied ON public.workspace_activity
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.is_jti_denied_from_jwt())
  WITH CHECK (NOT public.is_jti_denied_from_jwt());

-- =====================================================================
-- 3. SECURITY DEFINER writer RPC (service_role only)
-- =====================================================================
-- Per Kieran C2: all emitters are server-side, so GRANT to service_role only.
-- event_type validation in RPC body (no CHECK constraint — allows adding
-- types without migration per Simplicity S3a).

CREATE OR REPLACE FUNCTION public.record_workspace_activity(
  p_workspace_id uuid,
  p_actor_user_id uuid,
  p_event_type text,
  p_metadata jsonb DEFAULT '{}'
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_event_type NOT IN ('member_join', 'member_leave', 'conversation_shared') THEN
    RAISE EXCEPTION 'Unknown event_type: %', p_event_type
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO public.workspace_activity (workspace_id, actor_user_id, event_type, metadata)
  VALUES (p_workspace_id, p_actor_user_id, p_event_type, p_metadata);
END;
$$;

REVOKE ALL ON FUNCTION public.record_workspace_activity(uuid, uuid, text, jsonb)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_workspace_activity(uuid, uuid, text, jsonb)
  TO service_role;

-- =====================================================================
-- 4. Indexes
-- =====================================================================

CREATE INDEX workspace_activity_feed_idx
  ON public.workspace_activity (workspace_id, created_at DESC);

CREATE INDEX workspace_activity_actor_idx
  ON public.workspace_activity (actor_user_id);

-- =====================================================================
-- 5. pg_cron 90-day retention purge (idempotent per Kieran H3)
-- =====================================================================

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'workspace_activity_purge') THEN
    PERFORM cron.unschedule('workspace_activity_purge');
  END IF;
  PERFORM cron.schedule(
    'workspace_activity_purge',
    '0 3 * * *',
    $$DELETE FROM public.workspace_activity WHERE created_at < now() - interval '90 days'$$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- =====================================================================
-- 6. Art-17 anonymisation RPC (follows mig 063 pattern)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.anonymise_workspace_activity(
  p_user_id uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.workspace_activity
     SET actor_user_id = NULL,
         metadata = '{}'
   WHERE actor_user_id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_workspace_activity(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.anonymise_workspace_activity(uuid)
  TO service_role;

-- =====================================================================
-- 7. Update set_conversation_visibility to emit conversation_shared event
-- =====================================================================
-- SECURITY DEFINER runs as function owner — can INSERT into workspace_activity.

CREATE OR REPLACE FUNCTION public.set_conversation_visibility(
  p_conversation_id uuid,
  p_visibility text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_workspace_id uuid;
BEGIN
  IF p_visibility NOT IN ('private', 'workspace') THEN
    RAISE EXCEPTION 'Invalid visibility value: %', p_visibility
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.conversations
     SET visibility = p_visibility
   WHERE id = p_conversation_id
     AND user_id = auth.uid()
  RETURNING workspace_id INTO v_workspace_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conversation not found or not owned by caller'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_visibility = 'workspace' AND v_workspace_id IS NOT NULL THEN
    INSERT INTO public.workspace_activity (workspace_id, actor_user_id, event_type, metadata)
    VALUES (v_workspace_id, auth.uid(), 'conversation_shared', jsonb_build_object('conversation_id', p_conversation_id));
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_conversation_visibility(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_conversation_visibility(uuid, text)
  TO authenticated;
