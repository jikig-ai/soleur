-- 087_worm_bypass_privilege_independence.down.sql
-- Reverts 087: restores the session_replication_role bypass in the anonymise
-- RPCs and the prior trigger-function bodies, and re-adds NOT NULL on
-- byok_delegation_acceptances.user_id.
--
-- WARNING (forward-only reality): SET NOT NULL will FAIL if any
-- byok_delegation_acceptances row has user_id = NULL (i.e. an Art-17 anonymise
-- already ran post-087). Migrations are forward-only; this down is best-effort
-- for local rollback before any erasure has executed. It also reinstates the
-- prod-broken 42501 behaviour, so it is NOT a production remediation.

-- 0. Re-add NOT NULL (fails if anonymised rows exist).
ALTER TABLE public.byok_delegation_acceptances
  ALTER COLUMN user_id SET NOT NULL;

-- 1. Restore prior trigger-function bodies.

CREATE OR REPLACE FUNCTION public.action_sends_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  RAISE EXCEPTION 'action_sends is append-only (WORM); % rejected', TG_OP
    USING ERRCODE = 'P0001';
END;
$fn$;

CREATE OR REPLACE FUNCTION public.template_authorizations_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  RAISE EXCEPTION 'template_authorizations is append-only (WORM); % rejected', TG_OP
    USING ERRCODE = 'P0001';
END;
$fn$;

CREATE OR REPLACE FUNCTION public.byok_delegation_acceptances_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF current_setting('session_replication_role') = 'replica'
     AND current_user = 'service_role' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'byok_delegation_acceptances is append-only (WORM)' USING ERRCODE = 'P0001';
END;
$fn$;

CREATE OR REPLACE FUNCTION public.byok_delegation_withdrawals_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF current_setting('session_replication_role') = 'replica'
     AND current_user = 'service_role' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'byok_delegation_withdrawals is append-only (WORM)' USING ERRCODE = 'P0001';
END;
$fn$;

CREATE OR REPLACE FUNCTION public.workspace_member_actions_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'workspace_member_actions is append-only (WORM); DELETE rejected'
      USING ERRCODE = 'P0001';
  END IF;

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

  IF (OLD.workspace_id IS NULL AND NEW.workspace_id IS NOT NULL)
    OR (OLD.workspace_id IS NOT NULL AND NEW.workspace_id IS NOT NULL
        AND NEW.workspace_id IS DISTINCT FROM OLD.workspace_id)
  THEN
    RAISE EXCEPTION 'workspace_member_actions.workspace_id: only NOT NULL -> NULL permitted'
      USING ERRCODE = 'P0001';
  END IF;

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

CREATE OR REPLACE FUNCTION public.audit_github_token_use_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF current_setting('session_replication_role') = 'replica' THEN
    RETURN NULL;
  END IF;
  RAISE EXCEPTION 'audit_github_token_use is append-only (PR-H #3244)'
    USING ERRCODE = 'P0001';
END;
$fn$;

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
      RETURN NULL;
    END IF;
    v_action      := 'role_changed';
    v_target      := NEW.user_id;
    v_old_role    := OLD.role;
    v_new_role    := NEW.role;
    v_attestation := NEW.attestation_id;
  END IF;

  INSERT INTO public.workspace_member_actions
    (workspace_id, actor_user_id, target_user_id, action_type, old_role, new_role, attestation_id)
  VALUES
    (COALESCE(NEW.workspace_id, OLD.workspace_id), v_actor, v_target, v_action, v_old_role, v_new_role, v_attestation);

  IF v_actor IS NULL AND session_user = 'authenticated' THEN
    RAISE LOG 'audit_orphan_actor workspace_id=% action=%',
      COALESCE(NEW.workspace_id, OLD.workspace_id), TG_OP;
  END IF;

  RETURN NULL;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.byok_delegations_on_member_delete()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
BEGIN
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

-- 2. Restore prior anonymise RPC bodies (session_replication_role bypass).

CREATE OR REPLACE FUNCTION public.anonymise_action_sends(p_user_id uuid)
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
      RAISE EXCEPTION 'anonymise_action_sends: caller not authorised'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    IF auth.uid() <> p_user_id THEN
      RAISE EXCEPTION 'anonymise_action_sends: self-call only for authenticated callers'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  SET LOCAL session_replication_role = 'replica';
  UPDATE public.action_sends
     SET user_id           = NULL,
         recipient_id_hash = '__anonymised__'
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS affected = ROW_COUNT;
  RESET session_replication_role;

  RETURN affected;
END;
$fn$;

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
$fn$;

CREATE OR REPLACE FUNCTION public.anonymise_workspace_member_actions(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_rows int;
BEGIN
  SET LOCAL session_replication_role = 'replica';
  UPDATE public.workspace_member_actions
     SET actor_user_id  = NULL,
         target_user_id = NULL
   WHERE actor_user_id  = p_user_id
      OR target_user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RESET session_replication_role;
  RETURN v_rows;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.anonymise_workspace_members(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_rows int;
BEGIN
  SET LOCAL session_replication_role = 'replica';
  DELETE FROM public.workspace_members
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RESET session_replication_role;
  RETURN v_rows;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.anonymise_byok_delegation_acceptances(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
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
$fn$;

CREATE OR REPLACE FUNCTION public.anonymise_byok_delegation_withdrawals(p_user_id uuid)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
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
$fn$;

CREATE OR REPLACE FUNCTION public.anonymise_audit_github_token_use(p_founder_id uuid)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  SET LOCAL session_replication_role = 'replica';
  UPDATE public.audit_github_token_use
     SET founder_id = NULL,
         repo_full_name = NULL
   WHERE founder_id = p_founder_id;
END;
$fn$;
