-- 111_email_triage_items_workspace_shared.sql
-- feat-shared-workspace-email-triage-inbox — re-key the operator email-triage
-- inbox from single-user grain to WORKSPACE grain so every Owner of the owning
-- workspace can read + act on statutory items. The notification recipient is
-- UNCHANGED (single configured owner); only READ access broadens.
--
-- Root cause this resolves: EMAIL_TRIAGE_OWNER_USER_ID resolves to ops@jikigai.com;
-- rows are written user_id=owner; the operator logs in as jean.deruelle@jikigai.com
-- (a co-Owner of the same workspace) → the user_id-scoped RLS returned no row → 404.
--
-- Phase 0 (prod, read-only, 2026-06-17): workspace 754ee124 owns the items;
-- jean.deruelle@ (52af49c2) is role='owner' there; workspace_id == owner uid
-- (residual-personal-workspace shape, mig 109), so the backfill workspace_id =
-- user_id stamps the correct workspace.
--
-- Precedent: 068_attachments_workspace_shared.sql (SECURITY DEFINER plpgsql
-- membership helper defeating planner inlining of the tenant boundary). Here the
-- helper is OWNER-scoped (role='owner'), not is_workspace_member (any member) —
-- members are excluded by the operator's "Owners only" decision.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every fn pins
-- SET search_path = public, pg_temp.
-- Transaction wrapping: NO top-level BEGIN/COMMIT — run-migrations.sh wraps the
-- body + the _schema_migrations INSERT in one --single-transaction stream.

-- =====================================================================
-- 0. Preconditions
-- =====================================================================

DO $$ BEGIN
  IF to_regclass('public.workspaces') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.workspaces must exist before 111';
  END IF;
  IF to_regclass('public.workspace_members') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.workspace_members must exist before 111';
  END IF;
  IF to_regclass('public.email_triage_items') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.email_triage_items must exist before 111';
  END IF;
END $$;

-- =====================================================================
-- 1. workspace_id column
--    NEVER CASCADE (mirror user_id): a workspace delete must not silently
--    destroy statutory evidence. ON DELETE RESTRICT.
-- =====================================================================

ALTER TABLE public.email_triage_items
  ADD COLUMN IF NOT EXISTS workspace_id uuid NULL
    REFERENCES public.workspaces(id) ON DELETE RESTRICT;

COMMENT ON COLUMN public.email_triage_items.workspace_id IS
  'Owning workspace (mig 111). Set at insert by the write path; backfilled = '
  'user_id for pre-111 rows (residual-personal-workspace shape). Reads are gated '
  'on workspace OWNER membership via is_email_triage_workspace_owner. WORM: '
  'immutable once set (backfill NULL->value only). NULL after Art.17 anonymise '
  'leaves the row unreadable — correct (erased).';

-- =====================================================================
-- 2. WORM trigger: add workspace_id to the frozen set + a backfill GUC arm.
--    Reproduces mig 102's body verbatim plus one new arm (Postgres has no
--    ALTER FUNCTION BODY). The down.sql restores mig 102's body.
-- =====================================================================

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

  -- workspace_id (mig 111): set once at insert; immutable thereafter. The ONLY
  -- sanctioned UPDATE is the mig-111 backfill (NULL -> value) under its GUC.
  -- value->NULL and value-change are rejected even under the GUC.
  IF NEW.workspace_id IS DISTINCT FROM OLD.workspace_id THEN
    IF NOT (current_setting('app.email_triage_backfill_in_progress', true) = 'on'
            AND OLD.workspace_id IS NULL AND NEW.workspace_id IS NOT NULL) THEN
      RAISE EXCEPTION 'email_triage_items.workspace_id is immutable (set at insert; backfill NULL->value only)'
        USING ERRCODE = 'P0001';
    END IF;
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
    RAISE EXCEPTION 'email_triage_items.summary is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;
  IF OLD.mail_class IS NOT NULL AND NEW.mail_class IS DISTINCT FROM OLD.mail_class THEN
    RAISE EXCEPTION 'email_triage_items.mail_class is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;
  IF OLD.statutory_class IS NOT NULL AND NEW.statutory_class IS DISTINCT FROM OLD.statutory_class THEN
    RAISE EXCEPTION 'email_triage_items.statutory_class is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;
  IF OLD.rule_id IS NOT NULL AND NEW.rule_id IS DISTINCT FROM OLD.rule_id THEN
    RAISE EXCEPTION 'email_triage_items.rule_id is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;

  IF OLD.acknowledged_at IS NOT NULL AND NEW.acknowledged_at IS DISTINCT FROM OLD.acknowledged_at THEN
    RAISE EXCEPTION 'email_triage_items.acknowledged_at is immutable once set'
      USING ERRCODE = 'P0001';
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

