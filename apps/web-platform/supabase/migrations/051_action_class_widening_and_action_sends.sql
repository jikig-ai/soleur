-- 051_action_class_widening_and_action_sends.sql
-- PR-H (#4077) — Trust-tier external-classes wiring.
--
-- Composite migration:
--   (a) scope_grants.tier CHECK widened to admit 'auto_with_digest'
--   (b) scope_grants DB CHECK enum-absence regex on action_class
--       (defense-in-depth per ADR-034 §2)
--   (c) messages.action_class column + bounded backfill for PR-F drafts
--   (d) action_sends WORM table with shape CHECKs + DB CHECK enum-absence
--   (e) pure-reject UPDATE/DELETE trigger (mig 037 pattern; NO role-check
--       bypass per learning 2026-05-18-worm-trigger-bypass-role-check-fails-
--       under-postgrest-routing.md)
--   (f) owner-select + owner-insert RLS (no FOR ALL USING per learning
--       2026-04-18-rls-for-all-using)
--   (g) covering index for future digest aggregator + audit viewer
--   (h) anonymise_action_sends(uuid) SECURITY DEFINER RPC (Art-17 cascade;
--       sibling pattern from mig 048 anonymise_scope_grants but bypasses
--       the pure-reject trigger via SET LOCAL session_replication_role)
--   (i) grant_action_class RPC re-create to accept 'auto_with_digest'
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every SECURITY DEFINER
-- function pins SET search_path = public, pg_temp and qualifies every
-- relation as public.<table>.
--
-- Per 2026-04-18-supabase-migration-concurrently-forbidden: NO CREATE INDEX
-- CONCURRENTLY (Supabase wraps each migration in a transaction).
--
-- Per Kieran P1-4: NO outer BEGIN/COMMIT (Supabase runner already wraps).

-- ============================================================================
-- (a) Widen scope_grants.tier CHECK to admit auto_with_digest
-- ============================================================================
ALTER TABLE public.scope_grants
  DROP CONSTRAINT IF EXISTS scope_grants_tier_check;
ALTER TABLE public.scope_grants
  ADD CONSTRAINT scope_grants_tier_check
  CHECK (tier IN ('auto', 'draft_one_click', 'approve_every_time', 'auto_with_digest'));

-- ============================================================================
-- (b) DB CHECK enum-absence on scope_grants.action_class (defense-in-depth)
--     ADR-034 §2 / hr-menu-option-ack-not-prod-write-auth. Belt-and-suspenders
--     against indirect routes (RPC-from-JSON-payload, future config imports)
--     that the TS layer can't see.
-- ============================================================================
ALTER TABLE public.scope_grants
  DROP CONSTRAINT IF EXISTS scope_grants_action_class_not_locked;
ALTER TABLE public.scope_grants
  ADD CONSTRAINT scope_grants_action_class_not_locked
  CHECK (action_class !~ '^(payment|legal|auth)\.');

-- ============================================================================
-- (c) Add messages.action_class + (d) bounded backfill
--     Defensive deploy-timestamp upper bound (Kieran P2-1) so a future
--     CFO producer emitting a different class is not retro-labeled.
-- ============================================================================
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS action_class text NULL;

COMMENT ON COLUMN public.messages.action_class IS
  'Producer-declared action-class literal (PR-H #4077). One of public.ACTION_CLASSES '
  '(see apps/web-platform/server/scope-grants/action-class-map.ts). NULL on legacy '
  'rows; bounded backfill in migration 051 covers PR-F CFO drafts.';

UPDATE public.messages
   SET action_class = 'finance.payment_failed'
 WHERE action_class IS NULL
   AND tier = 'external_brand_critical'
   AND owning_domain = 'cfo'
   AND source = 'stripe'
   AND created_at < '2026-05-19 23:59:59+00'::timestamptz;

-- ============================================================================
-- (d/e/f/g) action_sends WORM table + trigger + RLS + index
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.action_sends (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- NULLABLE to admit Art-17 anonymisation. ON DELETE RESTRICT prevents
  -- accidental user-row deletion before anonymise_action_sends runs.
  user_id                   uuid NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  message_id                uuid NOT NULL REFERENCES public.messages(id),
  action_class              text NOT NULL CHECK (length(action_class) BETWEEN 1 AND 64),
  CONSTRAINT action_sends_action_class_not_locked
    CHECK (action_class !~ '^(payment|legal|auth)\.'),
  tier_at_send              text NOT NULL CHECK (tier_at_send IN (
                              'auto',
                              'draft_one_click',
                              'approve_every_time',
                              'auto_with_digest'
                            )),
  template_hash             text NOT NULL,
  per_send_body_sha256      text NOT NULL,
  recipient_id_hash         text NOT NULL,
  clicked_at                timestamptz NOT NULL DEFAULT now(),
  confirmed_typed           boolean NOT NULL DEFAULT false,
  approval_signature_sha256 text NULL,
  grant_id                  uuid NOT NULL REFERENCES public.scope_grants(id)
);

COMMENT ON TABLE public.action_sends IS
  'Per-send signature record. WORM (append-only). Art. 5(2) accountability evidence '
  '(GDPR). PR-H (#4077). One row per founder click on Send for an external_low_stakes '
  '/ external_brand_critical draft, plus one row per auto_with_digest infra.* action '
  'execution. UPDATE/DELETE rejected by trigger; Art-17 erasure via anonymise_action_sends.';

-- Pure-reject UPDATE/DELETE trigger (mig 037 pattern). FOR EACH STATEMENT
-- per mig 037 — STATEMENT-level is cheaper than ROW-level for a fixed-reject.
CREATE OR REPLACE FUNCTION public.action_sends_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'action_sends is append-only (WORM); % rejected', TG_OP
    USING ERRCODE = 'P0001';
END;
$$;

REVOKE ALL ON FUNCTION public.action_sends_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS action_sends_no_update ON public.action_sends;
CREATE TRIGGER action_sends_no_update
  BEFORE UPDATE ON public.action_sends
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.action_sends_no_mutate();

DROP TRIGGER IF EXISTS action_sends_no_delete ON public.action_sends;
CREATE TRIGGER action_sends_no_delete
  BEFORE DELETE ON public.action_sends
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.action_sends_no_mutate();

-- RLS — owner-select + owner-insert; no FOR ALL USING (learning
-- 2026-04-18-rls-for-all-using-applies-to-writes.md).
ALTER TABLE public.action_sends ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS action_sends_owner_select ON public.action_sends;
CREATE POLICY action_sends_owner_select ON public.action_sends
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS action_sends_owner_insert ON public.action_sends;
CREATE POLICY action_sends_owner_insert ON public.action_sends
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Covering index for digest aggregator (PR-I #4078) + audit viewer hot
-- paths. (user_id, clicked_at DESC) supports "what did founder X do in
-- the last 24h" lookups.
CREATE INDEX IF NOT EXISTS action_sends_user_clicked_idx
  ON public.action_sends (user_id, clicked_at DESC);

-- ============================================================================
-- (h) Art-17 anonymise RPC — called by server/account-delete.ts BEFORE
--     auth.admin.deleteUser (Kieran P1-1; sibling pattern from mig 048
--     anonymise_scope_grants). The pure-reject trigger blocks ordinary
--     UPDATEs even from service-role, so we use SET LOCAL session_replication_role
--     = 'replica' to bypass triggers for the single UPDATE — Postgres-canonical
--     mechanism; scope is the function call, not session-wide.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.anonymise_action_sends(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  affected integer;
BEGIN
  -- Authorisation:
  --   * Service-role callers (account-delete.ts) — auth.uid() is NULL,
  --     current_user = 'service_role' (or 'postgres' in local dev).
  --   * Self-DSAR callers (future founder-initiated path) — auth.uid()
  --     resolves to the same id as p_user_id.
  -- Everyone else is rejected.
  IF auth.uid() IS NULL THEN
    IF current_user NOT IN ('service_role', 'postgres') THEN
      RAISE EXCEPTION 'anonymise_action_sends: caller not authorised'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    IF auth.uid() <> p_user_id THEN
      RAISE EXCEPTION 'anonymise_action_sends: self-call only for authenticated callers'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- session_replication_role='replica' suppresses BEFORE triggers for the
  -- scope of this transaction. Required because action_sends has a pure-
  -- reject UPDATE trigger.
  SET LOCAL session_replication_role = 'replica';
  UPDATE public.action_sends
     SET user_id           = NULL,
         recipient_id_hash = '__anonymised__'
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS affected = ROW_COUNT;
  RESET session_replication_role;

  RETURN affected;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_action_sends(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_action_sends(uuid)
  TO service_role;
-- authenticated grant + self-call guard above lets the user-initiated DSAR
-- flow call the RPC directly without bouncing through a service-role endpoint.
GRANT EXECUTE ON FUNCTION public.anonymise_action_sends(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.anonymise_action_sends(uuid) IS
  'Art. 17 erasure: zeros user_id and recipient_id_hash on action_sends '
  'rows for given founder. Called by account-delete.ts BEFORE '
  'auth.admin.deleteUser. Pattern source: mig 048 anonymise_scope_grants '
  '+ session_replication_role for pure-reject trigger bypass.';

-- ============================================================================
-- (i) grant_action_class RPC re-create to admit the 4th tier value
--     The original mig 048 RPC hardcodes the 3-tier literal list.
--     CREATE OR REPLACE preserves grants per cq-pg-security-definer-search-path-pin-pg-temp.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.grant_action_class(
  p_action_class text,
  p_tier         text
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_founder_id uuid := auth.uid();
  v_grant_id   uuid;
BEGIN
  IF v_founder_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;
  IF p_tier NOT IN ('auto', 'draft_one_click', 'approve_every_time', 'auto_with_digest') THEN
    RAISE EXCEPTION 'invalid tier: %', p_tier USING ERRCODE = '22P02';
  END IF;

  -- Revoke any currently-active grant for this (founder, action_class).
  UPDATE public.scope_grants
     SET revoked_at = now(),
         revoked_reason = 'tier_change'
   WHERE founder_id = v_founder_id
     AND action_class = p_action_class
     AND revoked_at IS NULL;

  INSERT INTO public.scope_grants (founder_id, action_class, tier)
       VALUES (v_founder_id, p_action_class, p_tier)
  RETURNING id INTO v_grant_id;

  RETURN v_grant_id;
END;
$$;

REVOKE ALL ON FUNCTION public.grant_action_class(text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.grant_action_class(text, text)
  TO authenticated;
