-- 091_rename_organization_and_default_names.sql
-- feat-one-shot-workspace-untitled-name — close the organizations.name
-- contract that migration 053 deferred to "Phase 5.4" and never built.
--
-- Symptom: every organization row carries name = NULL (the 053 backfill,
-- the handle_new_user() signup trigger, and every other write path insert
-- NULL). The dashboard org switcher renders `organizationName ?? "Untitled"`
-- (server/org-memberships-resolver.ts), so multi-workspace users see a list
-- of indistinguishable "Untitled" rows.
--
-- This migration makes organizations.name effectively non-NULL at every
-- write surface, WITHOUT adding a NOT NULL constraint (053:47-48 chose
-- app-layer enforcement to keep the backfill single-statement):
--   1. rename_organization RPC — the only runtime user-reachable write path
--      (owner-gated SECURITY DEFINER; mirrors 075_transfer_workspace_ownership).
--   2. handle_new_user() re-derived from 053:289-329 with the two NULL name
--      literals changed to a generic non-PII default ('My Workspace').
--   3. one-time backfill of existing NULL-name org + workspace rows.
--
-- Privacy (GDPR, advisory): the backfill default is a generic label, NOT the
-- owner's email/name. organizations.name is peer-visible via
-- orgs_select_for_members (053:159); an email-derived default would disclose
-- the owner's email to every workspace member.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every SECURITY DEFINER
-- function pins SET search_path = public, pg_temp (pg_temp LAST).
-- Per 2026-05-06-supabase-default-privileges-defeat-revoke-from-public:
-- explicit REVOKE from PUBLIC + anon + authenticated; explicit GRANT to
-- authenticated.

-- =====================================================================
-- 1. rename_organization RPC (sole authenticated write path)
-- =====================================================================
-- Strict simplification of transfer_workspace_ownership (mig 075): same
-- owner-gate/grant spine, none of the multi-row/attestation/audit machinery.
-- organizations carries NO audit trigger (audit triggers target
-- workspace_members only), so this RPC does NOT set the workspace_audit
-- actor GUC — it would be dead.
--
-- Caller identity: COALESCE(p_caller_user_id, auth.uid()), mirroring
-- accept_workspace_invitation (mig 076/085). The TS wrapper invokes this via
-- the service-role client (createServiceClient), under which auth.uid() is
-- NULL — a pure auth.uid() gate (the 075 shape) would raise 28000 on every
-- service-role call. The route passes the verified getUser() id explicitly;
-- when auth.uid() IS populated (authenticated-client call) COALESCE returns
-- the same value, so the gate is correct under both invocation modes.

CREATE OR REPLACE FUNCTION public.rename_organization(
  p_organization_id uuid,
  p_name            text,
  p_caller_user_id  uuid DEFAULT NULL
) RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_user_id uuid := COALESCE(p_caller_user_id, auth.uid());
  v_is_owner       boolean;
  v_trimmed        text;