-- Triggers already exist from mig 102; CREATE OR REPLACE above rebinds the body.

-- =====================================================================
-- 3. Backfill workspace_id for pre-111 rows (residual-personal-workspace
--    shape: workspace_id = user_id). Gated by the new GUC so the WORM
--    trigger admits the one-time UPDATE.
-- =====================================================================

DO $backfill$
DECLARE
  v_rows integer;
BEGIN
  SET LOCAL app.email_triage_backfill_in_progress = 'on';
  UPDATE public.email_triage_items
     SET workspace_id = user_id
   WHERE workspace_id IS NULL
     AND user_id IS NOT NULL;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  SET LOCAL app.email_triage_backfill_in_progress = 'off';
  RAISE NOTICE 'mig 111 backfilled workspace_id on % row(s)', v_rows;
END $backfill$;

-- =====================================================================
-- 4. Owner-membership helper (SECURITY DEFINER plpgsql — mig 068 pattern;
--    plpgsql NOT sql so the planner cannot inline the membership SELECT into
--    the caller's RLS context and re-trigger tenant-isolation chains).
--    OWNER-scoped (role='owner'): members are excluded by design.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.is_email_triage_workspace_owner(
  p_workspace_id uuid,
  p_user_id      uuid
) RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_workspace_id IS NULL OR p_user_id IS NULL THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = p_user_id
      AND role         = 'owner'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.is_email_triage_workspace_owner(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_email_triage_workspace_owner(uuid, uuid)
  TO authenticated;

COMMENT ON FUNCTION public.is_email_triage_workspace_owner(uuid, uuid) IS
  'TRUE if p_user_id is an OWNER (role=owner) of p_workspace_id. SECURITY '
  'DEFINER plpgsql so planner-inlining cannot dissolve the tenant boundary. '
  'Substrate for the mig 111 email_triage_items SELECT policy + the '
  'set_email_triage_status re-auth. Owners-only by design (members excluded).';

-- =====================================================================
-- 5. RLS: replace owner-by-user_id SELECT with owner-by-workspace-membership.
--    Writes remain RPC/service-role only (no authenticated write policy —
--    learning 2026-05-21: an owner-write policy beside RPCs is a bypass path).
-- =====================================================================

DROP POLICY IF EXISTS email_triage_items_owner_select ON public.email_triage_items;
DROP POLICY IF EXISTS email_triage_items_workspace_owner_select ON public.email_triage_items;
CREATE POLICY email_triage_items_workspace_owner_select ON public.email_triage_items
  FOR SELECT TO authenticated
  USING (public.is_email_triage_workspace_owner(workspace_id, auth.uid()));

-- Workspace-scoped read index (mirrors the user_id index from mig 102; the
-- user_id indexes stay — harmless, and DSAR/anonymise still query by user_id).
CREATE INDEX IF NOT EXISTS email_triage_items_workspace_received_idx
  ON public.email_triage_items (workspace_id, received_at DESC)
  WHERE status <> 'archived';

-- =====================================================================
-- 6. set_email_triage_status — re-auth from user_id pin to workspace-OWNER pin.
--    Reproduces mig 102's body verbatim with the authorization line changed.
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
  'Authorizes any Owner of the row''s workspace via '
  'is_email_triage_workspace_owner. Same error for missing+foreign row '
  '(no existence oracle). Sets app.email_triage_status_in_progress for the '
  'WORM trigger — the only sanctioned status-write path.';
