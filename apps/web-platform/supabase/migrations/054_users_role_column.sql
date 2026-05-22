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
