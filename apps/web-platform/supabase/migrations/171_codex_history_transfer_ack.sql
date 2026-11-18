BEGIN;
SET LOCAL lock_timeout = '30s';
SET LOCAL statement_timeout = '5min';

DO $$ BEGIN
  IF to_regclass('public.conversations') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.conversations must exist before 149';
  END IF;
  IF to_regclass('public.users') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.users must exist before 149';
  END IF;
END $$;

-- This ledger stores only that a member acknowledged a provider-account
-- change for a conversation generation. It contains no transcript or prompt.
-- LAWFUL_BASIS: provisional Art. 6(1)(b) candidate — records the explicit step required to perform a member-requested provider switch; validate with CLO before qualification.
-- RETENTION: only the current generation and active workspace-membership epoch are retained; purge on either change, account erasure, or conversation deletion.
CREATE TABLE public.codex_history_transfer_acknowledgments (
  conversation_id uuid NOT NULL
    REFERENCES public.conversations(id) ON DELETE CASCADE,
  member_user_id uuid NOT NULL
    REFERENCES public.users(id) ON DELETE CASCADE,
  auth_mode_generation bigint NOT NULL CHECK (auth_mode_generation > 0),
  workspace_member_created_at timestamptz NOT NULL,
  acknowledged_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (
    conversation_id,
    member_user_id,
    auth_mode_generation,
    workspace_member_created_at
  )
);

CREATE INDEX codex_history_transfer_acknowledgments_member_idx
  ON public.codex_history_transfer_acknowledgments (member_user_id);

ALTER TABLE public.codex_history_transfer_acknowledgments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.codex_history_transfer_acknowledgments FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.codex_history_transfer_acknowledgments TO service_role;

CREATE FUNCTION public.purge_stale_codex_history_transfer_acknowledgments()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  DELETE FROM public.codex_history_transfer_acknowledgments AS a
   WHERE a.conversation_id = NEW.conversation_id
     AND a.auth_mode_generation <> NEW.auth_mode_generation;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_stale_codex_history_transfer_acknowledgments() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER agent_engine_runs_purge_stale_codex_history_ack
AFTER UPDATE OF auth_mode_generation ON public.agent_engine_runs
FOR EACH ROW
WHEN (OLD.auth_mode_generation IS DISTINCT FROM NEW.auth_mode_generation)
EXECUTE FUNCTION public.purge_stale_codex_history_transfer_acknowledgments();

CREATE FUNCTION public.purge_codex_history_transfer_acknowledgments_on_member_change()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  DELETE FROM public.codex_history_transfer_acknowledgments AS a
   USING public.agent_engine_runs AS r
   WHERE r.workspace_id = OLD.workspace_id
     AND r.conversation_id = a.conversation_id
     AND a.member_user_id = OLD.user_id;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_codex_history_transfer_acknowledgments_on_member_change() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER workspace_members_purge_codex_history_ack_on_delete
AFTER DELETE ON public.workspace_members
FOR EACH ROW
EXECUTE FUNCTION public.purge_codex_history_transfer_acknowledgments_on_member_change();

CREATE TRIGGER workspace_members_purge_codex_history_ack_on_update
AFTER UPDATE OF workspace_id, user_id, created_at ON public.workspace_members
FOR EACH ROW
WHEN (
  OLD.workspace_id IS DISTINCT FROM NEW.workspace_id
  OR OLD.user_id IS DISTINCT FROM NEW.user_id
  OR OLD.created_at IS DISTINCT FROM NEW.created_at
)
EXECUTE FUNCTION public.purge_codex_history_transfer_acknowledgments_on_member_change();

CREATE FUNCTION public.record_codex_history_transfer_acknowledgment(
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

  -- Lock the current binding against an owner mode-switch while the member's
  -- acknowledgment is recorded. A later switch increments the generation and
  -- makes this acknowledgment inapplicable to the new provider account.
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
    conversation_id,
    member_user_id,
    auth_mode_generation,
    workspace_member_created_at
  ) VALUES (
    p_conversation_id,
    v_member_user_id,
    p_auth_mode_generation,
    v_membership_created_at
  )
  ON CONFLICT (
    conversation_id,
    member_user_id,
    auth_mode_generation,
    workspace_member_created_at
  ) DO NOTHING;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.record_codex_history_transfer_acknowledgment(uuid, bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_codex_history_transfer_acknowledgment(uuid, bigint) FROM anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_codex_history_transfer_acknowledgment(uuid, bigint) TO authenticated;

CREATE FUNCTION public.codex_history_transfer_acknowledged(
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

REVOKE ALL ON FUNCTION public.codex_history_transfer_acknowledged(uuid, bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.codex_history_transfer_acknowledged(uuid, bigint) FROM anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.codex_history_transfer_acknowledged(uuid, bigint) TO authenticated;

COMMENT ON TABLE public.codex_history_transfer_acknowledgments IS
  'Content-free, per-member acknowledgment of a Codex provider-account change for one conversation generation. Purged on generation, membership, account, or conversation change.';

COMMIT;
