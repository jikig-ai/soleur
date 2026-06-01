-- Down-migration for 091_rename_organization_and_default_names.
-- Drops the rename_organization RPC and restores the 053 handle_new_user
-- body (NULL default names). The backfill is NOT reverted — organization /
-- workspace names are user data; restoring them to NULL would destroy
-- user-supplied content. Provided for reversibility symmetry of the
-- schema-level objects only.

DROP FUNCTION IF EXISTS public.rename_organization(uuid, text, uuid);

-- Restore handle_new_user to the 053:289-329 body (NULL name literals).
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_org_id uuid;
BEGIN
  INSERT INTO public.users (id, email, workspace_path)
  VALUES (
    NEW.id,
    NEW.email,
    '/workspaces/' || NEW.id::text
  )
  ON CONFLICT (id) DO NOTHING;

  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_members m
    WHERE m.user_id = NEW.id AND m.workspace_id = NEW.id AND m.role = 'owner'
  ) THEN
    INSERT INTO public.organizations (id, name, domain, owner_user_id)
    VALUES (gen_random_uuid(), NULL, NULL, NEW.id)
    RETURNING id INTO v_org_id;

    INSERT INTO public.workspaces (id, organization_id, name)
    VALUES (NEW.id, v_org_id, NULL)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.workspace_members (workspace_id, user_id, role, attestation_id)
    VALUES (NEW.id, NEW.id, 'owner', NULL)
    ON CONFLICT (workspace_id, user_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated, service_role;
