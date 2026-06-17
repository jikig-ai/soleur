-- 111_email_triage_items_workspace_shared.down.sql
-- Reverts mig 111 to the mig-102 shape: user_id-pinned RLS + status RPC, WORM
-- trigger without the workspace_id arm, helper + index + column dropped.

-- 1. Restore set_email_triage_status to the mig-102 user_id pin.
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
  IF NOT FOUND OR v_row.user_id IS NULL OR v_row.user_id <> auth.uid() THEN
    RAISE EXCEPTION 'set_email_triage_status: not authorized'
      USING ERRCODE = '42501';
  END IF;
  IF v_row.status <> 'new' THEN
    RAISE EXCEPTION 'set_email_triage_status: transition from % rejected; only new -> acknowledged|archived', v_row.status
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
GRANT EXECUTE ON FUNCTION public.set_email_triage_status(uuid, text) TO authenticated;

-- 2. Restore the user_id SELECT policy; drop the workspace policy + index.
DROP POLICY IF EXISTS email_triage_items_workspace_owner_select ON public.email_triage_items;
DROP INDEX IF EXISTS public.email_triage_items_workspace_received_idx;
DROP POLICY IF EXISTS email_triage_items_owner_select ON public.email_triage_items;
CREATE POLICY email_triage_items_owner_select ON public.email_triage_items
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- 3. Drop the owner-membership helper.
DROP FUNCTION IF EXISTS public.is_email_triage_workspace_owner(uuid, uuid);

-- 4. Restore the mig-102 WORM trigger body (no workspace_id arm, no backfill GUC).
CREATE OR REPLACE FUNCTION public.email_triage_items_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF current_setting('app.email_triage_purge_in_progress', true) = 'on' THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'email_triage_items is append-only (WORM); DELETE only via purge_email_triage_items'
      USING ERRCODE = 'P0001';
  END IF;
  IF NEW.id                   IS DISTINCT FROM OLD.id
    OR NEW.claim_key          IS DISTINCT FROM OLD.claim_key
    OR NEW.message_id         IS DISTINCT FROM OLD.message_id
    OR NEW.resend_email_id    IS DISTINCT FROM OLD.resend_email_id
    OR NEW.subject            IS DISTINCT FROM OLD.subject
    OR NEW.received_at        IS DISTINCT FROM OLD.received_at
    OR NEW.received_at_source IS DISTINCT FROM OLD.received_at_source
    OR NEW.created_at         IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'email_triage_items hard-frozen columns are immutable (id, claim_key, message_id, resend_email_id, subject, received_at, received_at_source, created_at)'
      USING ERRCODE = 'P0001';
  END IF;
  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    IF NOT (current_setting('app.email_triage_anonymise_in_progress', true) = 'on'
            AND OLD.user_id IS NOT NULL AND NEW.user_id IS NULL) THEN
      RAISE EXCEPTION 'email_triage_items.user_id: only Art. 17 anonymise (NOT NULL -> NULL under anonymise GUC) permitted'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  IF NEW.sender IS DISTINCT FROM OLD.sender THEN
    IF NOT (current_setting('app.email_triage_anonymise_in_progress', true) = 'on'
            AND OLD.sender IS NOT NULL AND NEW.sender IS NULL) THEN
      RAISE EXCEPTION 'email_triage_items.sender: only Art. 17 anonymise (NOT NULL -> NULL under anonymise GUC) permitted'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
  IF OLD.summary IS NOT NULL AND NEW.summary IS DISTINCT FROM OLD.summary THEN
    RAISE EXCEPTION 'email_triage_items.summary is immutable once set' USING ERRCODE = 'P0001';
  END IF;
  IF OLD.mail_class IS NOT NULL AND NEW.mail_class IS DISTINCT FROM OLD.mail_class THEN
    RAISE EXCEPTION 'email_triage_items.mail_class is immutable once set' USING ERRCODE = 'P0001';
  END IF;
  IF OLD.statutory_class IS NOT NULL AND NEW.statutory_class IS DISTINCT FROM OLD.statutory_class THEN
    RAISE EXCEPTION 'email_triage_items.statutory_class is immutable once set' USING ERRCODE = 'P0001';
  END IF;
  IF OLD.rule_id IS NOT NULL AND NEW.rule_id IS DISTINCT FROM OLD.rule_id THEN
    RAISE EXCEPTION 'email_triage_items.rule_id is immutable once set' USING ERRCODE = 'P0001';
  END IF;
  IF OLD.acknowledged_at IS NOT NULL AND NEW.acknowledged_at IS DISTINCT FROM OLD.acknowledged_at THEN
    RAISE EXCEPTION 'email_triage_items.acknowledged_at is immutable once set' USING ERRCODE = 'P0001';
  END IF;
  IF (NEW.status            IS DISTINCT FROM OLD.status
    OR NEW.status_changed_at IS DISTINCT FROM OLD.status_changed_at
    OR NEW.acknowledged_at   IS DISTINCT FROM OLD.acknowledged_at)
    AND current_setting('app.email_triage_status_in_progress', true) IS DISTINCT FROM 'on'
  THEN
    RAISE EXCEPTION 'email_triage_items status transitions are RPC-only (set_email_triage_status)'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.email_triage_items_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

-- 5. Drop the workspace_id column (DDL — WORM trigger does not fire on ALTER).
ALTER TABLE public.email_triage_items DROP COLUMN IF EXISTS workspace_id;
