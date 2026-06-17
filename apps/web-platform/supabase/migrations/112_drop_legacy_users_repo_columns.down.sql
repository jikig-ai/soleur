-- 112_drop_legacy_users_repo_columns.down.sql
-- Reverse 112 (ADR-044 PR-2b, #5437).
--
-- ⚠️ SCHEMA-ONLY rollback — column DATA is NOT recoverable. This re-creates the
--    three columns + the partial-UNIQUE index with their exact original
--    definitions, but the dropped values are GONE. The restored columns are
--    EMPTY (workspace_path takes its '' default; the other two are NULL). The
--    canonical repo-connection state lives on workspaces.* (ADR-044) — this down
--    restores the legacy shape, not the legacy data.
--
-- Original definitions restored verbatim:
--   * github_installation_id bigint                  (mig 011_repo_connection.sql:8)
--   * repo_url               text                    (mig 011_repo_connection.sql:6)
--   * workspace_path         text NOT NULL DEFAULT '' (mig 001_initial_schema.sql:9)
--   * users_github_installation_id_unique_idx        (mig 052_multi_source_dedup.sql:159-168)
--
-- workspace_path NOT NULL DEFAULT '' re-adds cleanly: all existing rows take the
-- '' default, so no backfill trap. No explicit BEGIN/COMMIT (runner wraps it).

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS github_installation_id bigint,
  ADD COLUMN IF NOT EXISTS repo_url text,
  ADD COLUMN IF NOT EXISTS workspace_path text NOT NULL DEFAULT '';

CREATE UNIQUE INDEX IF NOT EXISTS users_github_installation_id_unique_idx
  ON public.users (github_installation_id)
  WHERE github_installation_id IS NOT NULL;

COMMENT ON INDEX public.users_github_installation_id_unique_idx IS
  'PR-H (#3244) — Cross-tenant attribution guard. The GitHub webhook '
  'resolves founder via .maybeSingle() on github_installation_id; '
  'without this index a 1:N mapping (two founders, same installation) '
  'would silently route to one of them. WHERE NOT NULL keeps the '
  'constraint compatible with pre-install rows.';

-- Restore the mig-091 handle_new_user body (writes workspace_path again) in lockstep with re-adding the column.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_org_id uuid;
BEGIN
  -- 1. Insert public.users row (original 001 behavior).
  INSERT INTO public.users (id, email, workspace_path)
  VALUES (
    NEW.id,
    NEW.email,
    '/workspaces/' || NEW.id::text
  )
  ON CONFLICT (id) DO NOTHING;

  -- 2. Insert organization (default-named) for this user IF they don't
  -- already have the canary owner row. Idempotent via the same
  -- discriminator as the 053 backfill DO block.
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_members m
    WHERE m.user_id = NEW.id AND m.workspace_id = NEW.id AND m.role = 'owner'
  ) THEN
    INSERT INTO public.organizations (id, name, domain, owner_user_id)
    VALUES (gen_random_uuid(), 'My Workspace', NULL, NEW.id)
    RETURNING id INTO v_org_id;

    INSERT INTO public.workspaces (id, organization_id, name)
    VALUES (NEW.id, v_org_id, 'My Workspace')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.workspace_members (workspace_id, user_id, role, attestation_id)
    VALUES (NEW.id, NEW.id, 'owner', NULL)
    ON CONFLICT (workspace_id, user_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

-- handle_new_user is a trigger function (fires AFTER INSERT on auth.users)
-- and is not invoked via direct CALL. The REVOKE is defensive (satisfies
-- migration-rpc-grants lint + closes the direct-EXECUTE surface). Triggers
-- fire under the owner's identity regardless of EXECUTE grant, so this
-- REVOKE does NOT break signup.
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.handle_new_user() IS
  'Auth signup hook. Creates public.users row + default-named organization '
  '+ workspace (id = users.id per ADR-038 N2) + workspace_members(role=owner). '
  'Idempotent via canary owner-row discriminator + per-table ON CONFLICT DO '
  'NOTHING. SECURITY DEFINER so RLS does not block during the auth.users '
  'INSERT trigger. Default name set per feat-one-shot-workspace-untitled-name '
  '(was NULL in mig 053).';
