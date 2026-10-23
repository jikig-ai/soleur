BEGIN;
SET LOCAL lock_timeout = '30s';
SET LOCAL statement_timeout = '5min';

-- Stores that the current conversation owner was sent the notice for one
-- provider-mode generation. It contains no message or notice text.
-- LAWFUL_BASIS: provisional Art. 6(1)(b) candidate — records the explicit step required to perform an owner-requested provider switch; validate with CLO before qualification.
-- RETENTION: issuance is generation- and membership-epoch-scoped, consumed by acknowledgment, purged when either epoch changes, and cascaded on conversation, account, or membership deletion.
CREATE TABLE public.codex_history_transfer_notice_issuances (
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  workspace_id uuid NOT NULL,
  member_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  auth_mode_generation bigint NOT NULL CHECK (auth_mode_generation > 0),
  workspace_member_created_at timestamptz NOT NULL,
  nonce_hash text NOT NULL CHECK (nonce_hash ~ '^[a-f0-9]{64}$'),
  delivered_at timestamptz,
  issued_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, member_user_id, auth_mode_generation, workspace_member_created_at),
  FOREIGN KEY (workspace_id, member_user_id)
    REFERENCES public.workspace_members(workspace_id, user_id) ON DELETE CASCADE
);

ALTER TABLE public.codex_history_transfer_notice_issuances ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.codex_history_transfer_notice_issuances FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.issue_codex_history_transfer_notice(
  p_conversation_id uuid,
  p_auth_mode_generation bigint,
  p_member_user_id uuid,
  p_nonce_hash text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_member_user_id uuid := p_member_user_id;
  v_workspace_id uuid;
  v_membership_created_at timestamptz;
BEGIN
  IF v_member_user_id IS NULL OR p_auth_mode_generation IS NULL OR p_auth_mode_generation <= 0
     OR p_nonce_hash IS NULL
     OR p_nonce_hash !~ '^[a-f0-9]{64}$' THEN
    RETURN false;
  END IF;

  SELECT r.workspace_id INTO v_workspace_id
    FROM public.agent_engine_runs AS r
    JOIN public.conversations AS c
      ON c.id = r.conversation_id
     AND c.workspace_id = r.workspace_id
   WHERE r.conversation_id = p_conversation_id
     AND c.user_id = v_member_user_id
     AND r.execution_kind = 'conversation'
     AND r.engine_id = 'codex'
     AND r.auth_mode_generation = p_auth_mode_generation
   ORDER BY r.id
   LIMIT 1
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

  DELETE FROM public.codex_history_transfer_notice_issuances AS i
   WHERE i.conversation_id = p_conversation_id
     AND i.member_user_id = v_member_user_id
     AND (i.auth_mode_generation <> p_auth_mode_generation
       OR i.workspace_member_created_at <> v_membership_created_at);

  INSERT INTO public.codex_history_transfer_notice_issuances (
    conversation_id, workspace_id, member_user_id, auth_mode_generation, workspace_member_created_at, nonce_hash
  ) VALUES (
    p_conversation_id, v_workspace_id, v_member_user_id, p_auth_mode_generation, v_membership_created_at, p_nonce_hash
  ) ON CONFLICT (conversation_id, member_user_id, auth_mode_generation, workspace_member_created_at)
    DO UPDATE SET nonce_hash = EXCLUDED.nonce_hash, delivered_at = NULL;

  RETURN true;
END;
$$;

CREATE FUNCTION public.mark_codex_history_transfer_notice_delivered(
  p_conversation_id uuid, p_auth_mode_generation bigint, p_member_user_id uuid, p_nonce_hash text
) RETURNS boolean
LANGUAGE sql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.codex_history_transfer_notice_issuances AS i
     SET delivered_at = now()
   WHERE i.conversation_id = p_conversation_id
     AND i.member_user_id = p_member_user_id
     AND i.auth_mode_generation = p_auth_mode_generation
     AND i.nonce_hash = p_nonce_hash
     AND i.delivered_at IS NULL
  RETURNING true
$$;

CREATE FUNCTION public.delete_codex_history_transfer_notice_issuance(
  p_conversation_id uuid, p_auth_mode_generation bigint, p_member_user_id uuid, p_nonce_hash text
) RETURNS boolean
LANGUAGE sql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH removed AS (
    DELETE FROM public.codex_history_transfer_notice_issuances AS i
     WHERE i.conversation_id = p_conversation_id
       AND i.member_user_id = p_member_user_id
       AND i.auth_mode_generation = p_auth_mode_generation
       AND i.nonce_hash = p_nonce_hash
       AND i.delivered_at IS NULL
    RETURNING 1
  ) SELECT EXISTS (SELECT 1 FROM removed)
$$;

CREATE FUNCTION public.purge_stale_codex_history_transfer_notice_issuances()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.auth_mode_generation IS DISTINCT FROM OLD.auth_mode_generation THEN
    DELETE FROM public.codex_history_transfer_notice_issuances
     WHERE conversation_id = NEW.conversation_id;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER purge_stale_codex_history_transfer_notice_issuances
AFTER UPDATE OF auth_mode_generation ON public.agent_engine_runs
FOR EACH ROW EXECUTE FUNCTION public.purge_stale_codex_history_transfer_notice_issuances();

CREATE FUNCTION public.purge_replaced_codex_history_notice_membership()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    DELETE FROM public.codex_history_transfer_notice_issuances
     WHERE workspace_id = OLD.workspace_id AND member_user_id = OLD.user_id;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER purge_replaced_codex_history_notice_membership
AFTER UPDATE OF created_at ON public.workspace_members
FOR EACH ROW EXECUTE FUNCTION public.purge_replaced_codex_history_notice_membership();

-- Remove the legacy two-argument overload. Leaving it executable would let
-- authenticated callers bypass notice possession and delivery proof.
REVOKE ALL ON FUNCTION public.record_codex_history_transfer_acknowledgment(uuid, bigint) FROM PUBLIC, anon, authenticated, service_role;
DROP FUNCTION public.record_codex_history_transfer_acknowledgment(uuid, bigint);

CREATE FUNCTION public.record_codex_history_transfer_acknowledgment(
  p_conversation_id uuid,
  p_auth_mode_generation bigint,
  p_nonce_hash text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_member_user_id uuid := auth.uid();
  v_workspace_id uuid;
  v_membership_created_at timestamptz;
BEGIN
  IF v_member_user_id IS NULL OR p_auth_mode_generation IS NULL OR p_auth_mode_generation <= 0
     OR p_nonce_hash IS NULL OR p_nonce_hash !~ '^[a-f0-9]{64}$' THEN
    RETURN false;
  END IF;

  SELECT r.workspace_id INTO v_workspace_id
    FROM public.agent_engine_runs AS r
    JOIN public.conversations AS c
      ON c.id = r.conversation_id
     AND c.workspace_id = r.workspace_id
   WHERE r.conversation_id = p_conversation_id
     AND c.user_id = v_member_user_id
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

  DELETE FROM public.codex_history_transfer_notice_issuances AS i
   WHERE i.conversation_id = p_conversation_id
     AND i.member_user_id = v_member_user_id
     AND i.auth_mode_generation = p_auth_mode_generation
     AND i.workspace_member_created_at = v_membership_created_at
     AND i.nonce_hash = p_nonce_hash
     AND i.delivered_at IS NOT NULL;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  INSERT INTO public.codex_history_transfer_acknowledgments (
    conversation_id, member_user_id, auth_mode_generation, workspace_member_created_at
  ) VALUES (
    p_conversation_id, v_member_user_id, p_auth_mode_generation, v_membership_created_at
  ) ON CONFLICT (
    conversation_id, member_user_id, auth_mode_generation, workspace_member_created_at
  ) DO NOTHING;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.issue_codex_history_transfer_notice(uuid, bigint, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.issue_codex_history_transfer_notice(uuid, bigint, uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.mark_codex_history_transfer_notice_delivered(uuid, bigint, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_codex_history_transfer_notice_delivered(uuid, bigint, uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.delete_codex_history_transfer_notice_issuance(uuid, bigint, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.delete_codex_history_transfer_notice_issuance(uuid, bigint, uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.purge_stale_codex_history_transfer_notice_issuances() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.purge_replaced_codex_history_notice_membership() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_codex_history_transfer_acknowledgment(uuid, bigint, text) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.record_codex_history_transfer_acknowledgment(uuid, bigint, text) TO authenticated;

COMMIT;
