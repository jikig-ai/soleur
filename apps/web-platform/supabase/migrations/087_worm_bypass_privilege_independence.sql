-- 087_worm_bypass_privilege_independence.sql
-- GDPR Article 17 — Right to Erasure. Issue #4696 / Sentry WEB-PLATFORM-13.
--
-- PROBLEM (broken in production): every anonymise RPC in the account-delete
-- saga bypassed its append-only (WORM) trigger via
--   SET LOCAL session_replication_role = 'replica';
-- That GUC is superuser-only (PGC_SUSET). The anonymise RPCs are SECURITY
-- DEFINER owned by `postgres`, which on managed Supabase is NOT a superuser,
-- so the SET raises `42501 permission denied to set parameter
-- "session_replication_role"` BEFORE the UPDATE. The saga aborts on its first
-- such step (anonymise_action_sends) and NO account can be deleted at all —
-- the right to erasure cannot be honoured (an Art. 17 / Art. 5(1)(e) failure).
--
-- FIX: replace the privileged GUC with a privilege-free custom GUC,
-- `app.worm_bypass`, set with SET LOCAL (transaction-scoped) inside each
-- anonymise RPC and honored by the trigger functions via
--   current_setting('app.worm_bypass', true) = 'on'
-- Custom namespaced GUCs require no special privilege, so the 42501 is gone.
-- The check has NO `current_user` dependency, so it is NOT the proven-dead
-- pattern from learning
-- 2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md
-- (where `current_user = 'service_role'` is silently always-false inside a
-- SECURITY DEFINER function under PostgREST routing). It is that learning's
-- own recommended no-role-check bypass. Precedent for shape-scoped WORM
-- bypass is migration 050 (scope_grants); this migration uses the uniform
-- GUC variant because anonymise_workspace_members must suppress AFTER
-- side-effect triggers (audit writer + byok-revoke cascade), which structural
-- shape detection cannot express.
--
-- SCOPE — all session_replication_role-dependent functions on the erasure
-- path (the account-delete saga):
--   * anonymise_action_sends                    (mig 051)  — FATAL step 3.82
--   * anonymise_template_authorizations         (mig 053)  — FATAL
--   * anonymise_workspace_member_actions        (mig 063)  — FATAL
--   * anonymise_workspace_members               (mig 058/063) — FATAL (DELETE)
--   * anonymise_byok_delegation_acceptances     (mig 074)  — FATAL
--   * anonymise_byok_delegation_withdrawals     (mig 084)  — FATAL
--   * anonymise_audit_github_token_use          (mig 037/066) — non-fatal
-- and their trigger functions. NOT in scope (deferred — non-erasure paths,
-- tracked separately): purge_workspace_member_actions (retention) and
-- revoke_template_authorization (revoke). They remain on session_replication_
-- role and are still broken on prod; fixing them does not unblock erasure.
--
-- byok_delegation_acceptances.user_id: the column is NOT NULL with FK→users
-- ON DELETE RESTRICT, yet anonymise_byok_delegation_acceptances sets it NULL.
-- On any real row that raises 23502 independent of WORM. The erasure contract
-- requires nulling the FK before auth-delete, so the column must be nullable
-- (mirrors action_sends.user_id and byok_delegation_withdrawals.user_id which
-- are already nullable). DROP NOT NULL below. (This is a real defect, NOT the
-- retracted action_sends one — that column really was already nullable.)
--
-- Conventions: idempotent (CREATE OR REPLACE), no outer BEGIN/COMMIT (Supabase
-- wraps), search_path pinned on SECURITY DEFINER functions
-- (cq-pg-security-definer-search-path-pin-pg-temp). Existing function grants
-- are preserved by CREATE OR REPLACE; trigger functions are re-REVOKEd from
-- client roles as defense-in-depth (mig 050 precedent).

-- ---------------------------------------------------------------------------
-- 0. byok_delegation_acceptances.user_id must be nullable for Art-17 erasure.
-- ---------------------------------------------------------------------------
ALTER TABLE public.byok_delegation_acceptances
  ALTER COLUMN user_id DROP NOT NULL;

COMMENT ON COLUMN public.byok_delegation_acceptances.user_id IS
  'NULLABLE to admit Art. 17 anonymisation (anonymise_byok_delegation_acceptances sets NULL). FK→users ON DELETE RESTRICT; nulled before auth-delete. Issue #4696.';

-- ===========================================================================
-- 1. BEFORE reject / shape WORM trigger functions — honor app.worm_bypass.
-- ===========================================================================

