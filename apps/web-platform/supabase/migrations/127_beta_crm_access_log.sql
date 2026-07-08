-- 127_beta_crm_access_log.sql
-- feat-beta-crm-ui #6172 (ADR-102 UI phase) — the read-only in-Soleur beta-CRM
-- board/funnel/drawer surface. This migration adds ONE table and ONE RPC that
-- together make the operator's *read* of third-party note bodies accountable.
--
-- Table (1):
--   beta_contact_access_log — APPEND-ONLY, owner-private record of operator
--   reads of a contact's PII (drawer-open granularity). GDPR Art. 5(2)
--   accountability: an owner reading a beta-tester's verbatim conversation
--   notes is a PII re-egress; we record it.
--
-- RPC (1):
--   crm_get_contact_detail(p_contact_id) — the ATOMIC read+audit. One
--   SECURITY DEFINER VOLATILE function inserts the access-log row AND returns
--   {contact, notes, transitions} jsonb in the SAME transaction. Fail-closed:
--   if the audit INSERT raises, the whole txn rolls back and NO data is
--   returned (no data-without-audit). This makes "un-bypassable" an INVARIANT,
--   not an aspiration, and makes SWR-revalidation duplicate log rows
--   semantically correct (each = a real re-egress). Called by the SSR cookie
--   client via supabase.rpc(...) so auth.uid() resolves from the browser
--   session.
--
-- RLS posture (mirrors mig-126 verbatim): SELECT-owner-only; NO
--   INSERT/UPDATE/DELETE policy (an owner-write policy beside the RPC is itself
--   a bypass — learning 2026-05-21); table-level INSERT/UPDATE/DELETE REVOKEd
--   from PUBLIC, anon, authenticated AND service_role (the RPC runs as function
--   owner, so it still writes). Plus the RESTRICTIVE <table>_jti_not_denied
--   policy (068/076/077/126 shape) so a revoked/stolen founder JWT used
--   directly against PostgREST is rejected at the policy boundary.
--
-- Immutability: append-only by RLS SHAPE (SELECT-only policy; INSERT only via
--   the RPC; no UPDATE/DELETE anywhere targets it) — same design as mig-126's
--   two history tables. A migration-body guard test asserts no UPDATE/DELETE.
--
-- Erasure (Art. 17): the composite FK (contact_id, user_id) ON DELETE CASCADE
--   means the access-log rows are removed with the contact — so the existing
--   service_role crm_erase_contact (mig-126) already sweeps them (its DELETE
--   FROM beta_contacts CASCADEs here too). The log holds only contactId + a
--   timestamp — never a note body.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: the fn pins
--   SET search_path = public, pg_temp.

-- =====================================================================
-- 0. Preconditions (cross-file references)
-- =====================================================================

DO $$ BEGIN
  IF to_regclass('public.beta_contacts') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.beta_contacts (mig 126) must exist before 127';
  END IF;
  IF to_regprocedure('public.is_jti_denied_from_jwt()') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.is_jti_denied_from_jwt() (mig 068) must exist before 127';
  END IF;
END $$;

-- =====================================================================
-- 1. beta_contact_access_log — APPEND-ONLY owner-read accountability
-- =====================================================================

-- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f)) + Art. 5(2) accountability;
--   LIA legitimate-interest-assessments/2026-07-07-beta-crm-lia.md (inherits the
--   parent beta_contacts basis). No content PII columns — owner id + contact
--   reference + timestamp only. RETENTION: no independent clock; rows are erased
--   WITH the contact via the composite-FK ON DELETE CASCADE (mig-126's 24-month
--   pg_cron sweep of beta_contacts CASCADEs here).
CREATE TABLE IF NOT EXISTS public.beta_contact_access_log (
  id           uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid         NOT NULL,
  contact_id   uuid         NOT NULL,
  accessed_at  timestamptz  NOT NULL DEFAULT now(),
  -- Composite FK: (contact_id, user_id) must match a beta_contacts row's
  -- (id, user_id) — closes the cross-tenant mis-stamp vector AND makes Art. 17
  -- erasure automatic (crm_erase_contact's DELETE FROM beta_contacts CASCADEs
  -- these rows away).
  CONSTRAINT beta_contact_access_log_contact_owner_fk
    FOREIGN KEY (contact_id, user_id)
    REFERENCES public.beta_contacts (id, user_id) ON DELETE CASCADE
);

COMMENT ON TABLE public.beta_contact_access_log IS
  'Beta-CRM append-only owner-read accountability log (feat-beta-crm-ui #6172, '
  'ADR-102 UI phase). GDPR Art. 5(2): records each operator read of a contact''s '
  'PII (drawer open), written ATOMICALLY inside crm_get_contact_detail '
  '(fail-closed: no PII egress without an audit row). Owner-private (owner-only '
  'RLS); INSERT only via the RPC. Holds contactId + timestamp only — never a '
  'note body. Erased with the contact via the composite-FK CASCADE.';

-- =====================================================================
-- 2. RLS — SELECT-owner-only + jti-deny RESTRICTIVE; writes REVOKEd
-- =====================================================================

