-- 084_byok_delegation_withdrawals.sql
-- BYOK Delegation Consent Enforcement (#4625; parent #4232). Adds the
-- consent-WITHDRAWAL path required by GDPR Art. 7(3) ("as easy to
-- withdraw as to give") and the in-flight billing stop.
--
-- LAWFUL_BASIS: Art. 7(3) consent withdrawal evidence (append-only WORM,
--   the Art. 30 record of a grantee revoking their joint-controllership
--   consent). Distinct from the grantor-revoke audit on byok_delegations.
-- RETENTION: 7 years (matches byok_delegation_acceptances mig 074).
--
-- DESIGN (revised after plan-review P0 + deepen P0/P1):
--   * Withdrawal is GATE-SIDE, not revoke-side. The withdraw RPC writes
--     ONLY a withdrawals WORM row; it does NOT set byok_delegations
--     .revoked_at — the 064 WORM trigger (064:312) requires revoked_at +
--     revoked_by_user_id + revocation_reason to flip together, and the
--     revocation_reason CHECK enum (064:95) has no 'consent_withdrawn'
--     value, so a revoked_at-only write aborts. Gate-side is also
--     NON-TERMINAL (re-accepting reactivates — Art. 7(3)).
--   * resolve_byok_key_owner gains a second clause: NOT EXISTS(withdrawal
--     newer than the latest current-version acceptance). Version-agnostic
--     inner max + COALESCE + `>=` (deepen P0): a version bump leaves
--     max(current-version accepted_at) NULL → `> NULL` would fail OPEN;
--     COALESCE(...,w.withdrawn_at) makes a withdrawal-with-no-acceptance
--     unconditionally newer, and `>=` wins equal-timestamp ties.
--   * check_and_record_byok_delegation_use gains a PER-TURN consent
--     re-gate (deepen architecture P1): a mid-run withdrawal stops
--     in-flight billing within one turn and DEBITS THE GRANTEE — without
--     it the resolver gate alone leaves in-flight billing unbounded
--     (ADR-040 threshold = unauthorized invoice).
--   * NO UNIQUE(user_id, delegation_id): append-only event log
--     (withdraw → re-accept → withdraw records multiple rows) AND a UNIQUE
--     breaks Art. 17 anonymise (two rows collapsing to (NULL, delegation_id)
--     collide → abort deleteUser — the AC14 regression).
--   * user_id is NULLABLE (unlike mig 074): the Art. 17 anonymise UPDATE
--     sets user_id = NULL, which a NOT NULL column would reject.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every SECURITY
-- DEFINER fn pins SET search_path = public, pg_temp (public first).
-- Per 2026-05-06-supabase-default-privileges-defeat-revoke-from-public:
-- Supabase's ALTER DEFAULT PRIVILEGES grants EXECUTE to anon/authenticated/
-- service_role on every new function — the explicit named-role REVOKE on
-- each SECURITY DEFINER fn below is load-bearing (AC8: no widened EXECUTE).

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.byok_delegations') IS NULL THEN
    RAISE EXCEPTION '084: public.byok_delegations must exist (run 064 first)';
  END IF;
  IF to_regclass('public.byok_delegation_acceptances') IS NULL THEN
    RAISE EXCEPTION '084: public.byok_delegation_acceptances must exist (run 074 first)';
  END IF;
  IF to_regclass('public.current_byok_side_letter_version'::text) IS NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_proc WHERE proname = 'current_byok_side_letter_version'
     ) THEN
    RAISE EXCEPTION '084: public.current_byok_side_letter_version() must exist (run 083 first)';
  END IF;
END $$;

-- =====================================================================
-- 1. byok_delegation_withdrawals — append-only WORM consent-withdrawal log
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.byok_delegation_withdrawals (
  id              uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  -- NULLABLE (diverges from mig 074's NOT NULL): the Art. 17 anonymise
  -- UPDATE sets user_id = NULL; a NOT NULL column would reject it (AC14).
  user_id         uuid         NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  delegation_id   uuid         NOT NULL REFERENCES public.byok_delegations(id) ON DELETE RESTRICT,
  withdrawn_at    timestamptz  NOT NULL DEFAULT now(),
  side_letter_version text     NOT NULL CHECK (length(side_letter_version) BETWEEN 1 AND 32),
  ip_hash         text         NULL CHECK (ip_hash IS NULL OR length(ip_hash) BETWEEN 1 AND 128),
  user_agent      text         NULL CHECK (user_agent IS NULL OR length(user_agent) BETWEEN 1 AND 512),
  retention_until timestamptz  NOT NULL DEFAULT (now() + interval '7 years'),
  created_at      timestamptz  NOT NULL DEFAULT now()
  -- NO UNIQUE(user_id, delegation_id) — see header (non-terminal + Art. 17).
);

CREATE INDEX IF NOT EXISTS byok_delegation_withdrawals_user_idx
  ON public.byok_delegation_withdrawals (user_id, withdrawn_at DESC);

-- Hot path for the resolver's NOT EXISTS clause + the cap re-gate.
CREATE INDEX IF NOT EXISTS byok_delegation_withdrawals_delegation_idx
  ON public.byok_delegation_withdrawals (delegation_id, withdrawn_at DESC);

ALTER TABLE public.byok_delegation_withdrawals ENABLE ROW LEVEL SECURITY;

CREATE POLICY byok_delegation_withdrawals_select
  ON public.byok_delegation_withdrawals FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Defense-in-depth: even with the GRANT below, a direct (non-DEFINER)
-- insert can only forge a withdrawal for a delegation the caller is the
-- grantee of.
CREATE POLICY byok_delegation_withdrawals_insert
  ON public.byok_delegation_withdrawals FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND delegation_id IN (
      SELECT id FROM public.byok_delegations WHERE grantee_user_id = auth.uid()
    )
  );

REVOKE INSERT, UPDATE, DELETE ON public.byok_delegation_withdrawals FROM PUBLIC, anon;
GRANT INSERT, SELECT ON public.byok_delegation_withdrawals TO authenticated;

COMMENT ON TABLE public.byok_delegation_withdrawals IS
  'Append-only WORM ledger of BYOK delegation consent withdrawals (GDPR '
  'Art. 7(3) demonstrability). NO UNIQUE — non-terminal (withdraw→re-accept'
  '→withdraw) + Art. 17 anonymise multi-row safety. user_id NULLABLE for '
  'the anonymise-to-NULL path. Gate-side: blocks new leases at '
  'resolve_byok_key_owner and stops in-flight billing at '
  'check_and_record_byok_delegation_use. Does NOT set byok_delegations'
  '.revoked_at. RLS: grantee SELECT/INSERT own rows. user_id ON DELETE '
  'RESTRICT — account-delete cascade MUST call '
  'anonymise_byok_delegation_withdrawals BEFORE auth.admin.deleteUser.';

-- =====================================================================
-- 2. WORM trigger — append-only except the Art. 17 anonymise flow
-- =====================================================================
-- Mirrors mig 074: bypass requires session_replication_role='replica'
-- AND current_user='service_role' (the anonymise RPC sets the former).

CREATE OR REPLACE FUNCTION public.byok_delegation_withdrawals_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_setting('session_replication_role') = 'replica'
     AND current_user = 'service_role' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'byok_delegation_withdrawals is append-only (WORM)' USING ERRCODE = 'P0001';
END;
$$;

REVOKE ALL ON FUNCTION public.byok_delegation_withdrawals_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS byok_delegation_withdrawals_no_update ON public.byok_delegation_withdrawals;
CREATE TRIGGER byok_delegation_withdrawals_no_update
  BEFORE UPDATE ON public.byok_delegation_withdrawals
  FOR EACH ROW EXECUTE FUNCTION public.byok_delegation_withdrawals_no_mutate();

DROP TRIGGER IF EXISTS byok_delegation_withdrawals_no_delete ON public.byok_delegation_withdrawals;
CREATE TRIGGER byok_delegation_withdrawals_no_delete
  BEFORE DELETE ON public.byok_delegation_withdrawals
  FOR EACH ROW EXECUTE FUNCTION public.byok_delegation_withdrawals_no_mutate();

-- =====================================================================
-- 3. withdraw_byok_delegation_consent — grantee-only, derives auth.uid()
-- =====================================================================
-- NO p_user_id parameter (SS-F3 harvest vector). Invoked AS the user
-- (GRANT authenticated, like revoke_byok_delegation 064:572). Idempotent
-- in effect (append-only; multiple rows are legitimate per the no-UNIQUE
-- design — re-withdrawing is a no-op for the gate).

CREATE OR REPLACE FUNCTION public.withdraw_byok_delegation_consent(
  p_delegation_id uuid
) RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_found  boolean;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'withdraw_byok_delegation_consent: no authenticated caller'
      USING ERRCODE = '42501';
  END IF;
  IF p_delegation_id IS NULL THEN
    RAISE EXCEPTION 'withdraw_byok_delegation_consent: p_delegation_id is required'
      USING ERRCODE = '22023';
  END IF;

  -- Grantee-only: the caller MUST be the grantee of this delegation.
  -- Closes the cross-tenant forge (a non-grantee naming someone else's
  -- delegation id).
  SELECT true INTO v_found
    FROM public.byok_delegations
   WHERE id = p_delegation_id
     AND grantee_user_id = v_caller;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'withdraw_byok_delegation_consent: delegation % not found for caller (grantee-only)', p_delegation_id
      USING ERRCODE = 'P0002';
  END IF;

  -- WORM append. Does NOT touch byok_delegations (see header).
  INSERT INTO public.byok_delegation_withdrawals (
    user_id, delegation_id, side_letter_version
  ) VALUES (
    v_caller, p_delegation_id, public.current_byok_side_letter_version()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.withdraw_byok_delegation_consent(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_byok_delegation_consent(uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.withdraw_byok_delegation_consent(uuid) IS
  'Records a gate-side BYOK delegation consent withdrawal (Art. 7(3)). '
  'Grantee-only (derives auth.uid(); NO p_user_id — SS-F3). Writes a '
  'byok_delegation_withdrawals WORM row; does NOT set byok_delegations'
  '.revoked_at. Non-terminal — re-accepting reactivates at the resolver.';

-- =====================================================================
-- 4. anonymise_byok_delegation_withdrawals — Art. 17 cascade hook
-- =====================================================================
-- Called from account-delete.ts BEFORE auth.admin.deleteUser() per the
-- ON DELETE RESTRICT FK ordering. Idempotent. NO UNIQUE on the table, so
-- anonymising ≥2 rows for the same delegation cannot collide (AC14).

CREATE OR REPLACE FUNCTION public.anonymise_byok_delegation_withdrawals(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  SET LOCAL session_replication_role = 'replica';

  UPDATE public.byok_delegation_withdrawals
     SET user_id    = NULL,
         ip_hash    = NULL,
         user_agent = NULL
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_byok_delegation_withdrawals(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_byok_delegation_withdrawals(uuid)
  TO service_role;

COMMENT ON FUNCTION public.anonymise_byok_delegation_withdrawals(uuid) IS
  'Art. 17 cascade hook: NULLs user_id, ip_hash, user_agent on '
  'byok_delegation_withdrawals rows for the given user. Idempotent. Called '
  'from account-delete.ts BEFORE auth.admin.deleteUser() per ON DELETE '
  'RESTRICT FK ordering. session_replication_role=replica bypasses WORM.';

-- =====================================================================
-- 5. audit_byok_use.attribution_shift_reason — add consent_withdrawn
-- =====================================================================
-- The inline CHECK from mig 064 (ADD COLUMN ... CHECK) is auto-named
-- audit_byok_use_attribution_shift_reason_check. Extend the enum so the
-- per-turn re-gate can write the consent_withdrawn attribution row.

ALTER TABLE public.audit_byok_use
  DROP CONSTRAINT IF EXISTS audit_byok_use_attribution_shift_reason_check;
ALTER TABLE public.audit_byok_use
  ADD CONSTRAINT audit_byok_use_attribution_shift_reason_check
  CHECK (
    attribution_shift_reason IS NULL
    OR attribution_shift_reason IN ('revoked_post_grace','expired','consent_withdrawn')
  );

-- =====================================================================
-- 6. resolve_byok_key_owner — add the withdrawal clause (keeps 083 gate)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.resolve_byok_key_owner(
  p_caller_user_id uuid,
  p_workspace_id   uuid
) RETURNS TABLE (
  key_owner_user_id uuid,
  delegation_id     uuid
)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'resolve_byok_key_owner: p_caller_user_id is NULL'
      USING ERRCODE = '22023';
  END IF;

  -- Own-key precedence (solo behavior preserved bit-for-bit — AC6).
  IF EXISTS (
    SELECT 1 FROM public.api_keys WHERE user_id = p_caller_user_id
  ) THEN
    key_owner_user_id := p_caller_user_id;
    delegation_id     := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  RETURN QUERY
    SELECT bd.grantor_user_id, bd.id
      FROM public.byok_delegations bd
     WHERE bd.grantee_user_id = p_caller_user_id
       AND bd.workspace_id    = p_workspace_id
       AND bd.revoked_at IS NULL
       AND (bd.expires_at IS NULL OR bd.expires_at > clock_timestamp())
       -- Gate 1 (mig 083): a current-version acceptance must exist.
       AND EXISTS (
         SELECT 1 FROM public.byok_delegation_acceptances a
          WHERE a.delegation_id = bd.id
            AND a.user_id       = bd.grantee_user_id
            AND a.side_letter_version = public.current_byok_side_letter_version()
       )
       -- Gate 2 (mig 084): no withdrawal that post-dates the latest
       -- current-version acceptance. Version-agnostic: COALESCE makes a
       -- withdrawal-with-no-acceptance unconditionally newer (no NULL
       -- fail-open after a version bump); `>=` wins equal-timestamp ties.
       AND NOT EXISTS (
         SELECT 1 FROM public.byok_delegation_withdrawals w
          WHERE w.delegation_id = bd.id
            AND w.user_id       = bd.grantee_user_id
            AND w.withdrawn_at >= COALESCE(
              (SELECT max(a2.accepted_at)
                 FROM public.byok_delegation_acceptances a2
                WHERE a2.delegation_id = bd.id
                  AND a2.user_id       = bd.grantee_user_id),
              w.withdrawn_at)
       )
     ORDER BY bd.created_at DESC
     LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_byok_key_owner(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_byok_key_owner(uuid, uuid)
  TO service_role;

-- =====================================================================
-- 7. check_and_record_byok_delegation_use — per-turn consent re-gate
-- =====================================================================
-- Identical to mig 064:648 EXCEPT for the new consent re-gate inserted
-- right after the grace check. The delegation row is already FOR UPDATE
-- locked, so the re-gate is serialized with concurrent callers.

CREATE OR REPLACE FUNCTION public.check_and_record_byok_delegation_use(
  p_delegation_id    uuid,
  p_invocation_id    uuid,
  p_token_count      int,
  p_unit_cost_cents  int,
  p_caller_user_id   uuid,
  p_agent_role       text
) RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_row             public.byok_delegations%ROWTYPE;
  v_this_cost       int := p_token_count * p_unit_cost_cents;
  v_hourly_spent    int;
  v_daily_spent     int;
BEGIN
  IF p_delegation_id IS NULL OR p_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'check_and_record_byok_delegation_use: p_delegation_id and p_caller_user_id are required'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_row
    FROM public.byok_delegations
   WHERE id = p_delegation_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'check_and_record_byok_delegation_use: delegation % not found', p_delegation_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_row.grantor_user_id IS NULL OR v_row.workspace_id IS NULL THEN
    RAISE EXCEPTION 'byok_delegations:anonymised'
      USING ERRCODE = 'P0001';
  END IF;

  -- Grace check (clock_timestamp() not now()): revoke past 60s grace.
  IF v_row.revoked_at IS NOT NULL
     AND clock_timestamp() > v_row.revoked_at + interval '60 seconds' THEN
    INSERT INTO public.audit_byok_use (
      invocation_id, founder_id, workspace_id, agent_role,
      token_count, unit_cost_cents, delegation_id, attribution_shift_reason
    ) VALUES (
      p_invocation_id, p_caller_user_id, v_row.workspace_id, p_agent_role,
      p_token_count, p_unit_cost_cents, p_delegation_id, 'revoked_post_grace'
    )
    ON CONFLICT (invocation_id) DO NOTHING;
    RAISE EXCEPTION 'byok_delegations:revoked_post_grace'
      USING ERRCODE = 'P0001';
  END IF;

  -- Per-turn consent re-gate (#4625 deepen P1): a mid-run withdrawal that
  -- post-dates the latest current-version acceptance stops in-flight
  -- billing within ONE turn and DEBITS THE GRANTEE (founder_id =
  -- p_caller_user_id, the grantee). Mirrors the version-agnostic resolver
  -- predicate. Without this, a withdrawal mid-run has zero billing effect
  -- — the grantor keeps paying until the run ends (ADR-040 threshold =
  -- unauthorized invoice).
  IF EXISTS (
    SELECT 1 FROM public.byok_delegation_withdrawals w
     WHERE w.delegation_id = p_delegation_id
       AND w.user_id       = v_row.grantee_user_id
       AND w.withdrawn_at >= COALESCE(
         (SELECT max(a.accepted_at)
            FROM public.byok_delegation_acceptances a
           WHERE a.delegation_id = p_delegation_id
             AND a.user_id       = v_row.grantee_user_id),
         w.withdrawn_at)
  ) THEN
    INSERT INTO public.audit_byok_use (
      invocation_id, founder_id, workspace_id, agent_role,
      token_count, unit_cost_cents, delegation_id, attribution_shift_reason
    ) VALUES (
      p_invocation_id, p_caller_user_id, v_row.workspace_id, p_agent_role,
      p_token_count, p_unit_cost_cents, p_delegation_id, 'consent_withdrawn'
    )
    ON CONFLICT (invocation_id) DO NOTHING;
    RAISE EXCEPTION 'byok_delegations:consent_withdrawn'
      USING ERRCODE = 'P0001';
  END IF;

  -- Expired check.
  IF v_row.expires_at IS NOT NULL
     AND clock_timestamp() > v_row.expires_at THEN
    INSERT INTO public.audit_byok_use (
      invocation_id, founder_id, workspace_id, agent_role,
      token_count, unit_cost_cents, delegation_id, attribution_shift_reason
    ) VALUES (
      p_invocation_id, p_caller_user_id, v_row.workspace_id, p_agent_role,
      p_token_count, p_unit_cost_cents, p_delegation_id, 'expired'
    )
    ON CONFLICT (invocation_id) DO NOTHING;
    RAISE EXCEPTION 'byok_delegations:expired'
      USING ERRCODE = 'P0001';
  END IF;

  -- Hourly cap SUM (rolling 1h).
  SELECT COALESCE(SUM(au.token_count * au.unit_cost_cents), 0)::int
    INTO v_hourly_spent
    FROM public.audit_byok_use au
   WHERE au.delegation_id = p_delegation_id
     AND au.ts > clock_timestamp() - interval '1 hour';

  IF v_hourly_spent + v_this_cost > v_row.hourly_usd_cap_cents THEN
    RAISE EXCEPTION 'byok_delegations:hourly_cap_exceeded'
      USING ERRCODE = 'P0001',
            DETAIL = format('hourly cap %s cents, spent %s, attempted +%s',
                            v_row.hourly_usd_cap_cents, v_hourly_spent, v_this_cost);
  END IF;

  -- Daily cap SUM (rolling 24h).
  SELECT COALESCE(SUM(au.token_count * au.unit_cost_cents), 0)::int
    INTO v_daily_spent
    FROM public.audit_byok_use au
   WHERE au.delegation_id = p_delegation_id
     AND au.ts > clock_timestamp() - interval '24 hours';

  IF v_daily_spent + v_this_cost > v_row.daily_usd_cap_cents THEN
    RAISE EXCEPTION 'byok_delegations:daily_cap_exceeded'
      USING ERRCODE = 'P0001',
            DETAIL = format('daily cap %s cents, spent %s, attempted +%s',
                            v_row.daily_usd_cap_cents, v_daily_spent, v_this_cost);
  END IF;

  -- Pass: write audit row with grantor attribution (normal accounting).
  INSERT INTO public.audit_byok_use (
    invocation_id, founder_id, workspace_id, agent_role,
    token_count, unit_cost_cents, delegation_id, attribution_shift_reason
  ) VALUES (
    p_invocation_id, v_row.grantor_user_id, v_row.workspace_id, p_agent_role,
    p_token_count, p_unit_cost_cents, p_delegation_id, NULL
  )
  ON CONFLICT (invocation_id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.check_and_record_byok_delegation_use(uuid, uuid, int, int, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_record_byok_delegation_use(uuid, uuid, int, int, uuid, text)
  TO service_role;

COMMIT;

-- Tracking row written in the same transaction by run-migrations.sh
-- (canonical) or the Doppler+pg fallback applier.
