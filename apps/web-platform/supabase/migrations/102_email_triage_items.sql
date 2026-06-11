-- 102_email_triage_items.sql
-- feat-operator-inbox-delegation Phase 1 — operator email triage inbox.
--
-- Tables:
--   1. email_triage_items     — WORM triage ledger (NO body column —
--      structural parse-and-discard; the raw email body is never persisted).
--   2. processed_resend_events — svix delivery dedup (processed_<source>_events
--      pattern per migs 030/052) + pg_cron 90-day retention sweep (mig 094).
--   3. probe_tokens            — liveness-probe token store, 7-day retention
--      via purge_email_triage_items.
--
-- WORM Mutation Matrix (the plan's `## WORM Mutation Matrix` is the contract):
--   * Hard-frozen (any change → P0001): id, claim_key, message_id,
--     resend_email_id, subject, received_at, received_at_source, created_at.
--   * user_id + sender: hard-frozen EXCEPT the Art. 17 anonymise shape
--     (NOT NULL → NULL) under GUC app.email_triage_anonymise_in_progress.
--   * One-time-set (NULL → value once; any change once set → P0001 — mig 075
--     accepted_at shape at 075:117-120): summary, mail_class, statutory_class,
--     rule_id, acknowledged_at. Stubs insert SQL NULL, never ''.
--   * status / status_changed_at / acknowledged_at: writable ONLY under GUC
--     app.email_triage_status_in_progress (set by set_email_triage_status —
--     this makes transitions RPC-only; RLS cannot express transitions and a
--     route-only matrix would leave acknowledged→new DB-legal).
--   * DELETE: rejected EXCEPT under GUC app.email_triage_purge_in_progress
--     (set by purge_email_triage_items).
--
-- Bypass mechanism: SET LOCAL app.email_triage_<op>_in_progress = 'on'
-- checked via current_setting(..., true) — mig 087 precedent. NOT
-- session_replication_role (superuser-only on managed Supabase) and NOT
-- current_user = 'service_role' checks (always-false under PostgREST;
-- learnings 2026-05-18/-31).
--
-- RLS posture: SELECT-for-owner only. NO INSERT/UPDATE/DELETE policies for
-- authenticated — writes go through the service-role pipeline + the SECURITY
-- DEFINER RPCs below (per learning 2026-05-21 an owner-write policy beside
-- RPCs is itself a bypass path).
--
-- RETENTION: probe rows 7d; non-statutory rows 365d; statutory rows retained
-- for the accountability period (purge carve-out via statutory_class IS NULL).
-- processed_resend_events 90d (pg_cron); probe_tokens 7d (purge RPC).
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every fn pins
-- SET search_path = public, pg_temp.

-- =====================================================================
-- 0. FK precondition guard (cross-file reference)
-- =====================================================================

DO $$ BEGIN
  IF to_regclass('public.users') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.users must exist before 102';
  END IF;
END $$;

-- =====================================================================
-- 1. email_triage_items table
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.email_triage_items (
  id                  uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  -- NULLABLE for Art. 17 anonymise. NEVER CASCADE: CASCADE would either
  -- abort the owner's erasure via the no-delete trigger or silently destroy
  -- statutory evidence; erasure goes through anonymise_email_triage_items.
  user_id             uuid         NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  -- COALESCE(message_id, 'resend:' || resend_email_id) — RFC 5322 Message-ID
  -- is optional + sender-controlled, and Postgres UNIQUE treats NULLs as
  -- distinct, so a naked UNIQUE(message_id) would defeat dedup.
  claim_key           text         NOT NULL UNIQUE,
  -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); LIA per Phase 7)
  message_id          text         NULL,
  resend_email_id     text         NOT NULL,
  -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); LIA per Phase 7)
  sender              text         NULL,
  -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); LIA per Phase 7)
  subject             text         NOT NULL,
  -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); LIA per Phase 7)
  summary             text         NULL,
  mail_class          text         NULL CHECK (mail_class IN ('vendor', 'billing', 'security', 'newsletter', 'legal-review', 'other', 'probe')),
  -- non-NULL ⟺ deterministic-path provenance; the LLM can never write it.
  statutory_class     text         NULL CHECK (statutory_class IN ('breach', 'service-of-process', 'dsar', 'regulator')),
  rule_id             text         NULL,
  status              text         NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'acknowledged', 'archived')),
  status_changed_at   timestamptz  NULL,
  acknowledged_at     timestamptz  NULL,
  -- Sourced from the RESEND EVENT PAYLOAD receive timestamp — NEVER insert
  -- time (no DEFAULT: a 10-hour webhook retry must not eat an Art. 12 clock,
  -- and the WORM trigger makes a wrong value permanent).
  received_at         timestamptz  NOT NULL,
  received_at_source  text         NOT NULL CHECK (received_at_source IN ('payload', 'envelope')),
  created_at          timestamptz  NOT NULL DEFAULT now(),
  -- Catches epoch-unit bugs at insert instead of immortalizing them.
  CONSTRAINT email_triage_items_received_at_sane
    CHECK (received_at <= created_at + interval '5 minutes')
);

