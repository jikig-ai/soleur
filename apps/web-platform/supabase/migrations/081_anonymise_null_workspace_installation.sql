-- 081_anonymise_null_workspace_installation.sql
-- feat-workspace-repo-ownership (#4558) — AC11 / GDPR Art-17 cascade.
--
-- ADR-044 relocated the GitHub App installation grant
-- (github_installation_id) from users to workspaces. The existing
-- anonymise_organization_membership (mig 078) does NOT null the new column,
-- so a departing user's GitHub authorization would survive their erasure on
-- every workspace they connected. The installation_id IS the departing
-- user's grant — retaining it lets the org keep acting under their GitHub
-- authorization, which Art-17 erasure must prevent.
--
-- This CREATE OR REPLACE preserves the 078 owner-transfer + orphan-org logic
-- verbatim and adds a per-org credential erasure: for every org owned by the
-- anonymised user, null github_installation_id + repo_last_synced_at and set
-- repo_status='not_connected' on that org's workspaces. repo_url is kept so a
-- promoted replacement owner can re-authorize the SAME repo with their own
-- installation.
--
-- search_path + grant shape unchanged from 078.

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

    -- AC11 (Art-17): erase the departing user's GitHub App installation
    -- grant from this org's workspaces, regardless of remaining members. A
    -- promoted replacement owner re-authorizes with their own installation.
    UPDATE public.workspaces w
       SET github_installation_id = NULL,
           repo_status            = 'not_connected',
           repo_last_synced_at    = NULL
     WHERE w.organization_id = v_org_rec.org_id
       AND w.github_installation_id IS NOT NULL;
  END LOOP;

  RETURN v_orgs_processed;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_organization_membership(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_organization_membership(uuid)
  TO service_role;