ALTER TABLE public.beta_contact_access_log ENABLE ROW LEVEL SECURITY;

-- No client-role writes: RPC-only (the RPC runs as function owner).
REVOKE INSERT, UPDATE, DELETE ON TABLE public.beta_contact_access_log
  FROM PUBLIC, anon, authenticated, service_role;

-- SELECT: owner only. No INSERT/UPDATE/DELETE policy (learning 2026-05-21: an
-- owner-write policy beside the RPC is a bypass path).
DROP POLICY IF EXISTS beta_contact_access_log_owner_select ON public.beta_contact_access_log;
CREATE POLICY beta_contact_access_log_owner_select ON public.beta_contact_access_log
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- RESTRICTIVE jti-deny (068/076/077/126 shape).
DROP POLICY IF EXISTS beta_contact_access_log_jti_not_denied ON public.beta_contact_access_log;
CREATE POLICY beta_contact_access_log_jti_not_denied ON public.beta_contact_access_log
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.is_jti_denied_from_jwt())
  WITH CHECK (NOT public.is_jti_denied_from_jwt());

-- =====================================================================
-- 3. Indexes (plain; NEVER CONCURRENTLY — runs in the migration txn)
-- =====================================================================

-- Owner's own access history (Art. 15 self-serve, and the observability count).
CREATE INDEX IF NOT EXISTS beta_contact_access_log_user_accessed_idx
  ON public.beta_contact_access_log (user_id, accessed_at DESC);
-- Backs the composite-FK CASCADE lookup on contact erasure.
CREATE INDEX IF NOT EXISTS beta_contact_access_log_contact_idx
  ON public.beta_contact_access_log (contact_id);

-- =====================================================================
-- 4. crm_get_contact_detail — ATOMIC read + Art. 5(2) audit (fail-closed)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.crm_get_contact_detail(p_contact_id uuid)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  -- VOLATILE (the default) is REQUIRED: this function INSERTs the audit row; an
  -- INSERT inside a STABLE/IMMUTABLE function raises at runtime. Do not add a
  -- volatility label that would mark it STABLE.
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_contact jsonb;
  v_notes   jsonb;
  v_trans   jsonb;
BEGIN
  -- SECURITY DEFINER bypasses RLS, so the body is the ONLY authorization gate.
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'crm_get_contact_detail: authenticated callers only'
      USING ERRCODE = '42501';
  END IF;

  -- Ownership-scoped head read. A missing OR foreign contact both yield NULL
  -- -> the SAME 42501 (no existence oracle; mirrors the mig-126 RPCs). Scoping
  -- the WHERE on user_id = v_uid means a foreign row's PII is never even loaded.
  SELECT to_jsonb(c) INTO v_contact
  FROM (
    SELECT id, user_id, name, company, role, source, stage, next_action,
           next_action_date, last_contact, amount, currency, amount_basis,
           expected_close_date, created_at, updated_at
    FROM public.beta_contacts
    WHERE id = p_contact_id AND user_id = v_uid
  ) c;

  IF v_contact IS NULL THEN
    RAISE EXCEPTION 'crm_get_contact_detail: not authorized'
      USING ERRCODE = '42501';
  END IF;

  -- Art. 5(2) accountability: record this owner read BEFORE returning any PII.
  -- Fail-closed — if this INSERT raises, the whole txn rolls back and NO data
  -- is returned (no data-without-audit). This is why the fn is VOLATILE.
  INSERT INTO public.beta_contact_access_log (user_id, contact_id)
  VALUES (v_uid, p_contact_id);

  -- Dual-lens note timeline (append-only), chronological (oldest first).
  SELECT COALESCE(jsonb_agg(n ORDER BY n.occurred_at NULLS FIRST, n.created_at), '[]'::jsonb)
  INTO v_notes
  FROM (
    SELECT id, contact_id, user_id, body, lens, occurred_at, created_at
    FROM public.interview_notes
    WHERE contact_id = p_contact_id AND user_id = v_uid
  ) n;

  -- Stage-transition history (append-only), chronological.
  SELECT COALESCE(jsonb_agg(t ORDER BY t.entered_at), '[]'::jsonb)
  INTO v_trans
  FROM (
    SELECT id, contact_id, user_id, from_stage, to_stage, entered_at
    FROM public.beta_contact_stage_transitions
    WHERE contact_id = p_contact_id AND user_id = v_uid
  ) t;

  RETURN jsonb_build_object(
    'contact', v_contact,
    'notes', v_notes,
    'transitions', v_trans
  );
END;
$$;

REVOKE ALL ON FUNCTION public.crm_get_contact_detail(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.crm_get_contact_detail(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.crm_get_contact_detail(uuid) IS
  'Atomic owner read + Art. 5(2) audit of a beta_contacts detail (head + '
  'dual-lens interview_notes + stage transitions) as jsonb. VOLATILE SECURITY '
  'DEFINER: inserts one beta_contact_access_log row AND returns the detail in '
  'the same txn — fail-closed (audit INSERT failure rolls back the read; no '
  'data-without-audit). Missing/foreign contact -> uniform 42501 (no oracle). '
  'Called via supabase.rpc() on the SSR cookie client.';
