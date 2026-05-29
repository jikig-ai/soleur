-- 074_byok_delegation_acceptances.sql
-- BYOK Delegations PR-B (#4232). Consent-capture table for the Delegation
-- Consent Side Letter. One row per (user_id, delegation_id) pair — grantee
-- accepts the Side Letter before the delegation becomes active in the UI.
--
-- LAWFUL_BASIS (corrected #4625 — the original "Art. 6(1)(b) contract —
--   grantee consents" conflated a contractual-necessity basis with a
--   consent act; the two are distinct and this table evidences the latter):
--   * Art. 6(1)(a) consent — the grantee's recorded acceptance row IS the
--     lawful basis for processing the grantee's prompt content under the
--     grantor's key; this table is the Art. 7(1) demonstrability evidence
--     of that consent (and Art. 7(3) withdrawal is recorded separately in
--     byok_delegation_withdrawals, mig 084).
--   * Art. 26 joint controllership — the delegation places grantor and
--     grantee in a joint-controller arrangement; the versioned Delegation
--     Consent Side Letter text IS the Art. 26 arrangement (responsibility
--     allocation for DSARs, security, transparency), and the stored
--     side_letter_version pins which version the grantee accepted.
--   The byok_delegations row's Art. 6(1)(b) contract basis (mig 064) governs
--   the grantor↔grantee FUNDING relationship; it does NOT substitute for the
--   grantee's Art. 6(1)(a) consent recorded here.
-- RETENTION: 7 years (financial audit, matching tc_acceptances).
--
-- Pattern precedent: 044_add_tc_acceptances_ledger.sql (WORM table +
-- anonymise RPC + ON DELETE RESTRICT).
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every SECURITY
-- DEFINER fn pins SET search_path = public, pg_temp.
-- Per 2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md:
-- explicit REVOKE from PUBLIC + anon + authenticated on trigger fn;
-- explicit GRANT to authenticated on table (grantee inserts own row via
-- RLS user_id = auth.uid()).

DO $$ BEGIN
  IF to_regclass('public.users') IS NULL THEN
    RAISE EXCEPTION '074: public.users must exist before this migration';
  END IF;
  IF to_regclass('public.byok_delegations') IS NULL THEN
    RAISE EXCEPTION '074: public.byok_delegations must exist before this migration (run 064 first)';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.byok_delegation_acceptances (
  id              uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid         NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  delegation_id   uuid         NOT NULL REFERENCES public.byok_delegations(id) ON DELETE RESTRICT,
  accepted_at     timestamptz  NOT NULL DEFAULT now(),
  side_letter_version text     NOT NULL CHECK (length(side_letter_version) BETWEEN 1 AND 32),
  ip_hash         text         NULL CHECK (ip_hash IS NULL OR length(ip_hash) BETWEEN 1 AND 128),
  user_agent      text         NULL CHECK (user_agent IS NULL OR length(user_agent) BETWEEN 1 AND 512),
  retention_until timestamptz  NOT NULL DEFAULT (now() + interval '7 years'),
  created_at      timestamptz  NOT NULL DEFAULT now(),
  UNIQUE (user_id, delegation_id)
);

ALTER TABLE public.byok_delegation_acceptances ENABLE ROW LEVEL SECURITY;

CREATE POLICY byok_delegation_acceptances_select
  ON public.byok_delegation_acceptances FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY byok_delegation_acceptances_insert
  ON public.byok_delegation_acceptances FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS byok_delegation_acceptances_user_idx
  ON public.byok_delegation_acceptances (user_id, accepted_at DESC);

CREATE INDEX IF NOT EXISTS byok_delegation_acceptances_delegation_idx
  ON public.byok_delegation_acceptances (delegation_id);

REVOKE INSERT, UPDATE, DELETE ON public.byok_delegation_acceptances FROM PUBLIC, anon;
GRANT INSERT, SELECT ON public.byok_delegation_acceptances TO authenticated;

COMMENT ON TABLE public.byok_delegation_acceptances IS
  'Append-only WORM ledger of Delegation Consent Side Letter acceptances '
  '(GDPR Art. 7(1) demonstrability). One row per (user_id, delegation_id). '
  'UPDATE rejected unconditionally; DELETE rejected except via '
  'anonymise_byok_delegation_acceptances (Art. 17). RLS: authenticated '
  'users can SELECT and INSERT their own rows. user_id ON DELETE RESTRICT: '
  'account-delete cascade MUST call anonymise_byok_delegation_acceptances '
  'BEFORE auth.admin.deleteUser.';

-- ============================================================================
-- WORM trigger: byok_delegation_acceptances is append-only EXCEPT during
-- the Art. 17 anonymisation flow.
--
-- Bypass requires ALL of:
--   (a) session_replication_role = 'replica'
--   (b) current_user = 'service_role'
--
-- Pattern: mig 044 tc_acceptances_no_mutate but using session_replication_role
-- instead of a custom GUC (matching mig 064's anonymise_byok_delegations
-- approach for the acceptance table since there are no legitimate mutation
-- shapes — pure append-only).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.byok_delegation_acceptances_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_setting('session_replication_role') = 'replica'
     AND current_user = 'service_role' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  RAISE EXCEPTION 'byok_delegation_acceptances is append-only (WORM)' USING ERRCODE = 'P0001';
END;
$$;

REVOKE ALL ON FUNCTION public.byok_delegation_acceptances_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS byok_delegation_acceptances_no_update ON public.byok_delegation_acceptances;
CREATE TRIGGER byok_delegation_acceptances_no_update
  BEFORE UPDATE ON public.byok_delegation_acceptances
  FOR EACH ROW
  EXECUTE FUNCTION public.byok_delegation_acceptances_no_mutate();

DROP TRIGGER IF EXISTS byok_delegation_acceptances_no_delete ON public.byok_delegation_acceptances;
CREATE TRIGGER byok_delegation_acceptances_no_delete
  BEFORE DELETE ON public.byok_delegation_acceptances
  FOR EACH ROW
  EXECUTE FUNCTION public.byok_delegation_acceptances_no_mutate();

COMMENT ON FUNCTION public.byok_delegation_acceptances_no_mutate() IS
  'WORM gate for byok_delegation_acceptances. Bypass: session_replication_role '
  '= replica + service_role (Art. 17 anonymise flow only). UPDATE attempts '
  'NEVER bypass outside the anonymise RPC.';

-- ============================================================================
-- anonymise_byok_delegation_acceptances — Art. 17 cascade hook.
--
-- Called from account-delete.ts step 5.11 BEFORE auth.admin.deleteUser()
-- per ON DELETE RESTRICT FK ordering. Idempotent.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.anonymise_byok_delegation_acceptances(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  SET LOCAL session_replication_role = 'replica';

  UPDATE public.byok_delegation_acceptances
     SET user_id    = NULL,
         ip_hash    = NULL,
         user_agent = NULL
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_byok_delegation_acceptances(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_byok_delegation_acceptances(uuid)
  TO service_role;

COMMENT ON FUNCTION public.anonymise_byok_delegation_acceptances(uuid) IS
  'Art. 17 cascade hook: anonymises user_id, ip_hash, user_agent on '
  'byok_delegation_acceptances rows for the given user. Idempotent. Called '
  'from account-delete.ts step 5.11 BEFORE auth.admin.deleteUser() per ON '
  'DELETE RESTRICT FK ordering. Uses session_replication_role=replica to '
  'bypass the WORM trigger.';
