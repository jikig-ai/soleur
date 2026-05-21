-- 053_template_authorizations.sql
-- PR-I (#4078) — Template-level authorization ledger.
--
-- Composite migration:
--   (a) messages.template_id column + bounded backfill ('default_legacy')
--       + NOT NULL + shape CHECK (a-z0-9_, 1-64 chars).
--   (b) template_authorizations WORM table with NOT NULL bounds
--       (expires_at, soft_reconfirm_at, max_sends), revocation_reason
--       8-value enum CHECK, paired-null CHECK, partial UNIQUE on
--       (founder_id, template_hash) WHERE revoked_at IS NULL, and
--       (founder_id, revoked_at) read-path index.
--   (c) pure-reject UPDATE/DELETE trigger (mig 051 pattern; bypass via
--       SET LOCAL session_replication_role='replica' at RPC call sites).
--   (d) owner-select + owner-insert RLS (NO FOR ALL USING; learning
--       2026-04-18-rls-for-all-using).
--   (e) authorize_template SECURITY DEFINER RPC (idempotent on 23505 per
--       learning 2026-05-03-postgrest-on-conflict-cannot-infer-partial-index).
--   (f) revoke_template_authorization SECURITY DEFINER RPC (founder-
--       initiated; WORM bypass via session_replication_role).
--   (g) anonymise_template_authorizations SECURITY DEFINER RPC (Art-17
--       cascade; sibling pattern to mig 051 anonymise_action_sends with
--       self-DSAR + service-role auth gate).
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every SECURITY DEFINER
-- function pins SET search_path = public, pg_temp and qualifies every
-- relation as public.<table>.
--
-- Per 2026-04-18-supabase-migration-concurrently-forbidden: NO CREATE INDEX
-- CONCURRENTLY (Supabase wraps each migration in a transaction).
--
-- Per Kieran P1-4 (mig 051 precedent): NO outer BEGIN/COMMIT (Supabase
-- runner already wraps). This DIVERGES from plan §Phase 2 / §Risks which
-- specified an inner BEGIN;…COMMIT; envelope for "partial-apply isolation"
-- — the plan was written without re-reading mig 051's directive. The
-- partial-apply concern is moot because the outer transaction already
-- provides atomicity; an inner BEGIN/COMMIT would either no-op (savepoint
-- semantics) or prematurely commit the outer envelope.
--
-- Per learning 2026-05-18-worm-trigger-bypass-role-check-fails-under-
-- postgrest-routing.md: NO current_user='service_role' check anywhere
-- (silently always-false under PostgREST). All bypass routed through
-- SET LOCAL session_replication_role='replica' (mig 051 §(h) precedent).

-- ============================================================================
-- (a) messages.template_id column + backfill + NOT NULL + shape CHECK
-- ============================================================================
-- Per learning 2026-04-17-add-column-then-update-then-set-not-null: ADD
-- nullable → UPDATE → SET NOT NULL is the safe order on a populated table.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS template_id text;

COMMENT ON COLUMN public.messages.template_id IS
  'PR-I (#4078): canonical template registry key. Drives '
  'getTemplateHash() at the producer and the template_authorizations '
  'WORM ledger downstream. Backfilled to ''default_legacy'' for legacy '
  'rows; new producers MUST set a registry-known value. Enforced by '
  'shape CHECK below; semantic membership in TEMPLATE_IDS is enforced '
  'at the application layer via isKnownTemplateId.';

UPDATE public.messages
   SET template_id = 'default_legacy'
 WHERE template_id IS NULL;

ALTER TABLE public.messages
  ALTER COLUMN template_id SET NOT NULL;

ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_template_id_check;
ALTER TABLE public.messages
  ADD CONSTRAINT messages_template_id_check
  CHECK (template_id ~ '^[a-z][a-z0-9_]*$' AND length(template_id) BETWEEN 1 AND 64);

-- ============================================================================
-- (b) template_authorizations WORM table
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.template_authorizations (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- NULLABLE to admit Art-17 anonymisation. ON DELETE RESTRICT (via
  -- scope_grants FK below) prevents accidental scope_grant deletion
  -- before this row is anonymised. The owner column itself FKs to
  -- public.users (sibling pattern of action_sends).
  founder_id          uuid NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  template_hash       text NOT NULL CHECK (length(template_hash) BETWEEN 1 AND 128),
  action_class        text NOT NULL CHECK (length(action_class) BETWEEN 1 AND 64),
  -- Enum-absence (defense-in-depth): the application TS layer cannot
  -- enforce this at indirect call sites (RPC-from-JSON, future config
  -- imports). Same regex as scope_grants and action_sends per ADR-034 §2.
  CONSTRAINT template_authorizations_action_class_not_locked
    CHECK (action_class !~ '^(payment|legal|auth)\.'),

  -- Provisional bounds (plan §Phase 2 FR4); calibration follow-up #4217
  -- tunes. NOT NULL so a partial-INSERT cannot silently bypass the bound.
  authorized_at       timestamptz NOT NULL DEFAULT now(),
  expires_at          timestamptz NOT NULL DEFAULT (now() + interval '90 days'),
  soft_reconfirm_at   timestamptz NOT NULL DEFAULT (now() + interval '30 days'),
  max_sends           integer     NOT NULL DEFAULT 100 CHECK (max_sends > 0),

  -- Revocation columns are paired-null: either both set or both null.
  revoked_at          timestamptz NULL,
  revocation_reason   text        NULL,

  -- FK to scope_grants — the template authorization is a CHILD of an
  -- active grant. ON DELETE RESTRICT preserves the audit chain (Art. 5(2))
  -- — accidental scope_grant deletion is rejected by Postgres until the
  -- cascade in account-delete.ts anonymises this row first.
  grant_id            uuid NOT NULL REFERENCES public.scope_grants(id) ON DELETE RESTRICT,

  created_at          timestamptz NOT NULL DEFAULT now(),

  -- Paired-null invariant. Either revoked_at + revocation_reason are
  -- both set, or both are null. Prevents "revoked but no reason" and
  -- "reason without revoke" drift.
  CONSTRAINT template_authorizations_revocation_paired_null
    CHECK ((revoked_at IS NULL) = (revocation_reason IS NULL)),

  -- 8-value revocation_reason enum (plan §Sharp Edges + §Phase 2 FR15).
  -- Legal §2.3(t) un-revocability + Art. 5(2) attribution rationale.
  -- Cheaper to overprovision here than ALTER later. Three values
  -- (regulator_ordered, vendor_tos_revoked, policy_violation) have no
  -- v1 producer; quarantine_retroactive reserved for PR-I+1 (#4216).
  CONSTRAINT template_authorizations_revocation_reason_check
    CHECK (revocation_reason IS NULL OR revocation_reason IN (
      'founder_revoked',
      'quota_exhausted',
      'expired',
      'dsr_erasure',
      'regulator_ordered',
      'vendor_tos_revoked',
      'policy_violation',
      'quarantine_retroactive'
    ))
);

COMMENT ON TABLE public.template_authorizations IS
  'Per-template authorization ledger. WORM (append-only). Art. 7(3) '
  '"specific" + "informed" consent under the first-send-IS-authorization '
  'pattern (PR-I #4078): the founder''s Send click on a labeled '
  'draft_one_click button IS the explicit consent act. Subsequent sends '
  'gate on this row''s bounds (expires_at, max_sends). UPDATE/DELETE '
  'rejected by trigger; Art-17 erasure via anonymise_template_authorizations.';

-- One active authorization per (founder, template_hash). Partial UNIQUE
-- is the canonical Postgres "one active X per Y" — sibling of mig 051's
-- scope_grants_active_unique. Concurrent authorize_template calls race
-- to INSERT; the 23505 loser branch returns the existing winner's id
-- (idempotent first-writer-wins per learning 2026-05-03-postgrest-on-
-- conflict-cannot-infer-partial-index.md).
CREATE UNIQUE INDEX IF NOT EXISTS template_authorizations_active_unique
  ON public.template_authorizations (founder_id, template_hash)
  WHERE revoked_at IS NULL;

-- Read-path acceleration for the scope-grants page query
-- (page.tsx lists active authorizations) and the revoke-RPC WHERE clause.
CREATE INDEX IF NOT EXISTS template_authorizations_founder_revoked_idx
  ON public.template_authorizations (founder_id, revoked_at);

-- ============================================================================
-- (c) pure-reject UPDATE/DELETE trigger (mig 051 §(e) pattern)
--     Bypass is achieved at RPC call sites via SET LOCAL
--     session_replication_role='replica' — Postgres skips BEFORE
--     triggers in replica mode for non-REPLICA triggers.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.template_authorizations_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'template_authorizations is append-only (WORM); % rejected', TG_OP
    USING ERRCODE = 'P0001';
END;
$$;

REVOKE ALL ON FUNCTION public.template_authorizations_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS template_authorizations_no_update ON public.template_authorizations;
CREATE TRIGGER template_authorizations_no_update
  BEFORE UPDATE ON public.template_authorizations
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.template_authorizations_no_mutate();

DROP TRIGGER IF EXISTS template_authorizations_no_delete ON public.template_authorizations;
CREATE TRIGGER template_authorizations_no_delete
  BEFORE DELETE ON public.template_authorizations
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.template_authorizations_no_mutate();

-- ============================================================================
-- (d) RLS — owner-select + owner-insert. NO FOR ALL USING per learning
--     2026-04-18-rls-for-all-using-applies-to-writes.md.
-- ============================================================================
ALTER TABLE public.template_authorizations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS template_authorizations_owner_select ON public.template_authorizations;
CREATE POLICY template_authorizations_owner_select ON public.template_authorizations
  FOR SELECT TO authenticated
  USING (founder_id = auth.uid());

DROP POLICY IF EXISTS template_authorizations_owner_insert ON public.template_authorizations;
CREATE POLICY template_authorizations_owner_insert ON public.template_authorizations
  FOR INSERT TO authenticated
  WITH CHECK (founder_id = auth.uid());

-- No FOR UPDATE / FOR DELETE policies: writes route through SECURITY
-- DEFINER RPCs that bypass the WORM trigger via session_replication_role.

-- ============================================================================
-- (e) authorize_template RPC — first-send-IS-authorization writer path
-- ============================================================================
CREATE OR REPLACE FUNCTION public.authorize_template(
  p_template_hash text,
  p_action_class  text,
  p_grant_id      uuid
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_founder_id uuid := auth.uid();
  v_existing_id uuid;
  v_new_id uuid;
BEGIN
  IF v_founder_id IS NULL THEN
    RAISE EXCEPTION 'authorize_template: authenticated session required'
      USING ERRCODE = '42501';
  END IF;

  -- Input validation (defense-in-depth alongside the column CHECKs).
  IF p_template_hash IS NULL OR length(p_template_hash) < 1 OR length(p_template_hash) > 128 THEN
    RAISE EXCEPTION 'authorize_template: invalid template_hash length'
      USING ERRCODE = '22023';
  END IF;
  IF p_action_class IS NULL OR p_action_class !~ '^[a-z][a-z0-9_.]*$' OR length(p_action_class) > 64 THEN
    RAISE EXCEPTION 'authorize_template: invalid action_class'
      USING ERRCODE = '22023';
  END IF;

  BEGIN
    INSERT INTO public.template_authorizations (
      founder_id, template_hash, action_class, grant_id
    )
    VALUES (
      v_founder_id, p_template_hash, p_action_class, p_grant_id
    )
    RETURNING id INTO v_new_id;
    RETURN v_new_id;
  EXCEPTION
    WHEN unique_violation THEN
      -- 23505 against template_authorizations_active_unique. Concurrent
      -- first-send raced us; return the winner's id. Idempotent first-
      -- writer-wins (learning 2026-05-03).
      SELECT id INTO v_existing_id
        FROM public.template_authorizations
       WHERE founder_id = v_founder_id
         AND template_hash = p_template_hash
         AND revoked_at IS NULL
       LIMIT 1;
      IF v_existing_id IS NULL THEN
        -- Shouldn't happen — the 23505 by definition implies a row
        -- exists. Re-raise rather than fabricate.
        RAISE;
      END IF;
      RETURN v_existing_id;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.authorize_template(text, text, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.authorize_template(text, text, uuid)
  TO authenticated;

COMMENT ON FUNCTION public.authorize_template(text, text, uuid) IS
  'First-send-IS-authorization writer. INSERTs a template_authorizations '
  'row for the calling founder. Idempotent on 23505 partial-UNIQUE '
  'conflict (returns existing active row''s id). Art. 7(3) "specific" + '
  '"informed" consent — call site is the founder''s Send click.';

-- ============================================================================
-- (f) revoke_template_authorization RPC — founder-initiated revoke
-- ============================================================================
CREATE OR REPLACE FUNCTION public.revoke_template_authorization(
  p_template_hash text,
  p_reason        text
) RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  affected integer;
  v_founder_id uuid := auth.uid();
BEGIN
  IF v_founder_id IS NULL THEN
    RAISE EXCEPTION 'revoke_template_authorization: authenticated session required'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason NOT IN (
    'founder_revoked', 'quota_exhausted', 'expired', 'dsr_erasure',
    'regulator_ordered', 'vendor_tos_revoked', 'policy_violation',
    'quarantine_retroactive'
  ) THEN
    RAISE EXCEPTION 'revoke_template_authorization: invalid reason %', p_reason
      USING ERRCODE = '22023';
  END IF;

  -- WORM trigger blocks all UPDATEs including founder-initiated revoke; bypass is required.
  -- session_replication_role='replica' makes Postgres skip BEFORE
  -- triggers in this transaction. RESET below.
  SET LOCAL session_replication_role = 'replica';
  UPDATE public.template_authorizations
     SET revoked_at = now(),
         revocation_reason = p_reason
   WHERE founder_id = v_founder_id
     AND template_hash = p_template_hash
     AND revoked_at IS NULL;
  GET DIAGNOSTICS affected = ROW_COUNT;
  RESET session_replication_role;

  RETURN affected;
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_template_authorization(text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.revoke_template_authorization(text, text)
  TO authenticated;

COMMENT ON FUNCTION public.revoke_template_authorization(text, text) IS
  'Founder-initiated revoke (Art. 7(3) "as easily withdrawable as given"). '
  'Also called auto-revoke-side-effect from the isTemplateAuthorized '
  'predicate on quota/expired detection so the scope-grants UI does '
  'not display lying rows.';

-- ============================================================================
-- (g) anonymise_template_authorizations RPC — Art-17 cascade
--     Sibling pattern to mig 051 §(h) anonymise_action_sends. Called by
--     server/account-delete.ts BETWEEN anonymise_action_sends and
--     anonymise_scope_grants. The ordering is SEMANTIC, not FK-driven:
--     dsr_erasure reason MUST be set on these CHILD rows BEFORE the
--     parent scope_grant's user_id is nulled — otherwise Art. 5(2)
--     attribution breaks. ON DELETE RESTRICT on grant_id is a separate
--     guarantee (rejects scope_grant DELETE while this row exists);
--     anonymise_* is UPDATE, so the RESTRICT does not fire.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.anonymise_template_authorizations(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  affected integer;
BEGIN
  -- Authorisation (mig 051 precedent):
  --   * Service-role callers (account-delete.ts) — auth.uid() is NULL
  --     and current_user is one of (service_role, postgres in local dev).
  --   * Self-DSAR callers — auth.uid() resolves to the same id as p_user_id.
  -- NOTE: current_user check is gated by auth.uid() IS NULL (server-role
  -- routing only). It is NOT used inside the WORM trigger and therefore
  -- not affected by learning 2026-05-18.
  IF auth.uid() IS NULL THEN
    IF current_user NOT IN ('service_role', 'postgres') THEN
      RAISE EXCEPTION 'anonymise_template_authorizations: caller not authorised'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    IF auth.uid() <> p_user_id THEN
      RAISE EXCEPTION 'anonymise_template_authorizations: self-call only for authenticated callers'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- session_replication_role='replica' bypasses the pure-reject WORM
  -- trigger for the scope of this transaction.
  SET LOCAL session_replication_role = 'replica';
  UPDATE public.template_authorizations
     SET founder_id        = NULL,
         revoked_at        = COALESCE(revoked_at, now()),
         revocation_reason = COALESCE(revocation_reason, 'dsr_erasure')
   WHERE founder_id = p_user_id;
  GET DIAGNOSTICS affected = ROW_COUNT;
  RESET session_replication_role;

  RETURN affected;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_template_authorizations(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_template_authorizations(uuid)
  TO service_role;
-- authenticated grant + self-call guard above lets the user-initiated
-- DSAR flow call the RPC directly without bouncing through a service-
-- role endpoint (mig 051 §(h) precedent).
GRANT EXECUTE ON FUNCTION public.anonymise_template_authorizations(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.anonymise_template_authorizations(uuid) IS
  'Art. 17 erasure: zeros founder_id and sets revocation_reason=dsr_erasure '
  '(preserving any prior reason) on template_authorizations rows for the '
  'given founder. Called by account-delete.ts BETWEEN anonymise_action_sends '
  'and anonymise_scope_grants per semantic cascade ordering (PR-I §Phase 8).';
