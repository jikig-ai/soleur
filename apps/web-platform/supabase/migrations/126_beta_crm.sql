-- 126_beta_crm.sql
-- feat-beta-conversation-capture #6165 (ADR-102) — per-tenant, owner-private,
-- agent-native capture store for beta-tester / prospect conversations.
--
-- Tables (3):
--   1. beta_contacts                  — MUTABLE contact/opportunity head.
--   2. interview_notes                — APPEND-ONLY dual-lens conversation notes.
--   3. beta_contact_stage_transitions — APPEND-ONLY pipeline velocity source.
--
-- RLS posture (ADR-102 §3-5): SELECT-for-owner-only on all three; NO
--   INSERT/UPDATE/DELETE policy for authenticated (an owner-write policy beside
--   the RPCs is itself a bypass — learning 2026-05-21). Table-level
--   INSERT/UPDATE/DELETE REVOKEd from PUBLIC, anon, authenticated AND
--   service_role (no service-role write pipeline exists; RPCs run as function
--   owner). Plus a RESTRICTIVE <table>_jti_not_denied policy (068/076/077 shape)
--   so a revoked/stolen founder JWT used directly against PostgREST is rejected
--   at the policy boundary.
--
-- Writes are RPC-only, through auth.uid()-pinned SECURITY DEFINER RPCs. Because
--   SECURITY DEFINER bypasses RLS, every write RPC opens with an
--   `auth.uid() IS NULL -> 42501` guard, then `SELECT ... FOR UPDATE` +
--   re-checks `user_id = auth.uid()` before mutating (no blind ON CONFLICT; the
--   FOR UPDATE also serializes concurrent stage changes). Missing row and
--   foreign row raise the SAME 42501 — no existence oracle. Shape mirrors
--   set_email_triage_status (mig 102:246-298).
--
-- Immutability (ADR-102 §3): the two history tables are append-only by RLS
--   SHAPE (SELECT-only policy; INSERT only via RPC; the RPCs never UPDATE/DELETE
--   them), NOT a WORM no-mutate trigger — the beta-CRM has no statutory-retention
--   class, and a no-mutate trigger would reintroduce the Art. 17 CASCADE deadlock
--   (learning 2026-05-25). A migration-body guard test asserts no UPDATE/DELETE
--   statement targets the two history tables.
--
-- Erasure (ADR-102 §4): plain ON DELETE CASCADE (simpler than email_triage's
--   RESTRICT + anonymise — no statutory rows to retain). users -> beta_contacts
--   -> children. Owner erasure via account delete CASCADE; third-party
--   (beta-tester) Art. 17 erasure via the service_role-only crm_erase_contact RPC.
--
-- Retention (ADR-102 §7): 24 months from COALESCE(last_contact, created_at) via
--   in-migration pg_cron (the processed_resend_events precedent, mig 102:452-468).
--
-- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f)); LIA per
--   knowledge-base/legal/legitimate-interest-assessments/2026-07-07-beta-crm-lia.md;
--   PA-30 in knowledge-base/legal/article-30-register.md. Involuntary
--   third-party data subject -> Art. 14 notice (see LIA).
--
-- Stage enum is the single source of truth in
--   apps/web-platform/server/crm/stage-probability.ts (STAGE_PROBABILITY keys);
--   a drift-guard test asserts the CHECK set below equals Object.keys(...).
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every fn pins
--   SET search_path = public, pg_temp.

-- =====================================================================
-- 0. Preconditions (cross-file references)
-- =====================================================================

DO $$ BEGIN
  IF to_regclass('public.users') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.users must exist before 126';
  END IF;
  IF to_regprocedure('public.is_jti_denied_from_jwt()') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.is_jti_denied_from_jwt() (mig 068) must exist before 126';
  END IF;
END $$;

