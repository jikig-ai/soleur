-- 054_workspace_member_attestations.sql
-- feat-team-workspace-multi-user (#4229, PR #4225) — WORM attestation
-- ledger + 5 SECURITY DEFINER RPCs gating workspace membership
-- mutations.
--
-- LAWFUL_BASIS: GDPR Art. 6(1)(a) consent (the invitee's explicit
-- acceptance of the inviter's attestation) + Art. 6(1)(c) legal
-- obligation (DPD §2.3 co-member disclosure + AUP §5.5 attestation
-- preservation requires a tamper-evident written record). PA-2 of the
-- Article 30 register tracks the "workspace co-member" data category.
--
-- RETENTION: WORM (write-once-read-many). Attestation rows survive
-- both inviter and invitee account-delete events. Art. 17 erasure
-- requests cascade via anonymise_workspace_member_attestations which
-- zero-out the PII columns (inviter_user_id, invitee_user_id,
-- attestation_text, ip_hash, user_agent) while preserving the audit
-- lineage (id, workspace_id, accepted_at). The audit row remains
-- queryable for SOX / SOC2 forensic windows without leaking PII.
--
-- WORM contract (per migration 048 + learning
-- 2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-
-- routing): UPDATE and DELETE are ALWAYS rejected, with one
-- structural exception — the "Art. 17 anonymise" shape where every
-- PII column transitions NOT NULL → NULL and every non-PII column is
-- unchanged. Recognized by structural diff, not by GUC + role gate
-- (which silently always-fails under PostgREST routing).
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every fn pins
-- SET search_path = public, pg_temp.
-- Per 2026-03-20-supabase-column-level-grant-override: REVOKE UPDATE
-- ON TABLE first. NO column-level GRANT — all mutations route
-- through SECURITY DEFINER RPCs (REVOKE FROM PUBLIC,anon,authenticated;
-- GRANT EXECUTE TO appropriate roles).
-- Per migration 045's is_message_owner shape: every helper fn uses
-- LANGUAGE plpgsql (NOT sql STABLE; planner-inlining hazard).

-- =====================================================================
-- 1. workspace_member_attestations table
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.workspace_member_attestations (
  id                uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id      uuid         NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  -- PII columns — NULL after Art. 17 anonymise.
  inviter_user_id   uuid         NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  invitee_user_id   uuid         NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  attestation_text  text         NULL,
  ip_hash           text         NULL,
  user_agent        text         NULL,
  -- Audit lineage — never cleared.
  accepted_at       timestamptz  NOT NULL DEFAULT now()
);

ALTER TABLE public.workspace_member_attestations ENABLE ROW LEVEL SECURITY;

-- Column-level posture: REVOKE table-level UPDATE FIRST per learning
-- 2026-03-20-supabase-column-level-grant-override. No column-level
-- GRANT — all mutations route through SECURITY DEFINER RPCs.
REVOKE UPDATE ON TABLE public.workspace_member_attestations FROM PUBLIC, anon, authenticated;
REVOKE DELETE ON TABLE public.workspace_member_attestations FROM PUBLIC, anon, authenticated;
REVOKE INSERT ON TABLE public.workspace_member_attestations FROM PUBLIC, anon, authenticated;

-- SELECT visible to workspace co-members.
CREATE POLICY attestations_select_for_members ON public.workspace_member_attestations
  FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspace_id, auth.uid()));

