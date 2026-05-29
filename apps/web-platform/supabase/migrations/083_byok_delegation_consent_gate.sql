-- 083_byok_delegation_consent_gate.sql
-- BYOK Delegation Consent Enforcement (#4625; parent #4232).
--
-- Makes recorded in-app consent the source of truth that gates the BYOK
-- key lease. PR-B (#4508, mig 074) shipped the consent CAPTURE layer
-- (byok_delegation_acceptances). The gap: resolve_byok_key_owner (mig
-- 064:583) activated a delegation on `revoked_at IS NULL AND expires_at >
-- clock_timestamp()` WITHOUT checking acceptance, so a grantee's prompts
-- could be processed under the grantor's key (with the grantor seeing
-- itemized cost telemetry) BEFORE the grantee consented — Art. 26 joint-
-- controllership / processing-without-consent exposure.
--
-- Design: gate IN SQL, not TS. Adding `AND EXISTS(current-version
-- acceptance)` inside the resolver keeps the atomic-MVCC TOCTOU guarantee
-- (064 Decision #8), needs ZERO change to the TS lease call sites, and is
-- automatically scoped to the delegation path only — direct
-- runWithByokLease solo-key leases never hit the resolver, so own-key
-- users are unaffected (the api_keys short-circuit runs first).
--
-- Canonical version is server-owned: current_byok_side_letter_version()
-- is the single SQL source of truth and MUST equal the TS constant
-- BYOK_SIDE_LETTER_VERSION (apps/web-platform/server/byok-side-letter.ts).
-- The AC4 parity test (test/byok-side-letter-version-parity.test.ts) is a
-- CI gate. A version bump fail-closes every stale acceptance at the gate.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: SECURITY DEFINER fn
-- pins SET search_path = public, pg_temp (public first).
-- Per 2026-05-06-supabase-default-privileges-defeat-revoke-from-public:
-- Supabase's ALTER DEFAULT PRIVILEGES grants EXECUTE to anon/authenticated/
-- service_role on every new function, so the explicit named-role REVOKE
-- below is load-bearing (AC8: no widened EXECUTE survives). The replaced
-- resolver re-asserts its REVOKE/GRANT in the same migration.

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.byok_delegations') IS NULL THEN
    RAISE EXCEPTION '083: public.byok_delegations must exist (run 064 first)';
  END IF;
  IF to_regclass('public.byok_delegation_acceptances') IS NULL THEN
    RAISE EXCEPTION '083: public.byok_delegation_acceptances must exist (run 074 first)';
  END IF;
END $$;

-- =====================================================================
-- 1. current_byok_side_letter_version() — SQL source of truth
-- =====================================================================
--
-- IMMUTABLE function-literal (NOT a table): the legal version pin is a
-- reviewed-migration artifact, not runtime-mutable data. SECURITY INVOKER
-- because it reads no tables — no DEFINER needed. The SECURITY DEFINER
-- gate below reads it via the schema-qualified call (a TS const is
-- unreadable from SQL). search_path pinned defensively.

CREATE OR REPLACE FUNCTION public.current_byok_side_letter_version()
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SECURITY INVOKER
  SET search_path = public, pg_temp
AS $$
  SELECT '1.0.0'::text;
$$;

REVOKE ALL ON FUNCTION public.current_byok_side_letter_version()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.current_byok_side_letter_version()
  TO authenticated, service_role;

COMMENT ON FUNCTION public.current_byok_side_letter_version() IS
  'Single SQL source of truth for the canonical Delegation Consent Side '
  'Letter version. MUST equal TS BYOK_SIDE_LETTER_VERSION (CI parity gate '
  '#4625 AC4). Read by resolve_byok_key_owner''s acceptance gate; a bump '
  'fail-closes every stale-version acceptance.';

-- =====================================================================
-- 2. resolve_byok_key_owner — add the current-version acceptance gate
-- =====================================================================
--
-- Identical to mig 064:583 EXCEPT the delegation RETURN QUERY now carries
-- `AND EXISTS(current-version acceptance)`. Own-key short-circuit, the
-- explicit p_workspace_id (DIG F3), and clock_timestamp() expiry (SS F1)
-- are preserved bit-for-bit.

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

  -- Active delegation in the supplied workspace, GATED on a current-
  -- version acceptance by the grantee. No acceptance (or a stale-version
  -- one) ⇒ empty result ⇒ the TS lease body raises MissingByokKeyError
  -- (fail-closed; distinct from ByokDelegationRevokedError).
  RETURN QUERY
    SELECT bd.grantor_user_id, bd.id
      FROM public.byok_delegations bd
     WHERE bd.grantee_user_id = p_caller_user_id
       AND bd.workspace_id    = p_workspace_id
       AND bd.revoked_at IS NULL
       AND (bd.expires_at IS NULL OR bd.expires_at > clock_timestamp())
       AND EXISTS (
         SELECT 1 FROM public.byok_delegation_acceptances a
          WHERE a.delegation_id = bd.id
            AND a.user_id       = bd.grantee_user_id
            AND a.side_letter_version = public.current_byok_side_letter_version()
       )
     ORDER BY bd.created_at DESC
     LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_byok_key_owner(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_byok_key_owner(uuid, uuid)
  TO service_role;

COMMIT;

-- Tracking row written in the same transaction by run-migrations.sh
-- (canonical) or the Doppler+pg fallback applier.