-- =====================================================================
-- 1. beta_contacts — MUTABLE contact/opportunity head
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.beta_contacts (
  id                   uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              uuid         NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); LIA legitimate-interest-assessments/2026-07-07-beta-crm-lia.md)
  name                 text         NULL,
  -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); LIA legitimate-interest-assessments/2026-07-07-beta-crm-lia.md)
  company              text         NULL,
  -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); LIA legitimate-interest-assessments/2026-07-07-beta-crm-lia.md)
  role                 text         NULL,
  -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); LIA legitimate-interest-assessments/2026-07-07-beta-crm-lia.md)
  source               text         NULL,
  stage                text         NOT NULL DEFAULT 'new'
                         CHECK (stage IN ('new', 'contacted', 'qualified', 'evaluating', 'committed', 'closed_won', 'closed_lost')),
  next_action          text         NULL,
  next_action_date     date         NULL,
  last_contact         date         NULL,
  amount               numeric      NULL,
  currency             text         NULL CHECK (currency ~ '^[A-Z]{3}$'),
  amount_basis         text         NOT NULL DEFAULT 'unknown'
                         CHECK (amount_basis IN ('hypothetical_acv', 'committed', 'unknown')),
  expected_close_date  date         NULL,
  created_at           timestamptz  NOT NULL DEFAULT now(),
  updated_at           timestamptz  NOT NULL DEFAULT now(),
  -- No amount without a unit (data-integrity P2-1).
  CONSTRAINT beta_contacts_amount_requires_currency
    CHECK (amount IS NULL OR currency IS NOT NULL),
  -- Composite-FK target for the children: a child can only ever carry its
  -- parent's owner, so a denormalized-user_id mis-stamp is a DB error.
  CONSTRAINT beta_contacts_id_user_unique UNIQUE (id, user_id)
);

COMMENT ON TABLE public.beta_contacts IS
  'Beta-CRM contact/opportunity head (feat-beta-conversation-capture #6165, '
  'ADR-102). Owner-private (owner-only RLS); writes RPC-only via '
  'crm_contact_upsert/crm_contact_set_stage. Third-party PII under Art. 6(1)(f) '
  'legitimate interest (LIA; PA-30). 24-month retention via pg_cron. Art. 17: '
  'ON DELETE CASCADE (owner) + crm_erase_contact (third-party, service_role).';

-- =====================================================================
-- 2. interview_notes — APPEND-ONLY dual-lens conversation notes
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.interview_notes (
  id           uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id   uuid         NOT NULL,
  user_id      uuid         NOT NULL,
  -- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f); LIA legitimate-interest-assessments/2026-07-07-beta-crm-lia.md)
  body         text         NOT NULL,
  -- cardinality(), NOT array_length: array_length('{}',1) is NULL (a CHECK
  -- treats NULL as satisfied, so an empty-lens note would pass);
  -- cardinality('{}')=0 rejects it (data-integrity P1-3).
  lens         text[]       NOT NULL
                 CHECK (lens <@ ARRAY['sales', 'product'] AND cardinality(lens) >= 1),
  occurred_at  date         NULL,
  created_at   timestamptz  NOT NULL DEFAULT now(),
  -- Composite FK: (contact_id, user_id) must match a beta_contacts row's
  -- (id, user_id) — closes the cross-tenant mis-stamp / injection vector.
  CONSTRAINT interview_notes_contact_owner_fk
    FOREIGN KEY (contact_id, user_id)
    REFERENCES public.beta_contacts (id, user_id) ON DELETE CASCADE
);

COMMENT ON TABLE public.interview_notes IS
  'Beta-CRM append-only dual-lens conversation notes (ADR-102 §2-3). Immutable '
  'by RLS shape (no UPDATE/DELETE policy; INSERT only via crm_note_append). '
  'Composite FK (contact_id, user_id) -> beta_contacts(id, user_id).';

-- =====================================================================
-- 3. beta_contact_stage_transitions — APPEND-ONLY velocity source
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.beta_contact_stage_transitions (
  id           uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id   uuid         NOT NULL,
  user_id      uuid         NOT NULL,
  from_stage   text         NULL,
  to_stage     text         NOT NULL
                 CHECK (to_stage IN ('new', 'contacted', 'qualified', 'evaluating', 'committed', 'closed_won', 'closed_lost')),
  entered_at   timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT beta_contact_stage_transitions_contact_owner_fk
    FOREIGN KEY (contact_id, user_id)
    REFERENCES public.beta_contacts (id, user_id) ON DELETE CASCADE
);

COMMENT ON TABLE public.beta_contact_stage_transitions IS
  'Beta-CRM append-only stage-transition history (ADR-102 §2). Velocity source '
  'for pipeline-analyst. Written on every stage change (and INSERT-at-non-'
  'default-stage) by crm_contact_upsert/crm_contact_set_stage. Not '
  'reconstructable retroactively (FR3).';