-- =====================================================================
-- 2. WORM trigger (BEFORE UPDATE/DELETE)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.workspace_member_attestations_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
BEGIN
  -- DELETE always rejected. Use anonymise_workspace_member_attestations
  -- for Art. 17 cascade.
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'workspace_member_attestations is append-only; use anonymise_workspace_member_attestations for Art. 17 cascade'
      USING ERRCODE = 'P0001';
  END IF;

  -- UPDATE shape "Art. 17 anonymise":
  --   * every PII column transitions NOT NULL → NULL
  --   * audit lineage (id, workspace_id, accepted_at) unchanged
  -- Mirrors migration 048 §scope_grants_no_mutate Shape 2. Recognized
  -- by structural shape rather than GUC + role gate per learning
  -- 2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-
  -- routing.md.
  --
  -- Defense-in-depth: anonymise_workspace_member_attestations is
  -- SECURITY DEFINER with `REVOKE EXECUTE FROM PUBLIC, anon,
  -- authenticated`; only service-role-authenticated callers can issue
  -- the UPDATE that matches this shape.
  IF NEW.id              IS DISTINCT FROM OLD.id
    OR NEW.workspace_id  IS DISTINCT FROM OLD.workspace_id
    OR NEW.accepted_at   IS DISTINCT FROM OLD.accepted_at
  THEN
    RAISE EXCEPTION 'workspace_member_attestations audit lineage is immutable'
      USING ERRCODE = 'P0001';
  END IF;

  -- Each PII column must transition NOT NULL → NULL OR stay unchanged.
  -- Any NULL → NOT NULL transition or value-change (NOT NULL → NOT NULL
  -- with different value) is rejected.
  IF (OLD.inviter_user_id  IS NULL AND NEW.inviter_user_id  IS NOT NULL)
    OR (OLD.inviter_user_id  IS NOT NULL AND NEW.inviter_user_id  IS NOT NULL AND NEW.inviter_user_id  IS DISTINCT FROM OLD.inviter_user_id)
    OR (OLD.invitee_user_id  IS NULL AND NEW.invitee_user_id  IS NOT NULL)
    OR (OLD.invitee_user_id  IS NOT NULL AND NEW.invitee_user_id  IS NOT NULL AND NEW.invitee_user_id  IS DISTINCT FROM OLD.invitee_user_id)
    OR (OLD.attestation_text IS NULL AND NEW.attestation_text IS NOT NULL)
    OR (OLD.attestation_text IS NOT NULL AND NEW.attestation_text IS NOT NULL AND NEW.attestation_text IS DISTINCT FROM OLD.attestation_text)
    OR (OLD.ip_hash          IS NULL AND NEW.ip_hash          IS NOT NULL)
    OR (OLD.ip_hash          IS NOT NULL AND NEW.ip_hash          IS NOT NULL AND NEW.ip_hash          IS DISTINCT FROM OLD.ip_hash)
    OR (OLD.user_agent       IS NULL AND NEW.user_agent       IS NOT NULL)
    OR (OLD.user_agent       IS NOT NULL AND NEW.user_agent       IS NOT NULL AND NEW.user_agent       IS DISTINCT FROM OLD.user_agent)
  THEN
    RAISE EXCEPTION 'workspace_member_attestations is append-only; only Art. 17 anonymise (NOT NULL → NULL) transitions permitted'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.workspace_member_attestations_no_mutate() FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS workspace_member_attestations_no_update ON public.workspace_member_attestations;
CREATE TRIGGER workspace_member_attestations_no_update
  BEFORE UPDATE ON public.workspace_member_attestations
  FOR EACH ROW EXECUTE FUNCTION public.workspace_member_attestations_no_mutate();

DROP TRIGGER IF EXISTS workspace_member_attestations_no_delete ON public.workspace_member_attestations;
CREATE TRIGGER workspace_member_attestations_no_delete
  BEFORE DELETE ON public.workspace_member_attestations
  FOR EACH ROW EXECUTE FUNCTION public.workspace_member_attestations_no_mutate();

-- Covering index for the per-workspace audit-read hot path.
CREATE INDEX IF NOT EXISTS workspace_member_attestations_workspace_idx
  ON public.workspace_member_attestations (workspace_id, accepted_at DESC);

-- =====================================================================
-- 3. workspace_members.attestation_id FK (now that target table exists)
-- =====================================================================

ALTER TABLE public.workspace_members
  ADD CONSTRAINT workspace_members_attestation_id_fkey
  FOREIGN KEY (attestation_id) REFERENCES public.workspace_member_attestations(id) ON DELETE RESTRICT;

-- =====================================================================
-- 4. invite_workspace_member RPC
-- =====================================================================
--
-- Caller: workspace OWNER (authenticated; auth.uid() must be a member
-- with role='owner' of p_workspace_id). Inserts a workspace_member_
-- attestations row + workspace_members row atomically. Returns
-- the new workspace_members composite key.
--
-- Idempotency: if the user is already a member of the workspace,
-- raises 'already_member' (caller decides whether to surface or
-- ignore). Re-inviting after removal is a new attestation row (the
-- prior removal cleared the workspace_members row but not the
-- attestation; this is by design — the previous consent stands as
-- audit lineage).

