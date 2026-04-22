-- Plan-based conversation concurrency enforcement.
--
-- Adds plan_tier / concurrency_override / subscription_downgraded_at to
-- users; folds in #2188 by adding a unique partial index on
-- stripe_customer_id WHERE NOT NULL. Creates user_concurrency_slots with
-- RLS and two SECURITY DEFINER RPCs (acquire + release) plus a pg_cron
-- scheduled sweep.
--
-- FORWARD-ONLY: This migration is not cleanly reversible. The webhook at
-- app/api/webhooks/stripe/route.ts and server/concurrency.ts unconditionally
-- reference plan_tier, concurrency_override, subscription_downgraded_at,
-- and the two RPCs — dropping any of them will 500 the Stripe webhook.
-- Rollback procedure: revert the code PR first, then drop SQL. See
-- knowledge-base/engineering/ops/runbooks/supabase-migrations.md.
--
-- CONCURRENTLY is NOT used — Supabase wraps each migration in a txn and
-- CREATE INDEX CONCURRENTLY fails with SQLSTATE 25001. See 025/027/028.

-- Ensure pg_cron is present before the schedule block below. Supabase
-- allowlists pg_cron in its extension schema; idempotent on projects that
-- already have it. Extension creation is non-blocking here so the schedule
-- block at the bottom can run unconditionally.
create extension if not exists pg_cron with schema extensions;

-- Pre-flight: fail loud if a duplicate stripe_customer_id exists. Closes the
-- preflight → apply race window (a webhook arriving between the operator's
-- duplicate-check query and this migration could insert a violating row; the
-- `CREATE UNIQUE INDEX` below would then fail mid-txn with an opaque error).
do $$
declare
  v_dup_count integer;
begin
  select count(*) into v_dup_count from (
    select stripe_customer_id
    from public.users
    where stripe_customer_id is not null
    group by stripe_customer_id
    having count(*) > 1
  ) t;
  if v_dup_count > 0 then
    raise exception 'Migration 029 aborted: % duplicate stripe_customer_id value(s) in public.users. Resolve duplicates before re-running.', v_dup_count;
  end if;
end $$;

alter table public.users
  add column if not exists plan_tier text not null default 'free'
    check (plan_tier in ('free','solo','startup','scale','enterprise')),
  add column if not exists concurrency_override integer null
    check (concurrency_override is null or (concurrency_override >= 0 and concurrency_override <= 100)),
  add column if not exists subscription_downgraded_at timestamptz null;

-- One-time backfill for existing paying users. The schema defaults plan_tier
-- to 'free' — which is wrong for any row with an active/trialing Stripe
-- subscription: it would cap them at 1 concurrent conversation until the
-- next customer.subscription.* webhook fires (possibly days on an annual
-- plan). We set such rows to 'enterprise' as the most-generous floor so
-- in-flight paying users lose no capacity on deploy; the real tier is
-- re-derived from items[0].price.id the next time Stripe emits an event.
-- Pre-beta production has exactly 1 row matching this predicate (a known
-- internal/founder account that warrants Enterprise caps regardless).
-- Post-beta, operate a Stripe event replay from the Dashboard if the
-- default-to-Enterprise preserves capacity but not exact tier mapping.
update public.users
set plan_tier = 'enterprise'
where subscription_status in ('active','trialing')
  and stripe_subscription_id is not null
  and plan_tier = 'free';

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

-- Acquire: per-user advisory xact lock serializes same-user acquires without
-- touching the hot users table. Lazy sweep before counting so orphaned rows
-- don't starve legitimate acquires.
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
  v_existing_conv uuid;
begin
  -- Txn-scoped lock timeout. set_config(..., true) is is_local=true and
  -- applies only to the current transaction — SET LOCAL would no-op outside
  -- an explicit BEGIN (we rely on implicit-txn mode in PostgREST RPC calls).
  perform set_config('lock_timeout', '500ms', true);

  -- Serialize same-user acquires via advisory xact lock keyed on the user
  -- UUID. Previously used `SELECT FROM users FOR UPDATE` but that shares a
  -- hot row with the Stripe webhook's plan_tier writes, creating lock
  -- contention at scale. Advisory locks are release-on-commit automatic,
  -- same user still serialized, different users never contend.
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

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

  -- Cap-check must fire regardless of v_was_insert. If an idempotent retry
  -- arrives AFTER a downgrade webhook lowered p_effective_cap, the original
  -- row already exists (v_was_insert=false) but v_count still exceeds the
  -- new cap — we must reject and sweep THIS conversation's slot so the user
  -- reconnects at the new cap on the next start_session. Previously this
  -- branch was gated behind `and v_was_insert`, which silently leaked slots
  -- above cap after a downgrade.
  if v_count > p_effective_cap then
    delete from public.user_concurrency_slots
    where user_id = p_user_id and conversation_id = p_conversation_id;
    status := 'cap_hit';
    -- active_count is the count AFTER this conversation's slot is removed,
    -- regardless of whether we inserted it now or it existed before.
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

-- Heartbeat-only: refresh last_heartbeat_at for an existing slot without
-- re-running the cap check, the lazy sweep, or the advisory lock. Used by
-- the WS ping interval — called once per 30s per live session. Keeping this
-- cheap matters because at N live sessions we pay N/30 writes/s steady-state.
-- Returns the number of rows updated so callers can detect stale/evicted slots
-- (0 = slot was swept; client should trigger a fresh acquire on reconnect).
create or replace function public.touch_conversation_slot(
  p_user_id uuid,
  p_conversation_id uuid
) returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_updated integer;
begin
  update public.user_concurrency_slots
  set last_heartbeat_at = now()
  where user_id = p_user_id and conversation_id = p_conversation_id;
  get diagnostics v_updated = row_count;
  return v_updated;
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
revoke all on function public.touch_conversation_slot(uuid, uuid) from public;
grant execute on function public.acquire_conversation_slot(uuid, uuid, integer) to service_role;
grant execute on function public.release_conversation_slot(uuid, uuid) to service_role;
grant execute on function public.touch_conversation_slot(uuid, uuid) to service_role;

-- pg_cron sweep. The CREATE EXTENSION at the top of this migration makes
-- pg_cron a hard dependency (prior versions of this file no-op'd if absent).
-- Supabase allowlists pg_cron; local dev using plain postgres needs
-- `shared_preload_libraries = 'pg_cron'` in postgresql.conf — otherwise this
-- block errors and the migration fails fast (intended: the in-RPC lazy
-- sweep only fires on the SAME user's next acquire, so a user who abandoned
-- a session and never returns leaves a slot occupied until cron runs).
select cron.schedule(
  'user_concurrency_slots_sweep',
  '* * * * *',
  $sweep$
    delete from public.user_concurrency_slots
    where last_heartbeat_at < now() - interval '120 seconds';
  $sweep$
);