ALTER TABLE public.email_triage_items ENABLE ROW LEVEL SECURITY;

-- Column-level posture: REVOKE table-level mutations from client roles
-- (mig 075 precedent). Writes: service-role pipeline + SECURITY DEFINER RPCs.
REVOKE INSERT ON TABLE public.email_triage_items FROM PUBLIC, anon, authenticated;
REVOKE UPDATE ON TABLE public.email_triage_items FROM PUBLIC, anon, authenticated;
REVOKE DELETE ON TABLE public.email_triage_items FROM PUBLIC, anon, authenticated;

-- SELECT: owner only. NO INSERT/UPDATE/DELETE policies for authenticated
-- (learning 2026-05-21: an owner-write policy beside RPCs is a bypass path).
CREATE POLICY email_triage_items_owner_select ON public.email_triage_items
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS email_triage_items_user_received_idx
  ON public.email_triage_items (user_id, received_at DESC)
  WHERE status <> 'archived';

COMMENT ON TABLE public.email_triage_items IS
  'WORM operator email-triage ledger (feat-operator-inbox-delegation). '
  'NO body column — structural parse-and-discard. Mutation matrix enforced '
  'by email_triage_items_no_mutate; status transitions RPC-only via '
  'set_email_triage_status; purge/anonymise via GUC-gated SECURITY DEFINER '
  'RPCs (mig 087 pattern). Retention: probe 7d / non-statutory 365d / '
  'statutory per accountability period.';

-- =====================================================================
-- 2. WORM trigger (BEFORE UPDATE/DELETE) — implements the mutation matrix
-- =====================================================================

CREATE OR REPLACE FUNCTION public.email_triage_items_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- Retention purge bypass (purge_email_triage_items): privilege-free GUC.
    IF current_setting('app.email_triage_purge_in_progress', true) = 'on' THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'email_triage_items is append-only (WORM); DELETE only via purge_email_triage_items'
      USING ERRCODE = 'P0001';
  END IF;

  -- Hard-frozen columns: all knowable at claim time; the stub INSERT
  -- populates them and no path may change them.
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

  -- user_id + sender: hard-frozen EXCEPT the Art. 17 anonymise shape
  -- (NOT NULL → NULL) under the anonymise GUC. Re-identification
  -- (NULL → value) and value changes are rejected even under the GUC.
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

  -- One-time-set columns: NULL → value permitted once (the pipeline's
  -- finalize UPDATE); any change once set → P0001 (mig 075 accepted_at shape).
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

  -- acknowledged_at: one-time-set — when-the-operator-saw-it is itself WORM.
  -- (Checked BEFORE the status-GUC gate so even the RPC cannot rewrite it.)
  IF OLD.acknowledged_at IS NOT NULL AND NEW.acknowledged_at IS DISTINCT FROM OLD.acknowledged_at THEN
    RAISE EXCEPTION 'email_triage_items.acknowledged_at is immutable once set'
      USING ERRCODE = 'P0001';
  END IF;

  -- status / status_changed_at / acknowledged_at: writable ONLY under the
  -- status GUC, which only set_email_triage_status sets → RPC-only
  -- transitions (the RPC enforces the one-way matrix).
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

