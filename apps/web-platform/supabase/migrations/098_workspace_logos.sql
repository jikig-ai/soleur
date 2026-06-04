-- 098_workspace_logos.sql
-- feat-workspace-logo-upload (#4916) — owner-uploaded custom workspace logo.
-- Adds workspaces.logo_path (object key), a private workspace-logos Storage
-- bucket, an is_workspace_owner() ownership helper, and owner-only write /
-- member-read RLS on storage.objects for that bucket.
--
-- LAWFUL_BASIS: GDPR Art. 6(1)(b) workspace-branding under the collaboration
--               contract + Art. 6(1)(f) shared-asset retention legitimate
--               interest. Retention = workspace lifetime (Art. 5(1)(e)).
-- See knowledge-base/legal/article-30-register.md PA-26.
--
-- The route writes via the service-role client (RLS-bypassing), exactly like
-- workspace/rename. These storage.objects policies are defense-in-depth for any
-- direct authenticated client-SDK access path: member read, owner-only write.
-- public.workspaces deliberately has NO client-facing INSERT/UPDATE/DELETE
-- policy (only workspaces_select_for_members), so no client SDK can set
-- logo_path to another workspace's key — the read proxy can trust it (AC5b).
--
-- Object key shape: '<workspace_id>/logo.webp'. (storage.foldername(name))[1]
-- is the workspace_id; every policy AND-guards the UUID shape with the
-- '^[0-9a-f-]{36}$' regex BEFORE the ::uuid cast so a malformed name denies
-- cleanly instead of raising 22P02 and aborting the statement (mig 068:124
-- lesson). The canonical re-encode output is always WebP, so the bucket
-- allowed_mime_types is the single value ['image/webp'].
--
-- Transaction wrapping: NO top-level BEGIN/COMMIT. The canonical migration
-- runner (apps/web-platform/scripts/run-migrations.sh) pipes the body + the
-- trailing _schema_migrations INSERT to psql --single-transaction (see mig
-- 068 header for the full rationale).

-- =====================================================================
-- 1. Column: nullable object-key pointer, no backfill.
-- =====================================================================

ALTER TABLE public.workspaces ADD COLUMN IF NOT EXISTS logo_path text;

COMMENT ON COLUMN public.workspaces.logo_path IS
  'Storage object key for the workspace logo in the workspace-logos bucket, '
  'shape ''<workspace_id>/logo.webp''. NULL = no custom logo (monogram '
  'fallback). Written only via the service-role route; never client-settable '
  '(no client write policy on public.workspaces). #4916.';

-- =====================================================================
-- 2. Private Storage bucket for workspace logos. 1 MB cap; only the
--    canonical WebP re-encode is ever uploaded, so allowed_mime_types is
--    the single value. ON CONFLICT keeps the migration idempotent.
-- =====================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'workspace-logos',
  'workspace-logos',
  false,
  1048576,
  ARRAY['image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- 3. Ownership helper. SECURITY DEFINER plpgsql (NOT sql) so planner-inlining
--    cannot dissolve the tenant-isolation boundary inside the storage RLS
--    context. search_path pinned public, pg_temp per cq-pg-security-definer-
--    search-path-pin-pg-temp. REVOKE from all four roles (defeats ALTER
--    DEFAULT PRIVILEGES) then GRANT to authenticated only.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.is_workspace_owner(
  p_workspace_id uuid,
  p_user_id      uuid
) RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_exists boolean;
BEGIN
  IF p_workspace_id IS NULL OR p_user_id IS NULL THEN
    RETURN false;
  END IF;
  SELECT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = p_user_id
      AND role         = 'owner'
  ) INTO v_exists;
  RETURN v_exists;
END;
$$;

REVOKE ALL ON FUNCTION public.is_workspace_owner(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_workspace_owner(uuid, uuid)
  TO authenticated;

COMMENT ON FUNCTION public.is_workspace_owner(uuid, uuid) IS
  'Returns TRUE if p_user_id holds role=''owner'' in workspace p_workspace_id. '
  'SECURITY DEFINER plpgsql so planner-inlining cannot dissolve the tenant '
  'boundary. Substrate for the workspace-logos storage.objects write policies '
  '(#4916). Mirrors is_workspace_member (mig 053).';

-- =====================================================================
-- 4. Storage RLS for the workspace-logos bucket. Member read; owner-only
--    write split into narrow INSERT/UPDATE/DELETE (never FOR ALL — a
--    FOR ALL USING governs writes too, per security-issues/2026-04-18-rls-
--    for-all-using-applies-to-writes.md). The UPDATE policy carries BOTH
--    USING (gates the OLD row) AND WITH CHECK (gates the NEW row) so an
--    owner of A cannot rename/move an object INTO B's prefix.
--
--    No COMMENT ON POLICY on storage.objects: the table is owned by
--    supabase_storage_admin in Supabase prd and COMMENT ON POLICY requires
--    table ownership (mig 068:158 — failed prd apply). Prose lives here.
-- =====================================================================

CREATE POLICY "Workspace members read workspace logo objects"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'workspace-logos'
    AND (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
    AND public.is_workspace_member(
      ((storage.foldername(name))[1])::uuid,
      auth.uid()
    )
  );

CREATE POLICY "Workspace owners write logo objects only (insert)"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'workspace-logos'
    AND (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
    AND public.is_workspace_owner(
      ((storage.foldername(name))[1])::uuid,
      auth.uid()
    )
  );

CREATE POLICY "Workspace owners write logo objects only (update)"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'workspace-logos'
    AND (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
    AND public.is_workspace_owner(
      ((storage.foldername(name))[1])::uuid,
      auth.uid()
    )
  )
  WITH CHECK (
    bucket_id = 'workspace-logos'
    AND (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
    AND public.is_workspace_owner(
      ((storage.foldername(name))[1])::uuid,
      auth.uid()
    )
  );

CREATE POLICY "Workspace owners write logo objects only (delete)"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'workspace-logos'
    AND (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
    AND public.is_workspace_owner(
      ((storage.foldername(name))[1])::uuid,
      auth.uid()
    )
  );
