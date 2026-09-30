-- 154_inbox_item_idempotent_rearchive.down.sql
-- Reverts mig 154: restores set_inbox_item_state to the mig-122 body
-- verbatim (no idempotent early-return on already-archived rows).

CREATE OR REPLACE FUNCTION public.set_inbox_item_state(p_id uuid, p_action text)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.inbox_item%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'set_inbox_item_state: authenticated callers only'
      USING ERRCODE = '42501';
  END IF;

  IF p_action NOT IN ('read', 'acted', 'archived') THEN
    RAISE EXCEPTION 'set_inbox_item_state: invalid action %; only read|acted|archived', p_action
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_row
  FROM public.inbox_item
  WHERE id = p_id
  FOR UPDATE;

  -- Same error for missing row and non-authorized row — no existence oracle.
  -- Authorize exactly as the SELECT policy: recipient of a targeted row, or an
  -- Owner of a broadcast row's workspace.
  IF NOT FOUND
     OR NOT (
       (v_row.user_id = auth.uid())
       OR (v_row.user_id IS NULL AND public.is_workspace_owner(v_row.workspace_id, auth.uid()))
     )
  THEN
    RAISE EXCEPTION 'set_inbox_item_state: not authorized'
      USING ERRCODE = '42501';
  END IF;

  IF p_action = 'archived' THEN
    -- Archive-guard: an un-acted action_required item must be acted before it
    -- can be archived (a misclick must not permanently lose an approval).
    IF v_row.severity = 'action_required' AND v_row.acted_at IS NULL THEN
      RAISE EXCEPTION 'set_inbox_item_state: cannot archive an un-acted action_required item'
        USING ERRCODE = 'P0001';
    END IF;
    UPDATE public.inbox_item
       SET status = 'archived', archived_at = now()
     WHERE id = p_id;

  ELSIF p_action = 'acted' THEN
    -- Set-once: already-acted is a no-op (idempotent). Acting also marks read
    -- (an item you acted on is necessarily seen). Never demotes an archived row.
    IF v_row.acted_at IS NULL THEN
      UPDATE public.inbox_item
         SET acted_at = now(),
             read_at  = COALESCE(read_at, now()),
             status   = CASE WHEN status = 'archived' THEN status ELSE 'read' END
       WHERE id = p_id;
    END IF;

  ELSE  -- 'read'
    IF v_row.read_at IS NULL THEN
      UPDATE public.inbox_item
         SET read_at = now(),
             status  = CASE WHEN status = 'unread' THEN 'read' ELSE status END
       WHERE id = p_id;
    END IF;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_inbox_item_state(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_inbox_item_state(uuid, text)
  TO authenticated;

COMMENT ON FUNCTION public.set_inbox_item_state(uuid, text) IS
  'Owner/recipient-pinned state transitions for inbox_item (read|acted|archived). '
  'SECURITY DEFINER; authorization mirrors the SELECT policy (recipient of a '
  'targeted row, or an Owner of a broadcast row''s workspace). Same error for '
  'missing + foreign row (no existence oracle). Archive-guard blocks archiving an '
  'un-acted action_required item. acted_at is set-once/idempotent. The ONLY '
  'sanctioned authenticated write path (no write RLS policy exists).';