DROP TRIGGER IF EXISTS email_triage_items_no_update ON public.email_triage_items;
CREATE TRIGGER email_triage_items_no_update
  BEFORE UPDATE ON public.email_triage_items
  FOR EACH ROW EXECUTE FUNCTION public.email_triage_items_no_mutate();

DROP TRIGGER IF EXISTS email_triage_items_no_delete ON public.email_triage_items;
CREATE TRIGGER email_triage_items_no_delete
  BEFORE DELETE ON public.email_triage_items
  FOR EACH ROW EXECUTE FUNCTION public.email_triage_items_no_mutate();

-- =====================================================================
-- 3. set_email_triage_status RPC — owner-pinned one-way transitions
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
  -- Authorization pin: SECURITY DEFINER bypasses RLS, so the body is the
  -- ONLY thing enforcing per-caller authorization (scaffold contract).
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'set_email_triage_status: authenticated callers only'
      USING ERRCODE = '42501';
  END IF;

  -- One-way transition matrix: only new → acknowledged | archived.
  IF p_status NOT IN ('acknowledged', 'archived') THEN
    RAISE EXCEPTION 'set_email_triage_status: invalid target status %; only new -> acknowledged|archived', p_status
      USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_row
  FROM public.email_triage_items
  WHERE id = p_id
  FOR UPDATE;

  -- Same error for missing row and foreign row — no existence oracle.
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
GRANT EXECUTE ON FUNCTION public.set_email_triage_status(uuid, text)
  TO authenticated;

COMMENT ON FUNCTION public.set_email_triage_status(uuid, text) IS
  'Owner-pinned (auth.uid()) one-way status transition for '
  'email_triage_items: only new -> acknowledged|archived. Sets '
  'status_changed_at and (on acknowledge) the one-time-set acknowledged_at. '
  'Sets app.email_triage_status_in_progress for the WORM trigger — the only '
  'sanctioned status-write path.';

-- =====================================================================
-- 4. probe_tokens — liveness-probe token store (service-only)
--    (Created before the purge RPC that sweeps it.)
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.probe_tokens (
  token       text         PRIMARY KEY CHECK (length(token) BETWEEN 1 AND 128),
  created_at  timestamptz  NOT NULL DEFAULT now()
);

ALTER TABLE public.probe_tokens ENABLE ROW LEVEL SECURITY;

-- No client-facing policies: service-role only (probe cron + pipeline
-- probe-rule matching). 7-day retention via purge_email_triage_items.

COMMENT ON TABLE public.probe_tokens IS
  'Liveness-probe tokens for the email-triage probe cron '
  '(feat-operator-inbox-delegation). Service-role only. 7-day retention '
  'via purge_email_triage_items.';

-- =====================================================================
-- 5. purge_email_triage_items RPC — retention sweep (service_role ONLY)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.purge_email_triage_items()
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_probe   integer;
  v_general integer;
  v_tokens  integer;
