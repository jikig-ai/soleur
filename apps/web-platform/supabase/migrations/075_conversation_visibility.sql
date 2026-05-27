-- 075_conversation_visibility.sql
-- Closes #4521 PR-A: per-conversation visibility controls.
--
-- Adds a visibility column to conversations (default 'private') so workspace
-- members only see conversations the owner has explicitly shared. Replaces
-- the unconditional workspace-wide policy from mig 059 with a dual-predicate
-- policy: owner OR (shared AND workspace member).
--
-- Brand-survival threshold: single-user incident.
-- Plan review: 3 CRITICAL fixes applied (C1 FK syntax, C2 RPC auth, C3 RESTRICTIVE → REVOKE).

-- Precondition: conversations table exists (mig 001).
DO $$ BEGIN
  IF to_regclass('public.conversations') IS NULL THEN
    RAISE EXCEPTION 'public.conversations does not exist — cannot apply 075';
  END IF;
END $$;

-- =====================================================================
-- 1. Add visibility column
-- =====================================================================

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS visibility text
  CHECK (visibility IN ('private', 'workspace'))
  DEFAULT 'private';

UPDATE public.conversations SET visibility = 'private' WHERE visibility IS NULL;
ALTER TABLE public.conversations ALTER COLUMN visibility SET NOT NULL;

-- =====================================================================
-- 2. Protect visibility column via column-level REVOKE
-- =====================================================================
-- Per Kieran C3: self-referential RESTRICTIVE WITH CHECK compares NEW vs NEW
-- (always true). Column-level REVOKE is the correct defense — only the
-- SECURITY DEFINER RPC (running as function owner) can UPDATE this column.

REVOKE UPDATE(visibility) ON public.conversations FROM authenticated;

-- =====================================================================
-- 3. Replace unconditional workspace-wide policy with dual-predicate
-- =====================================================================

DROP POLICY IF EXISTS conversations_workspace_member_all ON public.conversations;

-- P1 review fix: split into per-operation policies to prevent workspace
-- members from mutating (UPDATE/DELETE) other users' shared conversations.
-- SELECT: owner OR workspace-shared (dual-predicate).
-- INSERT: owner only (user_id = auth.uid()) — prevents impersonation.
-- UPDATE/DELETE: owner only — workspace members can READ but not MUTATE.
-- Two separate PERMISSIVE policies instead of a single OR-predicate.
-- Postgres ORs PERMISSIVE policies together, enabling BitmapOr of two
-- independent index scans. This avoids calling is_workspace_member()
-- per-row for owned conversations (the hot path).
CREATE POLICY conversations_owner_select ON public.conversations
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY conversations_shared_select ON public.conversations
  FOR SELECT TO authenticated
  USING (visibility = 'workspace' AND public.is_workspace_member(workspace_id, auth.uid()));

CREATE POLICY conversations_owner_insert ON public.conversations
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY conversations_owner_update ON public.conversations
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY conversations_owner_delete ON public.conversations
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- =====================================================================
-- 4. SECURITY DEFINER RPC for visibility changes (owner-only)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.set_conversation_visibility(
  p_conversation_id uuid,
  p_visibility text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_visibility NOT IN ('private', 'workspace') THEN
    RAISE EXCEPTION 'Invalid visibility value: %', p_visibility
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.conversations
     SET visibility = p_visibility
   WHERE id = p_conversation_id
     AND user_id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conversation not found or not owned by caller'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_conversation_visibility(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_conversation_visibility(uuid, text)
  TO authenticated;

-- =====================================================================
-- 5. Index for shared-conversation queries
-- =====================================================================

CREATE INDEX IF NOT EXISTS conversations_visibility_workspace_idx
  ON public.conversations (workspace_id)
  WHERE visibility = 'workspace';
