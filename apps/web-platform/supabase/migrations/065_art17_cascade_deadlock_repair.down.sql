-- Down migration for 065: restore the RESTRICT FKs and the orphan-delete
-- path in anonymise_organization_membership.
--
-- WARNING: applying this down migration re-introduces the Art. 17 cascade
-- deadlock described in 065. Rolling forward (forward migration succeeds,
-- prd is on mig 065) is the canonical recovery path.

-- Part 3 inverse: restore anonymise_organization_membership orphan-delete path
-- (mig 058:419 verbatim body).
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
      DELETE FROM public.workspaces WHERE organization_id = v_org_rec.org_id;
      DELETE FROM public.organizations WHERE id = v_org_rec.org_id;
      v_orgs_deleted := v_orgs_deleted + 1;
    ELSE
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

-- Part 2 inverse: audit_byok_use.founder_id SET NULL → RESTRICT + NOT NULL.
-- Requires any NULL rows to be removed first (audit rows from Art-17-
-- anonymised users post-065). DELETE NULL rows to satisfy NOT NULL.
DELETE FROM public.audit_byok_use WHERE founder_id IS NULL;

ALTER TABLE public.audit_byok_use
  DROP CONSTRAINT IF EXISTS audit_byok_use_founder_id_fkey;

ALTER TABLE public.audit_byok_use
  ADD CONSTRAINT audit_byok_use_founder_id_fkey
  FOREIGN KEY (founder_id) REFERENCES public.users(id) ON DELETE RESTRICT;

ALTER TABLE public.audit_byok_use
  ALTER COLUMN founder_id SET NOT NULL;

-- Part 1 inverse: organizations.owner_user_id SET NULL → RESTRICT + NOT NULL.
-- DELETE NULL rows similarly.
DELETE FROM public.organizations WHERE owner_user_id IS NULL;

ALTER TABLE public.organizations
  DROP CONSTRAINT IF EXISTS organizations_owner_user_id_fkey;

ALTER TABLE public.organizations
  ADD CONSTRAINT organizations_owner_user_id_fkey
  FOREIGN KEY (owner_user_id) REFERENCES public.users(id) ON DELETE RESTRICT;

ALTER TABLE public.organizations
  ALTER COLUMN owner_user_id SET NOT NULL;