CREATE OR REPLACE FUNCTION public.invite_workspace_member(
  p_workspace_id      uuid,
  p_invitee_user_id   uuid,
  p_attestation_text  text,
  p_ip_hash           text,
  p_user_agent        text
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_inviter_user_id uuid := auth.uid();
  v_is_owner       boolean;
  v_attestation_id uuid;
BEGIN
  IF v_inviter_user_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF p_workspace_id IS NULL OR p_invitee_user_id IS NULL THEN
    RAISE EXCEPTION 'workspace_id and invitee_user_id are required'
      USING ERRCODE = '22004';
  END IF;

  IF p_attestation_text IS NULL OR length(p_attestation_text) < 16 THEN
    RAISE EXCEPTION 'attestation_text must be at least 16 chars'
      USING ERRCODE = '22023';
  END IF;

  -- Authorize: caller must be an owner of the target workspace.
  SELECT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = v_inviter_user_id
      AND role         = 'owner'
  ) INTO v_is_owner;

  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'caller is not an owner of workspace %', p_workspace_id
      USING ERRCODE = '42501';
  END IF;

  -- Reject self-invite (the owner is already a member).
  IF v_inviter_user_id = p_invitee_user_id THEN
    RAISE EXCEPTION 'owner cannot invite themselves'
      USING ERRCODE = '22023';
  END IF;

  -- Reject double-membership (already a member, irrespective of role).
  IF EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = p_invitee_user_id
  ) THEN
    RAISE EXCEPTION 'user is already a member of workspace %', p_workspace_id
      USING ERRCODE = '23505';  -- unique_violation analogue
  END IF;

  -- Insert attestation row.
  INSERT INTO public.workspace_member_attestations (
    workspace_id, inviter_user_id, invitee_user_id,
    attestation_text, ip_hash, user_agent
  ) VALUES (
    p_workspace_id, v_inviter_user_id, p_invitee_user_id,
    p_attestation_text, p_ip_hash, p_user_agent
  )
  RETURNING id INTO v_attestation_id;

  -- Insert workspace_members row referencing the attestation.
  INSERT INTO public.workspace_members (workspace_id, user_id, role, attestation_id)
       VALUES (p_workspace_id, p_invitee_user_id, 'member', v_attestation_id);

  RETURN v_attestation_id;
END;
$$;