-- =====================================================================
-- 4. RLS — SELECT-owner-only + jti-deny RESTRICTIVE; writes REVOKEd
-- =====================================================================

ALTER TABLE public.beta_contacts                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.interview_notes                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.beta_contact_stage_transitions ENABLE ROW LEVEL SECURITY;

-- No client-role writes: RPC-only (no service-role write pipeline exists).
REVOKE INSERT, UPDATE, DELETE ON TABLE public.beta_contacts                  FROM PUBLIC, anon, authenticated, service_role;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.interview_notes                FROM PUBLIC, anon, authenticated, service_role;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.beta_contact_stage_transitions FROM PUBLIC, anon, authenticated, service_role;

-- SELECT: owner only. No INSERT/UPDATE/DELETE policies (learning 2026-05-21:
-- an owner-write policy beside RPCs is a bypass path).
DROP POLICY IF EXISTS beta_contacts_owner_select ON public.beta_contacts;
CREATE POLICY beta_contacts_owner_select ON public.beta_contacts
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS interview_notes_owner_select ON public.interview_notes;
CREATE POLICY interview_notes_owner_select ON public.interview_notes
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS beta_contact_stage_transitions_owner_select ON public.beta_contact_stage_transitions;
CREATE POLICY beta_contact_stage_transitions_owner_select ON public.beta_contact_stage_transitions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- RESTRICTIVE jti-deny (068/076/077 shape): a revoked/stolen founder JWT used
-- directly against PostgREST is rejected at the policy boundary for the JWT TTL.
DROP POLICY IF EXISTS beta_contacts_jti_not_denied ON public.beta_contacts;
CREATE POLICY beta_contacts_jti_not_denied ON public.beta_contacts
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.is_jti_denied_from_jwt())
  WITH CHECK (NOT public.is_jti_denied_from_jwt());

DROP POLICY IF EXISTS interview_notes_jti_not_denied ON public.interview_notes;
CREATE POLICY interview_notes_jti_not_denied ON public.interview_notes
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.is_jti_denied_from_jwt())
  WITH CHECK (NOT public.is_jti_denied_from_jwt());

DROP POLICY IF EXISTS beta_contact_stage_transitions_jti_not_denied ON public.beta_contact_stage_transitions;
CREATE POLICY beta_contact_stage_transitions_jti_not_denied ON public.beta_contact_stage_transitions
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.is_jti_denied_from_jwt())
  WITH CHECK (NOT public.is_jti_denied_from_jwt());

-- =====================================================================
-- 5. Indexes (plain; NEVER CONCURRENTLY — runs in the migration txn)
-- =====================================================================

CREATE INDEX IF NOT EXISTS beta_contacts_user_last_contact_idx
  ON public.beta_contacts (user_id, last_contact DESC);
CREATE INDEX IF NOT EXISTS beta_contacts_user_stage_idx
  ON public.beta_contacts (user_id, stage);
