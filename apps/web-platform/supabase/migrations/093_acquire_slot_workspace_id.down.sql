-- =====================================================================
-- 093_acquire_slot_workspace_id.down.sql
-- =====================================================================
--
-- Drops the 4-arg overload and restores the verbatim pre-093 (3-arg) body
-- from 029_plan_tier_and_concurrency_slots.sql:101-166 + its grants.
--
-- IMPORTANT CAVEAT (knowingly-broken): applying this down migration WHILE the
-- migration-059 `user_concurrency_slots.workspace_id` NOT NULL constraint is
-- still in place leaves the database in a knowingly-broken state — every
-- NEW-conversation acquire will again fail with SQLSTATE 23502 because the
-- restored 3-arg body does NOT populate workspace_id. This is acceptable for
-- rollback semantics (the operator is reverting toward the pre-093 broken
-- state that the Sentry incident reported); the up-migration is the canonical
-- path forward. Do NOT run this in production except as a controlled
-- regression test. Mirrors the 063_post_workspace_rpc_repair.down.sql
-- convention.
-- =====================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.acquire_conversation_slot(uuid, uuid, integer, uuid);

-- Verbatim restore of the 3-arg body from
-- 029_plan_tier_and_concurrency_slots.sql:95-166 (inline comments included).
-- Acquire: per-user advisory xact lock serializes same-user acquires without
-- touching the hot users table. Lazy sweep before counting so orphaned rows
-- don't starve legitimate acquires.
-- Returns TABLE(status, active_count, effective_cap). Status is 'ok' or
-- 'cap_hit'. On cap_hit the inserted row is rolled back and active_count
-- reflects pre-insert state.
CREATE FUNCTION public.acquire_conversation_slot(
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

revoke all on function public.acquire_conversation_slot(uuid, uuid, integer) from public;
grant execute on function public.acquire_conversation_slot(uuid, uuid, integer) to service_role;

COMMIT;