REVOKE ALL ON FUNCTION public.invite_workspace_member(uuid, uuid, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.invite_workspace_member(uuid, uuid, text, text, text)
  TO authenticated;

-- =====================================================================
-- 5. remove_workspace_member RPC
-- =====================================================================
--
-- Caller: workspace OWNER. DELETEs the workspace_members row (the
-- attestation stays for audit). The TS wrapper at
-- apps/web-platform/server/workspace-membership.ts invokes
-- abortAllWorkspaceMemberSessions(workspaceId, userId) after this
-- RPC returns (per tasks §5.5.3).
--
-- AC-FLOW4: owner cannot remove themselves. Use account-delete flow
-- for owner removal (cascades through anonymise_organization_membership).
-- Strict check is "you cannot remove an owner role" — a workspace
-- must always have at least one owner; preserving this invariant is
-- a separate concern handled at the application layer (member
-- promotion + owner demotion flow, deferred to future scope).

CREATE OR REPLACE FUNCTION public.remove_workspace_member(
  p_workspace_id uuid,
  p_user_id      uuid
) RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_user_id uuid := auth.uid();
  v_is_owner       boolean;
  v_target_role    text;
  v_rows           int;
BEGIN
  IF v_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;

  -- Authorize: caller must be an owner of the target workspace.
  SELECT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = v_caller_user_id
      AND role         = 'owner'
  ) INTO v_is_owner;

  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'caller is not an owner of workspace %', p_workspace_id
      USING ERRCODE = '42501';
  END IF;

  -- AC-FLOW4: owner cannot remove themselves.
  IF v_caller_user_id = p_user_id THEN
    RAISE EXCEPTION 'owner cannot remove themselves; use account-delete to cascade-anonymise instead'
      USING ERRCODE = '22023';
  END IF;

  -- AC-FLOW4 part 2: cannot remove another owner role (preserve
  -- workspace-has-at-least-one-owner invariant). Member-only removal.
  SELECT role INTO v_target_role
  FROM public.workspace_members
  WHERE workspace_id = p_workspace_id AND user_id = p_user_id;

  IF v_target_role IS NULL THEN
    RETURN 0;  -- already not a member; idempotent
  END IF;

  IF v_target_role = 'owner' THEN
    RAISE EXCEPTION 'cannot remove another owner; only members can be removed'
      USING ERRCODE = '22023';
  END IF;

  DELETE FROM public.workspace_members
  WHERE workspace_id = p_workspace_id AND user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.remove_workspace_member(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.remove_workspace_member(uuid, uuid)
  TO authenticated;

-- =====================================================================
-- 6. anonymise_workspace_member_attestations RPC (Art. 17 cascade)
-- =====================================================================
--
-- Clears PII columns to NULL for every attestation row where p_user_id
-- is the inviter OR the invitee. Workspace_id + accepted_at + id stay
-- intact for forensic windows. Called from account-delete.ts BEFORE
-- auth.admin.deleteUser() per ON DELETE RESTRICT FK ordering.

CREATE OR REPLACE FUNCTION public.anonymise_workspace_member_attestations(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  UPDATE public.workspace_member_attestations
     SET inviter_user_id  = NULL,
         invitee_user_id  = NULL,
         attestation_text = NULL,
         ip_hash          = NULL,
         user_agent       = NULL
   WHERE inviter_user_id = p_user_id
      OR invitee_user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_workspace_member_attestations(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_workspace_member_attestations(uuid)
  TO service_role;

-- =====================================================================
-- 7. anonymise_workspace_members RPC (Art. 17 cascade)
-- =====================================================================
--
-- Removes p_user_id's membership rows. Unlike attestations, member
-- rows have no PII to preserve — the row IS the linkage. DELETE is
-- the correct anonymise shape.
--
-- For a backfilled-solo workspace (workspace_members.user_id ==
-- workspace_id == p_user_id, role='owner'), this cascades through
-- ON DELETE RESTRICT on workspaces.organization_id → organizations,
-- so the caller (account-delete.ts) must invoke
-- anonymise_organization_membership AFTERWARD to break the chain.

CREATE OR REPLACE FUNCTION public.anonymise_workspace_members(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  DELETE FROM public.workspace_members
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_workspace_members(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_workspace_members(uuid)
  TO service_role;

-- =====================================================================
-- 8. anonymise_organization_membership RPC (Art. 17 cascade)
-- =====================================================================
--
-- For each organization where p_user_id was the owner AND the
-- organization has no remaining workspace_members (after
-- anonymise_workspace_members has run), DELETE the workspace and
-- DELETE the organization. ON DELETE RESTRICT on FKs is intentional
-- — orphaned orgs/workspaces fail loud (RAISE EXCEPTION) so the
-- caller knows to investigate.
--
-- The OWNER-of-empty-org cascade preserves the invariant: every
-- workspaces row references a live organization, every workspace_members
-- row references a live workspace, no orphan rows.

CREATE OR REPLACE FUNCTION public.anonymise_organization_membership(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_org_rec record;
  v_orgs_deleted int := 0;
  v_remaining int;
BEGIN
  -- For each org where p_user_id is the owner, check if any
  -- workspace_members remain across all of its workspaces.
  FOR v_org_rec IN
    SELECT o.id AS org_id
    FROM public.organizations o
    WHERE o.owner_user_id = p_user_id
  LOOP
    SELECT COUNT(*) INTO v_remaining
    FROM public.workspace_members m
    JOIN public.workspaces w ON w.id = m.workspace_id
    WHERE w.organization_id = v_org_rec.org_id;

    IF v_remaining = 0 THEN
      -- Orphan org. Delete workspaces, then the organization. FK is
      -- ON DELETE RESTRICT so the order matters.
      DELETE FROM public.workspaces WHERE organization_id = v_org_rec.org_id;
      DELETE FROM public.organizations WHERE id = v_org_rec.org_id;
      v_orgs_deleted := v_orgs_deleted + 1;
    ELSE
      -- Org still has members — owner_user_id NOT NULL → cannot be
      -- nulled directly because ON DELETE RESTRICT on the FK would
      -- block the eventual auth.users.delete. Reassign ownership to
      -- the oldest remaining member instead.
      UPDATE public.organizations o
         SET owner_user_id = (
           SELECT m.user_id
           FROM public.workspace_members m
           JOIN public.workspaces w ON w.id = m.workspace_id
           WHERE w.organization_id = o.id
             AND m.user_id != p_user_id
           ORDER BY m.created_at ASC
           LIMIT 1
         )
       WHERE o.id = v_org_rec.org_id;
    END IF;
  END LOOP;

  RETURN v_orgs_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_organization_membership(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_organization_membership(uuid)
  TO service_role;

COMMENT ON TABLE public.workspace_member_attestations IS
  'WORM attestation ledger for workspace-member invitations. ADR-038. '
  'PII columns (inviter_user_id, invitee_user_id, attestation_text, '
  'ip_hash, user_agent) NULL-able for Art. 17 cascade; audit lineage '
  '(id, workspace_id, accepted_at) immutable.';

COMMENT ON FUNCTION public.invite_workspace_member(uuid, uuid, text, text, text) IS
  'Owner-callable invite RPC. Inserts attestation row + workspace_members '
  'row atomically. Rejects self-invite, double-membership, missing '
  'attestation_text. ADR-038.';

COMMENT ON FUNCTION public.remove_workspace_member(uuid, uuid) IS
  'Owner-callable removal. Cannot remove self (AC-FLOW4) or another '
  'owner (preserves workspace-has-at-least-one-owner invariant). '
  'Idempotent (returns 0 if target not a member). TS wrapper at '
  'server/workspace-membership.ts invokes abortAllWorkspaceMemberSessions '
  'after return. ADR-038.';