CREATE INDEX IF NOT EXISTS interview_notes_contact_occurred_idx
  ON public.interview_notes (contact_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS beta_contact_stage_transitions_contact_entered_idx
  ON public.beta_contact_stage_transitions (contact_id, entered_at);
-- Note: the composite FKs are backed by beta_contacts_id_user_unique (1).

-- =====================================================================
-- 6. updated_at trigger on beta_contacts (BEFORE UPDATE)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.beta_contacts_set_updated_at()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.beta_contacts_set_updated_at()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS beta_contacts_updated_at ON public.beta_contacts;
CREATE TRIGGER beta_contacts_updated_at
  BEFORE UPDATE ON public.beta_contacts
  FOR EACH ROW EXECUTE FUNCTION public.beta_contacts_set_updated_at();

-- =====================================================================
-- 7. crm_contact_upsert — owner-pinned INSERT or ownership-checked UPDATE
-- =====================================================================

CREATE OR REPLACE FUNCTION public.crm_contact_upsert(
  p_id                  uuid    DEFAULT NULL,
  p_name                text    DEFAULT NULL,
  p_company             text    DEFAULT NULL,
  p_role                text    DEFAULT NULL,
  p_source              text    DEFAULT NULL,
  p_stage               text    DEFAULT NULL,
  p_next_action         text    DEFAULT NULL,
  p_next_action_date    date    DEFAULT NULL,
  p_last_contact        date    DEFAULT NULL,
  p_amount              numeric DEFAULT NULL,
  p_currency            text    DEFAULT NULL,
  p_amount_basis        text    DEFAULT NULL,
  p_expected_close_date date    DEFAULT NULL
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_row   public.beta_contacts%ROWTYPE;
  v_id    uuid;
  v_stage text;
BEGIN
  -- SECURITY DEFINER bypasses RLS, so the body is the ONLY authorization gate.
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'crm_contact_upsert: authenticated callers only'
      USING ERRCODE = '42501';
  END IF;

  -- Validate stage before touching a row so a bad enum never trips the column
  -- CHECK (whose "Failing row contains (...)" DETAIL would carry name/company).
  IF p_stage IS NOT NULL
     AND p_stage NOT IN ('new', 'contacted', 'qualified', 'evaluating', 'committed', 'closed_won', 'closed_lost') THEN
    RAISE EXCEPTION 'crm_contact_upsert: invalid stage'
      USING ERRCODE = '22023';
  END IF;
  IF p_amount_basis IS NOT NULL
     AND p_amount_basis NOT IN ('hypothetical_acv', 'committed', 'unknown') THEN
    RAISE EXCEPTION 'crm_contact_upsert: invalid amount_basis'
      USING ERRCODE = '22023';
  END IF;
  -- Same PII-safe pre-validation for currency: a bad value must not trip the
  -- column CHECK (whose DETAIL carries name/company). Mirrors stage/amount_basis.
  IF p_currency IS NOT NULL AND p_currency !~ '^[A-Z]{3}$' THEN
    RAISE EXCEPTION 'crm_contact_upsert: invalid currency (ISO 4217, ^[A-Z]{3}$)'
      USING ERRCODE = '22023';
  END IF;

  IF p_id IS NULL THEN
    -- amount => currency (pre-validate so the table CHECK never fires with PII).
    IF p_amount IS NOT NULL AND p_currency IS NULL THEN
      RAISE EXCEPTION 'crm_contact_upsert: amount requires a currency'
        USING ERRCODE = '22023';
    END IF;
    -- INSERT: stamp user_id from auth.uid() (never a param).
    v_stage := COALESCE(p_stage, 'new');
    INSERT INTO public.beta_contacts (
      user_id, name, company, role, source, stage, next_action,
      next_action_date, last_contact, amount, currency, amount_basis,
      expected_close_date
    ) VALUES (
      v_uid, p_name, p_company, p_role, p_source, v_stage, p_next_action,
      p_next_action_date, p_last_contact, p_amount, p_currency,
      COALESCE(p_amount_basis, 'unknown'), p_expected_close_date
    )
    RETURNING id INTO v_id;

    -- Initial transition only when inserted at a NON-default stage.
    IF v_stage <> 'new' THEN
      INSERT INTO public.beta_contact_stage_transitions (contact_id, user_id, from_stage, to_stage)
      VALUES (v_id, v_uid, NULL, v_stage);
    END IF;

    RETURN v_id;
  END IF;

  -- UPDATE: FOR UPDATE lock + ownership re-check (serializes concurrent stage
  -- changes; missing/foreign row -> same 42501, no existence oracle).
  SELECT * INTO v_row FROM public.beta_contacts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND OR v_row.user_id <> v_uid THEN
    RAISE EXCEPTION 'crm_contact_upsert: not authorized'
      USING ERRCODE = '42501';
  END IF;

  -- amount => currency on the POST-COALESCE effective values (pre-validate so the
  -- table CHECK never fires with PII in its DETAIL).
  IF COALESCE(p_amount, v_row.amount) IS NOT NULL
     AND COALESCE(p_currency, v_row.currency) IS NULL THEN
    RAISE EXCEPTION 'crm_contact_upsert: amount requires a currency'
      USING ERRCODE = '22023';
  END IF;

  -- Partial update: unsupplied columns COALESCE-to-existing (never null a field
  -- or emit a spurious transition — spec-flow P1-3).
  UPDATE public.beta_contacts SET
    name                = COALESCE(p_name, name),
    company             = COALESCE(p_company, company),
    role                = COALESCE(p_role, role),
    source              = COALESCE(p_source, source),
    stage               = COALESCE(p_stage, stage),
    next_action         = COALESCE(p_next_action, next_action),
    next_action_date    = COALESCE(p_next_action_date, next_action_date),
    last_contact        = COALESCE(p_last_contact, last_contact),
    amount              = COALESCE(p_amount, amount),
    currency            = COALESCE(p_currency, currency),
    amount_basis        = COALESCE(p_amount_basis, amount_basis),
    expected_close_date = COALESCE(p_expected_close_date, expected_close_date)
  WHERE id = p_id;

  -- One transition iff stage was supplied AND actually changed.
  IF p_stage IS NOT NULL AND p_stage <> v_row.stage THEN
    INSERT INTO public.beta_contact_stage_transitions (contact_id, user_id, from_stage, to_stage)
    VALUES (p_id, v_uid, v_row.stage, p_stage);
  END IF;

  RETURN p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.crm_contact_upsert(uuid, text, text, text, text, text, text, date, date, numeric, text, text, date)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.crm_contact_upsert(uuid, text, text, text, text, text, text, date, date, numeric, text, text, date)
  TO authenticated;

COMMENT ON FUNCTION public.crm_contact_upsert(uuid, text, text, text, text, text, text, date, date, numeric, text, text, date) IS
  'Owner-pinned (auth.uid()) INSERT (p_id NULL) or ownership-checked UPDATE of '
  'beta_contacts. Partial update COALESCEs unsupplied columns. Appends exactly '
  'one beta_contact_stage_transitions row on INSERT-at-non-default-stage and on '
  'any stage change, in the same txn. Writes are RPC-only.';

-- =====================================================================
-- 8. crm_note_append — ownership-checked append to interview_notes
-- =====================================================================

CREATE OR REPLACE FUNCTION public.crm_note_append(
  p_contact_id  uuid,
  p_body        text,
  p_lens        text[],
  p_occurred_at date DEFAULT NULL
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_row  public.beta_contacts%ROWTYPE;
  v_id   uuid;
  v_when date := COALESCE(p_occurred_at, now()::date);
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'crm_note_append: authenticated callers only'
      USING ERRCODE = '42501';
  END IF;

  -- Validate lens BEFORE insert so the column CHECK (whose DETAIL carries the
  -- conversation body) never fires: non-empty + subset of {sales, product}.
  IF p_lens IS NULL OR cardinality(p_lens) < 1
     OR NOT (p_lens <@ ARRAY['sales', 'product']) THEN
    RAISE EXCEPTION 'crm_note_append: lens must be a non-empty subset of {sales, product}'
      USING ERRCODE = '22023';
  END IF;

  IF p_body IS NULL OR length(p_body) = 0 THEN
    RAISE EXCEPTION 'crm_note_append: body required'
      USING ERRCODE = '22023';
  END IF;

  -- occurred_at must not be in the future: a future-dated note would pin
  -- last_contact forward via GREATEST and overshoot the 24-month storage-
  -- limitation window (Art. 5(1)(e)).
  IF v_when > now()::date THEN
    RAISE EXCEPTION 'crm_note_append: occurred_at cannot be in the future'
      USING ERRCODE = '22023';
  END IF;

  -- Ownership re-check (missing/foreign -> same 42501, no oracle).
  SELECT * INTO v_row FROM public.beta_contacts WHERE id = p_contact_id FOR UPDATE;
  IF NOT FOUND OR v_row.user_id <> v_uid THEN
    RAISE EXCEPTION 'crm_note_append: not authorized'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.interview_notes (contact_id, user_id, body, lens, occurred_at)
  VALUES (p_contact_id, v_uid, p_body, p_lens, v_when)
  RETURNING id INTO v_id;

  -- Advance last_contact ONLY forward: a backdated note must not drag the
  -- retention clock (COALESCE(last_contact, created_at) < now()-24mo) backwards
  -- and prematurely expire an active contact. GREATEST ignores a NULL existing
  -- value, so the first note sets it to v_when.
  UPDATE public.beta_contacts
     SET last_contact = GREATEST(last_contact, v_when)
   WHERE id = p_contact_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.crm_note_append(uuid, text, text[], date)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.crm_note_append(uuid, text, text[], date)
  TO authenticated;

COMMENT ON FUNCTION public.crm_note_append(uuid, text, text[], date) IS
  'Owner-pinned append of a dual-lens interview_notes row (lens subset of '
  '{sales, product}, non-empty). Advances beta_contacts.last_contact forward '
  'only (GREATEST) so a backdated note cannot corrupt the retention clock. '
  'Writes are RPC-only.';

-- =====================================================================
-- 9. crm_contact_set_stage — explicit stage-change affordance
-- =====================================================================

CREATE OR REPLACE FUNCTION public.crm_contact_set_stage(
  p_contact_id uuid,
  p_to_stage   text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.beta_contacts%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'crm_contact_set_stage: authenticated callers only'
      USING ERRCODE = '42501';
  END IF;

  IF p_to_stage NOT IN ('new', 'contacted', 'qualified', 'evaluating', 'committed', 'closed_won', 'closed_lost') THEN
    RAISE EXCEPTION 'crm_contact_set_stage: invalid stage'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_row FROM public.beta_contacts WHERE id = p_contact_id FOR UPDATE;
  IF NOT FOUND OR v_row.user_id <> v_uid THEN
    RAISE EXCEPTION 'crm_contact_set_stage: not authorized'
      USING ERRCODE = '42501';
  END IF;

  -- No-op (no spurious transition) if the stage is unchanged.
  IF v_row.stage IS DISTINCT FROM p_to_stage THEN
    INSERT INTO public.beta_contact_stage_transitions (contact_id, user_id, from_stage, to_stage)
    VALUES (p_contact_id, v_uid, v_row.stage, p_to_stage);

    -- Advance last_contact to today (forward-only via GREATEST): a stage change
    -- is pipeline activity, so it refreshes the retention clock — otherwise a
    -- contact worked ONLY via stage changes (no notes, no upsert) would keep a
    -- stale anchor and be silently purged by the 24-month sweep (user-impact F2).
    UPDATE public.beta_contacts
       SET stage = p_to_stage,
           last_contact = GREATEST(last_contact, now()::date)
     WHERE id = p_contact_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.crm_contact_set_stage(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.crm_contact_set_stage(uuid, text)
  TO authenticated;

COMMENT ON FUNCTION public.crm_contact_set_stage(uuid, text) IS
  'Owner-pinned stage change: validates the target enum, appends one '
  'beta_contact_stage_transitions row, and updates beta_contacts.stage — no-op '
  '(no transition) when unchanged. Shares the transition logic with '
  'crm_contact_upsert.';

-- =====================================================================
-- 10. crm_erase_contact — third-party (beta-tester) Art. 17 erasure
--     (service_role ONLY — no auth.uid() caller)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.crm_erase_contact(p_contact_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows integer;
BEGIN
  -- Deletes the contact; the composite FKs CASCADE its notes + transitions.
  DELETE FROM public.beta_contacts WHERE id = p_contact_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.crm_erase_contact(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.crm_erase_contact(uuid)
  TO service_role;

COMMENT ON FUNCTION public.crm_erase_contact(uuid) IS
  'Third-party (beta-tester) Art. 17 erasure: deletes a beta_contacts row + '
  'CASCADEs its notes/transitions. service_role only — the auditable, '
  'implementable erasure path keyed on contact identity (distinct from the '
  'owner ON DELETE CASCADE from public.users).';

-- =====================================================================
-- 11. Retention — 24-month pg_cron sweep (mig 102:452-468 shape)
-- =====================================================================

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'beta_contacts_retention') THEN
    PERFORM cron.unschedule('beta_contacts_retention');
  END IF;
  PERFORM cron.schedule(
    'beta_contacts_retention',
    '30 4 * * *',
    -- COALESCE(last_contact, created_at::date): never-contacted rows must still
    -- expire (data-integrity P2-2). CASCADE removes children.
    $$DELETE FROM public.beta_contacts WHERE COALESCE(last_contact, created_at::date) < now()::date - interval '24 months'$$
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
  -- On DBs without pg_cron (local/CI), cron.job does not exist — warn instead
  -- of aborting the migration (mirrors the down-file's tolerance).
  WHEN undefined_table THEN
    RAISE WARNING 'pg_cron absent — beta_contacts retention sweep not scheduled';
END $cron_block$;