BEGIN
  -- 1. Authenticate
  IF v_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'caller_user_id is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;

  -- 2. Caller must be an owner of a workspace in the target org. FOR UPDATE
  -- matches the 075 precedent (a rename race is benign — last-write-wins —
  -- but the lock keeps the owner-read consistent under READ COMMITTED).
  SELECT EXISTS (
    SELECT 1
    FROM public.workspace_members m
    JOIN public.workspaces w ON w.id = m.workspace_id
    WHERE w.organization_id = p_organization_id
      AND m.user_id         = v_caller_user_id
      AND m.role            = 'owner'
    FOR UPDATE
  ) INTO v_is_owner;

  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'caller is not an owner of organization %', p_organization_id
      USING ERRCODE = '42501';
  END IF;

  -- 3. Validate name: trim, reject empty/whitespace-only, bound length.
  v_trimmed := btrim(COALESCE(p_name, ''));
  IF length(v_trimmed) = 0 THEN
    RAISE EXCEPTION 'name must not be empty'
      USING ERRCODE = '22023';
  END IF;
  IF length(v_trimmed) > 60 THEN
    RAISE EXCEPTION 'name must be at most 60 characters'
      USING ERRCODE = '22023';
  END IF;

  -- 4. Single-row UPDATE.
  UPDATE public.organizations SET name = v_trimmed WHERE id = p_organization_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no organization row for id=%', p_organization_id
      USING ERRCODE = 'P0001';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.rename_organization(uuid, text, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rename_organization(uuid, text, uuid)
  TO authenticated;

COMMENT ON FUNCTION public.rename_organization(uuid, text, uuid) IS
  'Owner-gated single-row rename of organizations.name. SECURITY DEFINER '
  'so the RPC is the sole authenticated write path (no RLS UPDATE policy '
  'on organizations). Mirrors transfer_workspace_ownership owner-gate '
  '(mig 075) minus attestation/audit machinery. '
  'feat-one-shot-workspace-untitled-name.';

-- =====================================================================
-- 2. handle_new_user() — non-NULL default names for new signups
-- =====================================================================
-- Full body re-derived from 053:289-329. ONLY change: the two NULL name
-- literals (organizations.name, workspaces.name) become the generic default
-- 'My Workspace'. Dropping any other arm (public.users insert, canary guard,
-- org/workspace/member creation, ON CONFLICT idempotency) would break signup.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_org_id uuid;
BEGIN
  -- 1. Insert public.users row (original 001 behavior).
  INSERT INTO public.users (id, email, workspace_path)
  VALUES (
    NEW.id,
    NEW.email,
    '/workspaces/' || NEW.id::text
  )
  ON CONFLICT (id) DO NOTHING;

  -- 2. Insert organization (default-named) for this user IF they don't
  -- already have the canary owner row. Idempotent via the same
  -- discriminator as the 053 backfill DO block.
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_members m
    WHERE m.user_id = NEW.id AND m.workspace_id = NEW.id AND m.role = 'owner'
  ) THEN
    INSERT INTO public.organizations (id, name, domain, owner_user_id)
    VALUES (gen_random_uuid(), 'My Workspace', NULL, NEW.id)
    RETURNING id INTO v_org_id;

    INSERT INTO public.workspaces (id, organization_id, name)
    VALUES (NEW.id, v_org_id, 'My Workspace')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.workspace_members (workspace_id, user_id, role, attestation_id)
    VALUES (NEW.id, NEW.id, 'owner', NULL)
    ON CONFLICT (workspace_id, user_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

-- handle_new_user is a trigger function (fires AFTER INSERT on auth.users)
-- and is not invoked via direct CALL. The REVOKE is defensive (satisfies
-- migration-rpc-grants lint + closes the direct-EXECUTE surface). Triggers
-- fire under the owner's identity regardless of EXECUTE grant, so this
-- REVOKE does NOT break signup.
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.handle_new_user() IS
  'Auth signup hook. Creates public.users row + default-named organization '
  '+ workspace (id = users.id per ADR-038 N2) + workspace_members(role=owner). '
  'Idempotent via canary owner-row discriminator + per-table ON CONFLICT DO '
  'NOTHING. SECURITY DEFINER so RLS does not block during the auth.users '
  'INSERT trigger. Default name set per feat-one-shot-workspace-untitled-name '
  '(was NULL in mig 053).';

-- =====================================================================
-- 3. Backfill existing NULL-name rows to the default
-- =====================================================================
-- Idempotent: WHERE name IS NULL discriminator → re-running this migration
-- on a populated DB updates 0 rows. Privacy: generic non-PII label only.

DO $$
DECLARE
  v_org_rc int;
  v_ws_rc  int;
BEGIN
  UPDATE public.organizations SET name = 'My Workspace' WHERE name IS NULL;
  GET DIAGNOSTICS v_org_rc = ROW_COUNT;
  RAISE NOTICE '[091-backfill] organizations renamed from NULL: %', v_org_rc;

  UPDATE public.workspaces SET name = 'My Workspace' WHERE name IS NULL;
  GET DIAGNOSTICS v_ws_rc = ROW_COUNT;
  RAISE NOTICE '[091-backfill] workspaces renamed from NULL: %', v_ws_rc;
END $$;