-- 1.1 action_sends_no_mutate (was pure-reject; SECURITY DEFINER).
CREATE OR REPLACE FUNCTION public.action_sends_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  -- Art-17 erasure bypass (anonymise_action_sends): privilege-free GUC.
  IF current_setting('app.worm_bypass', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'action_sends is append-only (WORM); % rejected', TG_OP
    USING ERRCODE = 'P0001';
END;
$fn$;

REVOKE ALL ON FUNCTION public.action_sends_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

-- 1.2 template_authorizations_no_mutate (was pure-reject; SECURITY DEFINER).
CREATE OR REPLACE FUNCTION public.template_authorizations_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF current_setting('app.worm_bypass', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'template_authorizations is append-only (WORM); % rejected', TG_OP
    USING ERRCODE = 'P0001';
END;
$fn$;

REVOKE ALL ON FUNCTION public.template_authorizations_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

-- 1.3 byok_delegation_acceptances_no_mutate. Replaces the proven-dead
--     `current_setting('session_replication_role')='replica' AND
--      current_user='service_role'` bypass (always-false under PostgREST
--     routing) with the GUC check. INVOKER (unchanged).
CREATE OR REPLACE FUNCTION public.byok_delegation_acceptances_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF current_setting('app.worm_bypass', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'byok_delegation_acceptances is append-only (WORM)'
    USING ERRCODE = 'P0001';
END;
$fn$;

REVOKE ALL ON FUNCTION public.byok_delegation_acceptances_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

-- 1.4 byok_delegation_withdrawals_no_mutate. Same fix as 1.3. INVOKER.
CREATE OR REPLACE FUNCTION public.byok_delegation_withdrawals_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF current_setting('app.worm_bypass', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'byok_delegation_withdrawals is append-only (WORM)'
    USING ERRCODE = 'P0001';
END;
$fn$;

REVOKE ALL ON FUNCTION public.byok_delegation_withdrawals_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

-- 1.5 workspace_member_actions_no_mutate. Already structural-shape (mig
--     063/072); add the GUC fast-path so anonymise_workspace_member_actions
--     can drop session_replication_role. Structural-shape logic is preserved
--     below as defense-in-depth (still permits the NOT NULL→NULL transitions
--     for any non-GUC legitimate path). INVOKER.
CREATE OR REPLACE FUNCTION public.workspace_member_actions_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  -- Art-17 erasure bypass (anonymise_workspace_member_actions).
  IF current_setting('app.worm_bypass', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- DELETE: pure-reject (unchanged from mig 063). Retention purge uses
  -- session_replication_role='replica' to bypass this trigger entirely.
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'workspace_member_actions is append-only (WORM); DELETE rejected'
      USING ERRCODE = 'P0001';
  END IF;

  -- UPDATE: audit lineage must be immutable.
  IF NEW.id              IS DISTINCT FROM OLD.id
    OR NEW.action_type   IS DISTINCT FROM OLD.action_type
    OR NEW.old_role      IS DISTINCT FROM OLD.old_role
    OR NEW.new_role      IS DISTINCT FROM OLD.new_role
    OR NEW.created_at    IS DISTINCT FROM OLD.created_at
    OR NEW.attestation_id IS DISTINCT FROM OLD.attestation_id
  THEN
    RAISE EXCEPTION 'workspace_member_actions audit lineage is immutable (id, action_type, old_role, new_role, created_at, attestation_id)'
      USING ERRCODE = 'P0001';
  END IF;

  -- workspace_id: NOT NULL → NULL permitted (ON DELETE SET NULL cascade
  -- when a workspace is deleted). NULL → NOT NULL or value-change rejected.
  IF (OLD.workspace_id IS NULL AND NEW.workspace_id IS NOT NULL)
    OR (OLD.workspace_id IS NOT NULL AND NEW.workspace_id IS NOT NULL
        AND NEW.workspace_id IS DISTINCT FROM OLD.workspace_id)
  THEN
    RAISE EXCEPTION 'workspace_member_actions.workspace_id: only NOT NULL -> NULL permitted'
      USING ERRCODE = 'P0001';
  END IF;

  -- PII columns (actor_user_id, target_user_id): NOT NULL → NULL permitted
  -- (Art. 17 anonymise). NULL → NOT NULL (re-identification) or value-change
  -- rejected.
  IF (OLD.actor_user_id IS NULL AND NEW.actor_user_id IS NOT NULL)
    OR (OLD.actor_user_id IS NOT NULL AND NEW.actor_user_id IS NOT NULL
        AND NEW.actor_user_id IS DISTINCT FROM OLD.actor_user_id)
    OR (OLD.target_user_id IS NULL AND NEW.target_user_id IS NOT NULL)
    OR (OLD.target_user_id IS NOT NULL AND NEW.target_user_id IS NOT NULL
        AND NEW.target_user_id IS DISTINCT FROM OLD.target_user_id)
  THEN
    RAISE EXCEPTION 'workspace_member_actions PII columns: only NOT NULL -> NULL permitted'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION public.workspace_member_actions_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

-- 1.6 audit_github_token_use_no_mutate. Was a session_replication_role check
--     (RETURN NULL when 'replica'); switch to the app.worm_bypass GUC.
--     INVOKER.
CREATE OR REPLACE FUNCTION public.audit_github_token_use_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  -- Art-17 erasure bypass (anonymise_audit_github_token_use).
  IF current_setting('app.worm_bypass', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'audit_github_token_use is append-only (PR-H #3244)'
    USING ERRCODE = 'P0001';
END;
$fn$;

REVOKE ALL ON FUNCTION public.audit_github_token_use_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

-- ===========================================================================
-- 2. AFTER side-effect trigger functions on workspace_members — honor
--    app.worm_bypass so anonymise_workspace_members' erasure DELETE creates
--    no new audit/PII rows and does not fire the byok-revoke cascade (the
--    exact behaviour the prior session_replication_role='replica' produced).
-- ===========================================================================

-- 2.1 workspace_members_audit (AFTER INSERT/UPDATE/DELETE). Skip the audit
--     INSERT under the erasure bypass.
CREATE OR REPLACE FUNCTION public.workspace_members_audit()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_actor       uuid;
  v_action      text;
  v_target      uuid;
  v_old_role    text;
  v_new_role    text;
  v_attestation uuid;
BEGIN
  -- Art-17 erasure bypass (anonymise_workspace_members): suppress the audit
  -- writer so the cascade DELETE does not create orphan-PII audit rows.
  IF current_setting('app.worm_bypass', true) = 'on' THEN
    RETURN NULL;
  END IF;

  -- Parse the actor GUC; tolerate unset (empty string) and malformed.
  -- NULLIF returns NULL for the unset/empty case; the EXCEPTION block
  -- catches 22P02 invalid_text_representation for a future writer that
  -- sets the GUC to a non-UUID. Never fall back to auth.uid() (TR10a).
  BEGIN
    v_actor := NULLIF(current_setting('workspace_audit.actor_user_id', true), '')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    v_actor := NULL;
  END;

  IF TG_OP = 'INSERT' THEN
    v_action      := 'added';
    v_target      := NEW.user_id;
    v_new_role    := NEW.role;
    v_attestation := NEW.attestation_id;
  ELSIF TG_OP = 'DELETE' THEN
    v_action   := 'removed';
    v_target   := OLD.user_id;
    v_old_role := OLD.role;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.role IS NOT DISTINCT FROM NEW.role THEN
      RETURN NULL;  -- no-op UPDATE (same role); do not audit
    END IF;
    v_action      := 'role_changed';
    v_target      := NEW.user_id;
    v_old_role    := OLD.role;
    v_new_role    := NEW.role;
    v_attestation := NEW.attestation_id;  -- preserve consent attribution on role change
  END IF;

  INSERT INTO public.workspace_member_actions
    (workspace_id, actor_user_id, target_user_id, action_type, old_role, new_role, attestation_id)
  VALUES
    (COALESCE(NEW.workspace_id, OLD.workspace_id), v_actor, v_target, v_action, v_old_role, v_new_role, v_attestation);

  -- TR13: orphan-actor signal. session_user (not current_user) for the
  -- caller's role — under SECURITY DEFINER current_user is the definer.
  IF v_actor IS NULL AND session_user = 'authenticated' THEN
    RAISE LOG 'audit_orphan_actor workspace_id=% action=%',
      COALESCE(NEW.workspace_id, OLD.workspace_id), TG_OP;
  END IF;

  RETURN NULL;
END;
$fn$;

-- 2.2 byok_delegations_on_member_delete (AFTER DELETE). Skip the byok-revoke
--     cascade under the erasure bypass (byok_delegations are handled by their
--     own anonymise step 5.10).
CREATE OR REPLACE FUNCTION public.byok_delegations_on_member_delete()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  -- Art-17 erasure bypass (anonymise_workspace_members).
  IF current_setting('app.worm_bypass', true) = 'on' THEN
    RETURN OLD;
  END IF;

  UPDATE public.byok_delegations
     SET revoked_at         = clock_timestamp(),
         revoked_by_user_id = OLD.user_id,
         revocation_reason  = 'member_departed'
   WHERE (grantor_user_id = OLD.user_id OR grantee_user_id = OLD.user_id)
     AND workspace_id      = OLD.workspace_id
     AND revoked_at IS NULL;
  RETURN OLD;
END;
$fn$;

-- ===========================================================================
-- 3. Anonymise RPCs — swap session_replication_role for app.worm_bypass.
--    Bodies otherwise unchanged (auth checks, search_path, grants preserved).
--    `SET LOCAL app.worm_bypass = 'off'` re-arms WORM immediately after the
--    single erasure write (mirrors the prior RESET session_replication_role).
-- ===========================================================================

-- 3.1 anonymise_action_sends
CREATE OR REPLACE FUNCTION public.anonymise_action_sends(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
DECLARE
  affected integer;
BEGIN
  -- Authorisation:
  --   * Service-role callers (account-delete.ts) — auth.uid() is NULL,
  --     current_user = 'service_role' (or 'postgres' in local dev).
  --   * Self-DSAR callers (founder-initiated path) — auth.uid() = p_user_id.
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

  SET LOCAL app.worm_bypass = 'on';
  UPDATE public.action_sends
     SET user_id           = NULL,
         recipient_id_hash = '__anonymised__'
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS affected = ROW_COUNT;
  SET LOCAL app.worm_bypass = 'off';

  RETURN affected;
END;
$fn$;

-- 3.2 anonymise_template_authorizations
CREATE OR REPLACE FUNCTION public.anonymise_template_authorizations(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
DECLARE
  affected integer;
BEGIN
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

  SET LOCAL app.worm_bypass = 'on';
  UPDATE public.template_authorizations
     SET founder_id        = NULL,
         revoked_at        = COALESCE(revoked_at, now()),
         revocation_reason = COALESCE(revocation_reason, 'dsr_erasure')
   WHERE founder_id = p_user_id;
  GET DIAGNOSTICS affected = ROW_COUNT;
  SET LOCAL app.worm_bypass = 'off';

  RETURN affected;
END;
$fn$;

-- 3.3 anonymise_workspace_member_actions
CREATE OR REPLACE FUNCTION public.anonymise_workspace_member_actions(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_rows int;
BEGIN
  SET LOCAL app.worm_bypass = 'on';
  UPDATE public.workspace_member_actions
     SET actor_user_id  = NULL,
         target_user_id = NULL
   WHERE actor_user_id  = p_user_id
      OR target_user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  SET LOCAL app.worm_bypass = 'off';
  RETURN v_rows;
END;
$fn$;

-- 3.4 anonymise_workspace_members (DELETE; suppresses AFTER triggers)
CREATE OR REPLACE FUNCTION public.anonymise_workspace_members(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_rows int;
BEGIN
  -- Bypass workspace_members_audit + byok_delegations_on_member_delete so the
  -- cascade DELETE does not create orphan-PII audit rows (plan-review P1-2;
  -- account-delete.ts step 3.93).
  SET LOCAL app.worm_bypass = 'on';
  DELETE FROM public.workspace_members
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  SET LOCAL app.worm_bypass = 'off';
  RETURN v_rows;
END;
$fn$;

-- 3.5 anonymise_byok_delegation_acceptances
CREATE OR REPLACE FUNCTION public.anonymise_byok_delegation_acceptances(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_rows int;
BEGIN
  SET LOCAL app.worm_bypass = 'on';
  UPDATE public.byok_delegation_acceptances
     SET user_id    = NULL,
         ip_hash    = NULL,
         user_agent = NULL
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  SET LOCAL app.worm_bypass = 'off';
  RETURN v_rows;
END;
$fn$;

-- 3.6 anonymise_byok_delegation_withdrawals
CREATE OR REPLACE FUNCTION public.anonymise_byok_delegation_withdrawals(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_rows int;
BEGIN
  SET LOCAL app.worm_bypass = 'on';
  UPDATE public.byok_delegation_withdrawals
     SET user_id    = NULL,
         ip_hash    = NULL,
         user_agent = NULL
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  SET LOCAL app.worm_bypass = 'off';
  RETURN v_rows;
END;
$fn$;

-- 3.7 anonymise_audit_github_token_use (RETURNS void; non-fatal saga step)
CREATE OR REPLACE FUNCTION public.anonymise_audit_github_token_use(p_founder_id uuid)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  SET LOCAL app.worm_bypass = 'on';
  UPDATE public.audit_github_token_use
     SET founder_id     = NULL,
         repo_full_name = NULL
   WHERE founder_id = p_founder_id;
  SET LOCAL app.worm_bypass = 'off';
END;
$fn$;
