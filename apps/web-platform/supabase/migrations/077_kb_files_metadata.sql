-- 077_kb_files_metadata.sql
-- Closes #4521 PR-C: KB files metadata table for uploader attribution + visibility.
--
-- Simplified per Simplicity S2: single INSERT at upload site (no sync engine).
-- content_sha256 and size_bytes dropped — no MVP consumer (Simplicity S3c).
-- visibility defaults to 'workspace' (KB is shared; conversations default to private).

-- Precondition: workspaces table exists (mig 053).
DO $$ BEGIN
  IF to_regclass('public.workspaces') IS NULL THEN
    RAISE EXCEPTION 'public.workspaces does not exist — cannot apply 077';
  END IF;
END $$;

-- =====================================================================
-- 1. Create kb_files table
-- =====================================================================

CREATE TABLE public.kb_files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  file_path text NOT NULL,
  filename text NOT NULL,
  visibility text NOT NULL CHECK (visibility IN ('private', 'workspace')) DEFAULT 'workspace',
  uploaded_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, file_path)
);

ALTER TABLE public.kb_files ENABLE ROW LEVEL SECURITY;

-- =====================================================================
-- 2. RLS policies
-- =====================================================================

-- Owner + workspace-member dual-predicate SELECT.
CREATE POLICY kb_files_owner_or_shared ON public.kb_files
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR (visibility = 'workspace' AND public.is_workspace_member(workspace_id, auth.uid()))
  );

-- Workspace members can INSERT (upload) files.
CREATE POLICY kb_files_member_insert ON public.kb_files
  FOR INSERT TO authenticated
  WITH CHECK (public.is_workspace_member(workspace_id, auth.uid()));

-- JTI deny RESTRICTIVE policy (per mig 068 pattern — Kieran H1).
CREATE POLICY kb_files_jti_not_denied ON public.kb_files
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.is_jti_denied_from_jwt())
  WITH CHECK (NOT public.is_jti_denied_from_jwt());

-- =====================================================================
-- 3. Protect authorization-sensitive columns via column-level REVOKE
-- =====================================================================
-- Per Kieran C3: prevent client UPDATE of visibility and workspace_id.
-- Only the SECURITY DEFINER RPC can change visibility.

REVOKE UPDATE(visibility, workspace_id) ON public.kb_files FROM authenticated;

-- =====================================================================
-- 4. SECURITY DEFINER RPC for visibility changes (owner-only)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.set_kb_file_visibility(
  p_file_id uuid,
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

  UPDATE public.kb_files
     SET visibility = p_visibility,
         updated_at = now()
   WHERE id = p_file_id
     AND user_id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'KB file not found or not owned by caller'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_kb_file_visibility(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_kb_file_visibility(uuid, text)
  TO authenticated;

-- =====================================================================
-- 5. Indexes
-- =====================================================================
-- Per Simplicity S3d: drop kb_files_user_idx (no query path filters by
-- user_id alone). Single workspace index covers the feed query.

CREATE INDEX kb_files_workspace_idx ON public.kb_files (workspace_id);

-- =====================================================================
-- 6. updated_at trigger (per Kieran M5)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.kb_files_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER kb_files_updated_at
  BEFORE UPDATE ON public.kb_files
  FOR EACH ROW
  EXECUTE FUNCTION public.kb_files_set_updated_at();
