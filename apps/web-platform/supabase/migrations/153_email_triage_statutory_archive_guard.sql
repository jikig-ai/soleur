-- =====================================================================
-- 145. set_email_triage_status — statutory archive pin
--     (feat-inbox-bulk-archive / #9284)
--
-- Reproduces mig 111's body verbatim (workspace-OWNER authz — the LIVE
-- definition; 126 only comments on it) with ONE added clause: a statutory
-- row (statutory_class IS NOT NULL) can never transition to 'archived'.
-- Statutory items are pinned in NEEDS YOU until handled; the UI has never
-- offered archive on them, but the RPC had no DB-level pin — a crafted
-- call to POST /api/inbox/emails/[id]/archive could archive one.
--
-- Placement: after the status<>'new' gate, BEFORE the WORM-trigger GUC —
-- the clause must raise before the only sanctioned status-write path arms.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.set_email_triage_status(p_id uuid, p_status text)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.email_triage_items%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'set_email_triage_status: authenticated callers only'
      USING ERRCODE = '42501';
  END IF;

  IF p_status NOT IN ('acknowledged', 'archived') THEN
    RAISE EXCEPTION 'set_email_triage_status: invalid target status %; only new -> acknowledged|archived', p_status
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_row
  FROM public.email_triage_items
  WHERE id = p_id
  FOR UPDATE;

  -- Same error for missing row and non-owner-of-workspace row — no existence
  -- oracle. mig 111: authorize any OWNER of the row's workspace (was: user_id pin).
  IF NOT FOUND
     OR v_row.workspace_id IS NULL
     OR NOT public.is_email_triage_workspace_owner(v_row.workspace_id, auth.uid())
  THEN
    RAISE EXCEPTION 'set_email_triage_status: not authorized'
      USING ERRCODE = '42501';
  END IF;

  IF v_row.status <> 'new' THEN
    RAISE EXCEPTION 'set_email_triage_status: transition from % rejected; only new -> acknowledged|archived', v_row.status
      USING ERRCODE = 'P0001';
  END IF;

  -- mig 153: statutory rows are never archivable — they are pinned in
  -- NEEDS YOU until handled (acknowledge). The UI hides the button; this is
  -- the DB pin behind it (feat-inbox-bulk-archive / #9284).
  IF p_status = 'archived' AND v_row.statutory_class IS NOT NULL THEN
    RAISE EXCEPTION 'set_email_triage_status: statutory rows are never archived'
      USING ERRCODE = 'P0001';
  END IF;

  SET LOCAL app.email_triage_status_in_progress = 'on';
  UPDATE public.email_triage_items
     SET status            = p_status,
         status_changed_at = now(),
         acknowledged_at   = CASE WHEN p_status = 'acknowledged' THEN now()
                                  ELSE acknowledged_at END
   WHERE id = p_id;
  SET LOCAL app.email_triage_status_in_progress = 'off';
END;
$$;

REVOKE ALL ON FUNCTION public.set_email_triage_status(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_email_triage_status(uuid, text)
  TO authenticated;

COMMENT ON FUNCTION public.set_email_triage_status(uuid, text) IS
  'Workspace-OWNER-pinned (mig 111; was user_id-pinned) one-way status '
  'transition for email_triage_items: only new -> acknowledged|archived. '
  'mig 153: statutory rows (statutory_class IS NOT NULL) are never '
  'archivable — the pin behind the UI-hidden archive affordance. '
  'Authorizes any Owner of the row''s workspace via '
  'is_email_triage_workspace_owner. Same error for missing+foreign row '
  '(no existence oracle). Sets app.email_triage_status_in_progress for the '
  'WORM trigger — the only sanctioned status-write path.';