BEGIN
  SET LOCAL app.email_triage_purge_in_progress = 'on';

  -- Probe rows: deterministic liveness traffic; 7-day retention.
  DELETE FROM public.email_triage_items
   WHERE mail_class = 'probe'
     AND received_at < now() - interval '7 days';
  GET DIAGNOSTICS v_probe = ROW_COUNT;

  -- Non-statutory rows: 365-day retention (Art. 5(1)(e)). Statutory rows
  -- (statutory_class IS NOT NULL) are retained for the accountability
  -- period — the WHERE carve-out IS the statutory retention guarantee.
  -- IS DISTINCT FROM admits unfinalized stubs (mail_class NULL) to the sweep.
  DELETE FROM public.email_triage_items
   WHERE statutory_class IS NULL
     AND mail_class IS DISTINCT FROM 'probe'
     AND received_at < now() - interval '365 days';
  GET DIAGNOSTICS v_general = ROW_COUNT;

  SET LOCAL app.email_triage_purge_in_progress = 'off';

  -- Probe tokens: 7-day retention (no WORM trigger on probe_tokens).
  DELETE FROM public.probe_tokens
   WHERE created_at < now() - interval '7 days';
  GET DIAGNOSTICS v_tokens = ROW_COUNT;

  RETURN jsonb_build_object(
    'probe_deleted',         v_probe,
    'non_statutory_deleted', v_general,
    'probe_tokens_deleted',  v_tokens
  );
END;
$$;

-- service_role ONLY (learning security-issues/2026-06-01: bulk-mutation RPCs
-- with no auth.uid() pin must never be authenticated-callable).
REVOKE ALL ON FUNCTION public.purge_email_triage_items()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.purge_email_triage_items()
  TO service_role;

COMMENT ON FUNCTION public.purge_email_triage_items() IS
  'Retention sweep for email_triage_items (probe 7d, non-statutory 365d; '
  'statutory rows retained) + probe_tokens (7d). Sets '
  'app.email_triage_purge_in_progress so the WORM no-delete trigger admits '
  'the sweep. service_role only.';

-- =====================================================================
-- 6. anonymise_email_triage_items RPC — Art. 17 cascade (service_role ONLY)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.anonymise_email_triage_items(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows integer;
BEGIN
  SET LOCAL app.email_triage_anonymise_in_progress = 'on';
  UPDATE public.email_triage_items
     SET user_id = NULL,
         sender  = NULL
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  SET LOCAL app.email_triage_anonymise_in_progress = 'off';
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_email_triage_items(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.anonymise_email_triage_items(uuid)
  TO service_role;

COMMENT ON FUNCTION public.anonymise_email_triage_items(uuid) IS
  'Art. 17 erasure for email_triage_items: NULLs user_id + sender under '
  'app.email_triage_anonymise_in_progress (the user_id FK is ON DELETE '
  'RESTRICT, so this must run BEFORE auth.admin.deleteUser). Idempotent. '
  'service_role only; wired into the account-delete flow.';

-- =====================================================================
-- 7. processed_resend_events — svix delivery dedup (mig 052 pattern)
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.processed_resend_events (
  svix_id      text         PRIMARY KEY CHECK (length(svix_id) BETWEEN 1 AND 128),
  received_at  timestamptz  NOT NULL DEFAULT now()
);

ALTER TABLE public.processed_resend_events ENABLE ROW LEVEL SECURITY;

-- No founder-facing policies: service-role only, mirrors
-- processed_github_events (mig 052). Webhook handler uses createServiceClient().

CREATE INDEX IF NOT EXISTS processed_resend_events_received_at_idx
  ON public.processed_resend_events (received_at DESC);

COMMENT ON TABLE public.processed_resend_events IS
  'Webhook svix_id dedup for the Resend inbound-email webhook '
  '(feat-operator-inbox-delegation). Mirror of processed_github_events '
  '(mig 052). Plain .insert() at webhook entry; catch PG_UNIQUE_VIOLATION '
  '(23505) -> 200 duplicate; release the row on transient failure after '
  'insert so Resend retries can re-process. Retention: daily pg_cron 90-day '
  'sweep (mig 094 pattern).';

-- Daily 90-day retention sweep (mig 094:42-70 shape).
DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'processed_resend_events_retention') THEN
    PERFORM cron.unschedule('processed_resend_events_retention');
  END IF;
  PERFORM cron.schedule(
    'processed_resend_events_retention',
    '0 4 * * *',
    $$DELETE FROM public.processed_resend_events WHERE received_at < now() - interval '90 days'$$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron_block$;
