-- Per-user role for feature-flag targeting (ADR-038 v2).
--
-- Two-role model in V1: 'prd' (default — every user, anonymous fallback)
-- and 'dev' (beta/internal testers). Soleur skill `user-set-role` is the
-- only operational interface for promoting users into the 'dev' role; the
-- column update path is service-role-only (see trigger below).
--
-- Default 'prd' backfills every existing row with zero data motion — the
-- column add is metadata-only under Postgres 15.

alter table public.users
  add column role text not null default 'prd'
  check (role in ('prd', 'dev'));

-- The existing "Users can update own profile" policy lets a user
-- update arbitrary columns on their own row. Without the trigger below
-- a user could `update users set role='dev'` and self-promote past the
-- skill contract. Use a trigger (not WITH CHECK) so service_role bypass
-- is explicit and auditable rather than relying on RLS subquery semantics.
--
-- The original plan prescribed an additional `users_role_service_only_update`
-- RLS policy. Dropped here because (a) a permissive `using (false)` policy
-- would be a no-op alongside the existing self-update policy, (b) a
-- restrictive variant would block legitimate self-update of non-role columns,
-- and (c) Postgres has no column-level UPDATE RLS. The trigger covers the
-- intent with row-level granularity. Migration 006's column-level
-- `GRANT UPDATE (email) ON public.users TO authenticated` is the
-- belt-and-braces second defense at the GRANT layer.
--
-- INSERT path is intentionally not covered by the trigger because no RLS
-- policy grants INSERT on public.users to `anon` or `authenticated` (verified
-- against migrations 001-053). Any future INSERT policy MUST exclude `role`
-- from the inserted column list or pin it to 'prd' explicitly.
create or replace function public.users_prevent_role_self_mutation()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
begin
  -- Supabase service_role connects as the `service_role` postgres role;
  -- the SQL editor + migrations run as `postgres`. Either is allowed.
  if current_user in ('service_role', 'postgres') then
    return new;
  end if;
  if new.role is distinct from old.role then
    raise exception using
      errcode = '42501',
      message = 'role column can only be updated by the service role (use soleur:user-set-role)';
  end if;
  return new;
end;
$$;

create trigger users_prevent_role_self_mutation
  before update on public.users
  for each row execute function public.users_prevent_role_self_mutation();
