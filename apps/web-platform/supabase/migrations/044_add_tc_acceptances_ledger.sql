-- 044_add_tc_acceptances_ledger.sql
-- feat-oauth-tc-consent-3205 — residual audit bundle (PR #3853).
-- Plan: knowledge-base/project/plans/2026-05-15-feat-oauth-tc-consent-residual-audit-plan.md
-- Spec: knowledge-base/project/specs/feat-oauth-tc-consent-3205/spec.md
-- RoPA: knowledge-base/legal/article-30-register.md (Processing Activity — Consent Records)
--
-- Tables:
--   public.tc_acceptances — append-only WORM ledger of per-version
--                           Terms & Conditions acceptances. One row per
--                           (user_id, version) pair. UPDATE always
--                           rejected; DELETE rejected except via the
--                           Art. 17 anonymise RPC.
--
-- RPCs (all SECURITY DEFINER, search_path = public, pg_temp,
-- public.-qualified relations, named-role REVOKE):
--   public.accept_terms(p_user_id uuid, p_version text, p_doc_sha text)
--   public.anonymise_tc_acceptances(p_user_id uuid)
--
-- Schedules: NONE in v1. Art. 5(1)(e) retention sweep deferred per
-- plan-review (simplicity-reviewer): 0 beta users + 7-year window
-- means the cron runs against 0 rows for years. `retention_until`
-- column ships for forward-compat; sweep ships in a follow-on issue
-- tracked at AC21 of the plan.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every SECURITY
-- DEFINER fn pins SET search_path = public, pg_temp (public FIRST).
-- Precedent: 043_tenant_deploy_audit.sql.
--
-- Per 2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md:
-- explicit REVOKE from PUBLIC + anon + authenticated; explicit GRANT to
-- service_role on each caller-facing RPC. Trigger function additionally
-- REVOKEs from service_role (no legitimate direct caller).
--
-- Per cq-supabase-migration-no-concurrently: no CREATE INDEX CONCURRENTLY
-- (Supabase wraps each migration in a transaction).
--
-- Per plan §"ON DELETE RESTRICT": user_id FK uses ON DELETE RESTRICT.
-- The offboarding runbook MUST call anonymise_tc_acceptances(p_user_id)
-- BEFORE auth.admin.deleteUser(); SET NULL would nullify before the
-- anonymise RPC can run, breaking the audit row's user discriminator.

-- ============================================================================
-- tc_acceptances — append-only T&C consent ledger.
--
-- Demonstrability for GDPR Art. 7(1): persists evidence of every
-- consent grant across all TC_VERSION values, so re-acceptance of a
-- new version preserves prior-version evidence (the `public.users`
-- row's `tc_accepted_at`/`tc_accepted_version` overwrite would
-- otherwise destroy the prior record).
--
-- RLS with zero policies (service_role-only via the writer RPC).
-- WORM gated by GUC + service_role bypass for the Art. 17 anonymise
-- flow.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.tc_acceptances (
  id              uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid         REFERENCES public.users(id) ON DELETE RESTRICT,
  version         text         NOT NULL CHECK (length(version) BETWEEN 1 AND 32),
  document_sha    text         NOT NULL CHECK (document_sha ~ '^[0-9a-f]{64}$'),
  accepted_at     timestamptz  NOT NULL DEFAULT now(),
  ip_hash         text         NULL  CHECK (ip_hash IS NULL OR length(ip_hash) BETWEEN 1 AND 128),
  user_agent      text         NULL  CHECK (user_agent IS NULL OR length(user_agent) BETWEEN 1 AND 512),
  -- RETENTION: 7-year envelope per CLO assessment (sweep mechanism
  -- deferred to a follow-on issue). Column ships for forward-compat
  -- so the eventual pg_cron DELETE sweep does not require an
  -- ALTER TABLE.
  retention_until timestamptz  NOT NULL DEFAULT (now() + interval '7 years'),
  created_at      timestamptz  NOT NULL DEFAULT now(),
  UNIQUE (user_id, version)
);

ALTER TABLE public.tc_acceptances ENABLE ROW LEVEL SECURITY;
-- Zero policies: service-role-only via accept_terms / anonymise RPCs.

CREATE INDEX IF NOT EXISTS tc_acceptances_user_accepted_idx
  ON public.tc_acceptances (user_id, accepted_at DESC);

COMMENT ON TABLE public.tc_acceptances IS
  'Append-only WORM ledger of T&C consent grants (GDPR Art. 7(1) '
  'demonstrability). One row per (user_id, version). UPDATE rejected '
  'unconditionally; DELETE rejected except via anonymise_tc_acceptances '
  '(Art. 17). RLS zero-policies. user_id ON DELETE RESTRICT: the '
  'offboarding runbook MUST call anonymise_tc_acceptances(user_id) '
  'BEFORE auth.admin.deleteUser. v1 ships without pg_cron retention '
  'sweep (deferred — see AC21 of the plan).';

-- ============================================================================
-- WORM trigger: tc_acceptances is append-only EXCEPT during the
-- Art. 17 anonymisation flow.
--
-- One bypass (anonymise); UPDATE attempts NEVER bypass.
--
-- Bypass requires ALL of:
--   (a) GUC `app.tc_acceptances_anonymise_in_progress` is set (any
--       non-empty value)
--   (b) `current_user = 'service_role'`
--   (c) The SET-site for the GUC appears EXACTLY ONCE in the codebase,
--       in the body of anonymise_tc_acceptances below.
--
-- No retention-sweep bypass in v1 (the pg_cron job that would need it
-- is deferred). When the sweep ships, add a TG_OP='DELETE' + state
-- predicate bypass mirroring 043:165-169.
--
-- Trigger function is INVOKER (not DEFINER) per 043:127-134 reasoning:
-- DEFINER would evaluate `current_user` as the function OWNER (typically
-- `postgres` in Supabase migrations), making the role gate always fail
-- and breaking the legitimate Art. 17 anonymise flow.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.tc_acceptances_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_anonymise_flag text;
BEGIN
  -- current_setting(name, missing_ok=true) returns '' (not NULL) when unset.
  v_anonymise_flag := current_setting('app.tc_acceptances_anonymise_in_progress', true);

  IF v_anonymise_flag <> '' AND current_user = 'service_role' THEN
    -- Bypass: Art. 17 anonymisation flow. The single SET site is in
    -- anonymise_tc_acceptances's body below.
    RETURN COALESCE(NEW, OLD);
  END IF;

  RAISE EXCEPTION 'tc_acceptances is append-only (WORM)' USING ERRCODE = 'P0001';
END;
$$;

REVOKE ALL ON FUNCTION public.tc_acceptances_no_mutate() FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS tc_acceptances_no_update ON public.tc_acceptances;
CREATE TRIGGER tc_acceptances_no_update
  BEFORE UPDATE ON public.tc_acceptances
  FOR EACH ROW
  EXECUTE FUNCTION public.tc_acceptances_no_mutate();

DROP TRIGGER IF EXISTS tc_acceptances_no_delete ON public.tc_acceptances;
CREATE TRIGGER tc_acceptances_no_delete
  BEFORE DELETE ON public.tc_acceptances
  FOR EACH ROW
  EXECUTE FUNCTION public.tc_acceptances_no_mutate();

COMMENT ON FUNCTION public.tc_acceptances_no_mutate() IS
  'WORM gate for tc_acceptances. Single bypass (Art. 17 anonymise): GUC + '
  'service_role. UPDATE attempts NEVER bypass. INVOKER (not DEFINER) so '
  'current_user reflects the calling role. No retention-sweep bypass in v1 '
  '(deferred).';

-- ============================================================================
-- accept_terms — append-only consent writer + heartbeat updater.
--
-- service_role-only. Called from POST /api/accept-terms.
--
-- Idempotency is HERE (RPC side), not in the route handler:
--   - UPDATE public.users: no-op when tc_accepted_version already
--     equals p_version (the value doesn't change), but the
--     tc_accepted_at heartbeat still records "user re-confirmed
--     consent at time T".
--   - INSERT INTO tc_acceptances: ON CONFLICT (user_id, version)
--     DO NOTHING. Re-acceptance of the same version is a no-op for
--     the audit ledger by design — consent records are content-
--     addressed by (user_id, version).
--
-- p_user_id is taken as a parameter (not auth.uid()) so the service-role
-- caller can attribute on behalf of the authenticated user. The route
-- handler validates session ownership before calling this RPC.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.accept_terms(
  p_user_id  uuid,
  p_version  text,
  p_doc_sha  text
) RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  UPDATE public.users
     SET tc_accepted_at      = now(),
         tc_accepted_version = p_version
   WHERE id = p_user_id;

  INSERT INTO public.tc_acceptances (user_id, version, document_sha)
       VALUES (p_user_id, p_version, p_doc_sha)
       ON CONFLICT (user_id, version) DO NOTHING;
$$;

REVOKE ALL ON FUNCTION public.accept_terms(uuid, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accept_terms(uuid, text, text)
  TO service_role;

COMMENT ON FUNCTION public.accept_terms(uuid, text, text) IS
  'Append-only T&C consent writer. service_role only. Idempotent: '
  'UPDATE public.users is no-op on same version; INSERT into '
  'tc_acceptances is ON CONFLICT (user_id, version) DO NOTHING. '
  'Server-side now() — RPC does NOT accept client-supplied timestamp. '
  'feat-oauth-tc-consent-3205.';

-- ============================================================================
-- anonymise_tc_acceptances — Art. 17 cascade hook.
--
-- Called from the user-offboarding runbook BEFORE auth.admin.deleteUser()
-- per plan §"ON DELETE RESTRICT" ordering. Idempotent: re-running on
-- already-anonymised rows is a no-op (user_id is simply re-set to NULL).
--
-- UPDATEs user_id = NULL (preserving row count + audit-trail integrity)
-- — does NOT DELETE. Audit row count is preserved so consent grants
-- remain visible to legal counsel as anonymised aggregate records.
--
-- THE SINGLE SET-SITE for app.tc_acceptances_anonymise_in_progress
-- lives here. The runtime gate (role + GUC) is the cryptographic
-- component; the single-SET-site convention is reviewed at PR time.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.anonymise_tc_acceptances(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  -- WORM-bypass: SET LOCAL scopes to the current transaction; reverts
  -- at COMMIT/ROLLBACK. THE SINGLE SET-SITE for this GUC.
  SET LOCAL app.tc_acceptances_anonymise_in_progress = 'on';

  UPDATE public.tc_acceptances
     SET user_id = NULL
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_tc_acceptances(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_tc_acceptances(uuid)
  TO service_role;

COMMENT ON FUNCTION public.anonymise_tc_acceptances(uuid) IS
  'Art. 17 cascade hook: anonymises user_id on tc_acceptances rows for '
  'the given user. Idempotent. Called from the user-offboarding runbook '
  'BEFORE auth.admin.deleteUser() per ON DELETE RESTRICT FK ordering. '
  'UPDATEs user_id = NULL (does NOT DELETE) to preserve audit-trail row '
  'count. Holds the ONLY SET-site for '
  'app.tc_acceptances_anonymise_in_progress.';
