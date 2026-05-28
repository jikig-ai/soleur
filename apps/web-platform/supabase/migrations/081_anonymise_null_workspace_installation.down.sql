-- 081_anonymise_null_workspace_installation.down.sql
-- Revert anonymise_organization_membership to the exact migration-078 body
-- (no workspaces.github_installation_id erasure).

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
