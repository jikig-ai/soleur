-- Reverse 054_users_role_column.sql.

drop trigger if exists users_prevent_role_self_mutation on public.users;
drop function if exists public.users_prevent_role_self_mutation();
alter table public.users drop column if exists role;
