-- Plan-based conversation concurrency enforcement.
--
-- Adds plan_tier / concurrency_override / subscription_downgraded_at to
-- users; folds in #2188 by adding a unique partial index on
-- stripe_customer_id WHERE NOT NULL. Creates user_concurrency_slots with
-- RLS and two SECURITY DEFINER RPCs (acquire + release) plus a pg_cron
-- scheduled sweep (no-op if pg_cron is not enabled on the target project).
--
-- CONCURRENTLY is NOT used — Supabase wraps each migration in a txn and
-- CREATE INDEX CONCURRENTLY fails with SQLSTATE 25001. See 025/027/028.

alter table public.users
  add column if not exists plan_tier text not null default 'free'
    check (plan_tier in ('free','solo','startup','scale','enterprise')),
  add column if not exists concurrency_override integer null
    check (concurrency_override is null or concurrency_override >= 0),
  add column if not exists subscription_downgraded_at timestamptz null;

-- Folds in #2188. Partial so pre-Stripe rows (NULL customer_id) don't collide.
create unique index if not exists users_stripe_customer_id_unique
  on public.users (stripe_customer_id)
  where stripe_customer_id is not null;

create table if not exists public.user_concurrency_slots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  conversation_id uuid not null,
  started_at timestamptz not null default now(),
  last_heartbeat_at timestamptz not null default now(),
  unique (user_id, conversation_id)
);

create index if not exists user_concurrency_slots_user_heartbeat_idx
  on public.user_concurrency_slots (user_id, last_heartbeat_at);

alter table public.user_concurrency_slots enable row level security;

-- Owner-only SELECT. Writes go through SECURITY DEFINER RPCs below — no
-- INSERT/UPDATE/DELETE policies on purpose. `FOR ALL USING` would apply to
-- writes too (see rf-rls-for-all-using-applies-to-writes).
drop policy if exists slots_owner_read on public.user_concurrency_slots;
create policy slots_owner_read on public.user_concurrency_slots
  for select using (auth.uid() = user_id);

-- Acquire: per-user FOR UPDATE serializes same-user acquires. Lazy sweep
-- before counting so orphaned rows don't starve legitimate acquires.
-- Returns TABLE(status, active_count, effective_cap). Status is 'ok' or
-- 'cap_hit'. On cap_hit the inserted row is rolled back and active_count
-- reflects pre-insert state.
create or replace function public.acquire_conversation_slot(
  p_user_id uuid,
  p_conversation_id uuid,
  p_effective_cap integer
) returns table (status text, active_count integer, effective_cap integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer;
  v_was_insert boolean;
begin
  -- Txn-scoped lock timeout. set_config(..., true) is is_local=true and
  -- applies only to the current transaction — SET LOCAL would no-op outside
  -- an explicit BEGIN (we rely on implicit-txn mode in PostgREST RPC calls).
  perform set_config('lock_timeout', '500ms', true);

  -- Serialize same-user acquires to avoid a TOCTOU between COUNT and INSERT.
  perform 1 from public.users where id = p_user_id for update;

  -- Lazy sweep. 120s threshold matches the pg_cron schedule below so a
  -- crashed WS can reclaim a slot on reconnect even before cron runs.
  delete from public.user_concurrency_slots
  where user_id = p_user_id
    and last_heartbeat_at < now() - interval '120 seconds';

  insert into public.user_concurrency_slots (user_id, conversation_id)
  values (p_user_id, p_conversation_id)
  on conflict (user_id, conversation_id)
    do update set last_heartbeat_at = now()
  returning (xmax = 0) into v_was_insert;

  select count(*) into v_count
    from public.user_concurrency_slots where user_id = p_user_id;

  if v_count > p_effective_cap and v_was_insert then
    delete from public.user_concurrency_slots
    where user_id = p_user_id and conversation_id = p_conversation_id;
    status := 'cap_hit';
    active_count := v_count - 1;
    effective_cap := p_effective_cap;
    return next;
    return;
  end if;

  status := 'ok';
  active_count := v_count;
  effective_cap := p_effective_cap;
  return next;
end;
$$;

create or replace function public.release_conversation_slot(
  p_user_id uuid,
  p_conversation_id uuid
) returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  delete from public.user_concurrency_slots
  where user_id = p_user_id and conversation_id = p_conversation_id;
$$;

revoke all on function public.acquire_conversation_slot(uuid, uuid, integer) from public;
revoke all on function public.release_conversation_slot(uuid, uuid) from public;
grant execute on function public.acquire_conversation_slot(uuid, uuid, integer) to service_role;
grant execute on function public.release_conversation_slot(uuid, uuid) to service_role;

-- pg_cron sweep. Guarded so the migration does not fail if pg_cron is not
-- enabled on a given project (e.g., local dev). Post-merge ops checks that
-- the job is alive on prd (see Acceptance Criteria post-merge list).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'user_concurrency_slots_sweep',
      '* * * * *',
      $sweep$
        delete from public.user_concurrency_slots
        where last_heartbeat_at < now() - interval '120 seconds';
      $sweep$
    );
  end if;
end $$;
