-- Migration 072: workspace_member_actions.workspace_id SET NULL + WORM carve-out
--
-- Closes #4355 (workspace_member_actions.workspace_id ON DELETE RESTRICT
-- blocks future workspace deletion). Sister to mig 062 (workspace_member_
-- removals.workspace_id SET NULL) and mig 065/066 (organizations +
-- audit_byok_use cascade deadlock repair).
--
-- Changes:
--   1. DROP NOT NULL on workspace_id (allows NULL for orphan-workspace cleanup).
--   2. DROP + re-ADD FK with ON DELETE SET NULL (was RESTRICT).
--   3. REPLACE workspace_member_actions_no_mutate with structural-shape WORM
--      trigger recognising Art. 17 anonymise + ON DELETE SET NULL transitions
--      (per mig 062 pattern).
--
-- The existing anonymise_workspace_member_actions + purge_workspace_member_
-- actions RPCs are UNCHANGED — both use SET LOCAL session_replication_role=
-- 'replica' which bypasses the trigger entirely (ENABLE ORIGIN default).
-- The structural-shape carve-out is defense-in-depth for the FK-cascade
-- SET NULL path (fires WITHOUT session_replication_role).
--
-- Ref #4299 (workspace_members.user_id RESTRICT — verified already handled
-- by existing step 3.91 anonymise_workspace_members).

-- =====================================================================
-- 0. Schema preconditions
-- =====================================================================

DO $$
BEGIN
  IF to_regclass('public.workspace_member_actions') IS NULL THEN
    RAISE EXCEPTION 'precondition failed: public.workspace_member_actions does not exist';
  END IF;
  IF to_regclass('public.workspaces') IS NULL THEN
    RAISE EXCEPTION 'precondition failed: public.workspaces does not exist';
  END IF;
END;
$$;

-- =====================================================================
-- 1. DROP NOT NULL on workspace_id
-- =====================================================================

ALTER TABLE public.workspace_member_actions
  ALTER COLUMN workspace_id DROP NOT NULL;

-- =====================================================================
-- 2. Drop and re-add FK with ON DELETE SET NULL
-- =====================================================================

ALTER TABLE public.workspace_member_actions
  DROP CONSTRAINT workspace_member_actions_workspace_id_fkey;

ALTER TABLE public.workspace_member_actions
  ADD CONSTRAINT workspace_member_actions_workspace_id_fkey
    FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id)
    ON DELETE SET NULL;

-- =====================================================================
-- 3. Structural-shape WORM trigger (replaces pure-reject from mig 063)
-- =====================================================================
--
-- Pattern source: mig 062 workspace_member_removals_no_mutate (lines
-- 140-212). Per-column NOT NULL → NULL recognition for PII columns +
-- workspace_id. Audit lineage (id, action_type, old_role, new_role,
-- created_at, attestation_id) is immutable.
--
-- Expected column set (mig 072): id, workspace_id, actor_user_id,
-- target_user_id, action_type, old_role, new_role, attestation_id,
-- created_at. If a future migration adds columns, update this trigger.
--
-- No session_replication_role check in the trigger body per learning
-- 2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-
-- routing.md.

CREATE OR REPLACE FUNCTION public.workspace_member_actions_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
BEGIN
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
$$;

-- Revoke from all roles — the trigger runs automatically; no role needs
-- direct EXECUTE on the function.
REVOKE ALL ON FUNCTION public.workspace_member_actions_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

-- No trigger re-creation needed — existing triggers (workspace_member_
-- actions_no_update + workspace_member_actions_no_delete from mig 063)
-- reference the function by name; CREATE OR REPLACE updates the body
-- in-place.

-- =====================================================================
-- 4. COMMENT update
-- =====================================================================

COMMENT ON FUNCTION public.workspace_member_actions_no_mutate() IS
  'WORM trigger (BEFORE UPDATE/DELETE) for workspace_member_actions. '
  'DELETE: pure-reject (retention purge bypasses via session_replication_role). '
  'UPDATE: audit lineage (id, action_type, old_role, new_role, created_at, '
  'attestation_id) immutable; workspace_id + PII columns (actor_user_id, '
  'target_user_id) permit NOT NULL → NULL transition only (Art. 17 anonymise '
  'and ON DELETE SET NULL cascade). Pattern: mig 062. #4355.';
