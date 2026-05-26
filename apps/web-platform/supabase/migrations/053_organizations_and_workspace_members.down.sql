-- 053_organizations_and_workspace_members.down.sql
-- feat-team-workspace-multi-user (#4229, PR #4225) — reverse migration.
-- Restores pre-053 state.
--
-- ORDER MATTERS: drop dependents before dependencies. Policies →
-- index → tables → helper function. handle_new_user reverts to the
-- 001_initial_schema.sql shape (public.users INSERT only; no
-- organizations / workspace / workspace_members inserts).
--
-- Run from rollback.md Step 2 if migrations 054, 055, 056 have ALREADY
-- been rolled back. This is the deepest down-migration in the
-- team-workspace stack — do not run unless 056 → 055 → 054 are gone.

-- 1. Drop RLS policies (must precede DROP FUNCTION since they
-- reference is_workspace_member).
DROP POLICY IF EXISTS orgs_select_for_members       ON public.organizations;
DROP POLICY IF EXISTS workspaces_select_for_members ON public.workspaces;
DROP POLICY IF EXISTS members_select_peers          ON public.workspace_members;

-- 2. Drop helper function.
DROP FUNCTION IF EXISTS public.is_workspace_member(uuid, uuid);

-- 3. Drop tables (workspace_members → workspaces → organizations
-- because of FK ordering).
DROP INDEX IF EXISTS public.workspace_members_user_id_idx;
DROP TABLE IF EXISTS public.workspace_members;
DROP TABLE IF EXISTS public.workspaces;
DROP TABLE IF EXISTS public.organizations;

-- 4. Restore handle_new_user to its 001_initial_schema.sql shape:
-- public.users INSERT only, no org/workspace/member inserts.
-- Syntactic shape matches 001 exactly (SECURITY DEFINER after the
-- $$ body close, not in the declaration block) so the
-- migration-rpc-grants lint regex does not match (it requires
-- SECURITY DEFINER between the function signature and AS $$).
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, email, workspace_path)
  values (
    new.id,
    new.email,
    '/workspaces/' || new.id::text
  );
  return new;
end;
$$ language plpgsql security definer;
