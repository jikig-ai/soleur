BEGIN;
SET LOCAL lock_timeout = '30s';
SET LOCAL statement_timeout = '5min';

-- Restore the 149 RPC contract. Acknowledgments deleted by the forward
-- migration cannot be reconstructed and remain deleted.
CREATE OR REPLACE FUNCTION public.record_codex_history_transfer_acknowledgment(
  p_conversation_id uuid,
  p_auth_mode_generation bigint
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_member_user_id uuid := auth.uid();
  v_workspace_id uuid;
  v_membership_created_at timestamptz;
BEGIN
  IF v_member_user_id IS NULL OR p_auth_mode_generation IS NULL OR p_auth_mode_generation <= 0 THEN
    RETURN false;
  END IF;

  SELECT r.workspace_id INTO v_workspace_id
    FROM public.agent_engine_runs AS r
    JOIN public.conversations AS c
      ON c.id = r.conversation_id
     AND c.workspace_id = r.workspace_id
   WHERE r.conversation_id = p_conversation_id
     AND r.execution_kind = 'conversation'
     AND r.engine_id = 'codex'
     AND r.auth_mode_generation = p_auth_mode_generation
   FOR UPDATE OF r;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  SELECT m.created_at INTO v_membership_created_at
    FROM public.workspace_members AS m
   WHERE m.workspace_id = v_workspace_id
     AND m.user_id = v_member_user_id
   FOR UPDATE OF m;
  IF NOT FOUND OR NOT public.is_workspace_member(v_workspace_id, v_member_user_id) THEN
    RETURN false;
  END IF;

  INSERT INTO public.codex_history_transfer_acknowledgments (
    conversation_id, member_user_id, auth_mode_generation, workspace_member_created_at
  ) VALUES (
    p_conversation_id, v_member_user_id, p_auth_mode_generation, v_membership_created_at
  )
  ON CONFLICT (
    conversation_id, member_user_id, auth_mode_generation, workspace_member_created_at
  ) DO NOTHING;

  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.codex_history_transfer_acknowledged(
  p_conversation_id uuid,
  p_auth_mode_generation bigint
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_member_user_id uuid := auth.uid();
BEGIN
  IF v_member_user_id IS NULL OR p_auth_mode_generation IS NULL OR p_auth_mode_generation <= 0 THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
      FROM public.agent_engine_runs AS r
      JOIN public.conversations AS c
        ON c.id = r.conversation_id
       AND c.workspace_id = r.workspace_id
      JOIN public.workspace_members AS m
        ON m.workspace_id = r.workspace_id
       AND m.user_id = v_member_user_id
      JOIN public.codex_history_transfer_acknowledgments AS a
        ON a.conversation_id = r.conversation_id
       AND a.member_user_id = m.user_id
       AND a.workspace_member_created_at = m.created_at
       AND a.auth_mode_generation = r.auth_mode_generation
     WHERE r.conversation_id = p_conversation_id
       AND r.execution_kind = 'conversation'
       AND r.engine_id = 'codex'
       AND r.auth_mode_generation = p_auth_mode_generation
       AND public.is_workspace_member(r.workspace_id, v_member_user_id)
  );
END;
$$;

COMMIT;
