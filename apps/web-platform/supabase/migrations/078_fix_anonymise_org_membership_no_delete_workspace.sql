-- 078_fix_anonymise_org_membership_no_delete_workspace.sql
--
-- Fixes #4551: 075_transfer_workspace_ownership.sql introduced an explicit
-- DELETE FROM workspaces for orphan orgs (v_remaining = 0). But 10+ tables
-- reference workspaces(id) ON DELETE RESTRICT (mig 059), so the DELETE
-- fails for any user with conversations, scope_grants, etc.
--
-- Restore the mig 065 design: orphan orgs stay alive with owner_user_id
-- SET NULL via the cascade from auth.users delete. The workspace-role
-- promotion logic for multi-member orgs (the #4520 fix) is preserved.

CREATE OR REPLACE FUNCTION public.anonymise_organization_membership(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_org_rec record;
  v_orgs_processed int := 0;
  v_remaining int;
  v_replacement_user_id uuid;
BEGIN
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
      -- Orphan org: no members remain. Do NOT delete workspace or org —
      -- many tables reference workspaces(id) ON DELETE RESTRICT. Rely on
      -- the SET NULL cascade from auth.users delete (mig 065 Part 1:
      -- organizations.owner_user_id ON DELETE SET NULL).
      v_orgs_processed := v_orgs_processed + 1;
    ELSE
      SELECT m.user_id INTO v_replacement_user_id
        FROM public.workspace_members m
        JOIN public.workspaces w ON w.id = m.workspace_id
       WHERE w.organization_id = v_org_rec.org_id
         AND m.user_id != p_user_id
       ORDER BY m.created_at ASC
       LIMIT 1;

      UPDATE public.organizations o
         SET owner_user_id = v_replacement_user_id
       WHERE o.id = v_org_rec.org_id;

      -- #4520 fix: promote replacement member's workspace_members.role
      IF v_replacement_user_id IS NOT NULL THEN
        UPDATE public.workspace_members m
           SET role = 'owner',
               attestation_id = NULL
         WHERE m.user_id = v_replacement_user_id
           AND m.workspace_id IN (
             SELECT w.id FROM public.workspaces w
              WHERE w.organization_id = v_org_rec.org_id
           );
      END IF;
    END IF;
  END LOOP;

  RETURN v_orgs_processed;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_organization_membership(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_organization_membership(uuid)
  TO service_role;
