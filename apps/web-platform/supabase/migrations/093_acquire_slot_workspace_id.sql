-- 093_acquire_slot_workspace_id.sql
-- fix: acquire_conversation_slot 23502 — RPC INSERT missing workspace_id.
--
-- Sentry `concurrency silent fallback` (issue 52442f7a9b77462b9927b1f055204cce):
--   feature=concurrency op=acquireSlot pg_code=23502 (not_null_violation).
--
-- Root cause: migration 059_workspace_keyed_rls_sweep.sql:206/223 added
-- `user_concurrency_slots.workspace_id uuid` (no DEFAULT) and `SET NOT NULL`,
-- but the only writer that INSERTs new slot rows —
-- `public.acquire_conversation_slot`, defined in
-- 029_plan_tier_and_concurrency_slots.sql:101 — was never re-issued. Its
-- INSERT supplied only (user_id, conversation_id), so workspace_id fell to
-- NULL and every NEW-conversation acquire failed the NOT NULL constraint with
-- SQLSTATE 23502. The TS wrapper (server/concurrency.ts) caught it, fired
-- reportSilentFallback, and returned status="error", which ws-handler.ts
-- treats fail-closed (CONCURRENCY_CAP) — silently denying every new
-- conversation. This is the residual "Class D" that the post-mig-059 sweep
-- (PR #4343 / #4356) missed for the slots table.
-- See knowledge-base/project/learnings/2026-05-22-tenant-integration-runtime-failures-post-mig-059.md.
--
-- Approach (mirrors the mig-061 byok precedent — record_byok_use_and_check_cap
-- / write_byok_audit were widened to a p_workspace_id arg when audit_byok_use
-- gained workspace_id NOT NULL in mig 055): DROP the 3-arg function and CREATE
-- a 4-arg overload with `p_workspace_id uuid`. A changed arg list under
-- CREATE OR REPLACE would create a NEW overload and leave the stale 3-arg
-- function (and its grant) in place, so the DROP is load-bearing.
--
-- The caller (server/ws-handler.ts) passes getUserWorkspace(userId) — the
-- same session-cached active workspace that createConversation writes to the
-- conversation row (ws-handler.ts:808-819) — so slot.workspace_id ==
-- conversation.workspace_id, the equality that find_stuck_active_conversations
-- (037) and the RLS member-select (059:227) both assume.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: SET search_path =
-- public, pg_temp pinned. FORWARD-ONLY; non-transactional-unsafe statements
-- (CREATE INDEX CONCURRENTLY / VACUUM / ALTER SYSTEM) are absent, so this runs
-- inside Supabase's per-migration transaction wrapper.

BEGIN;

-- DROP the old 3-arg overload (arg list changes → new function, not a replace).
DROP FUNCTION IF EXISTS public.acquire_conversation_slot(uuid, uuid, integer);

-- Acquire: per-user advisory xact lock serializes same-user acquires without
-- touching the hot users table. Lazy sweep before counting so orphaned rows
-- don't starve legitimate acquires.
-- Returns TABLE(status, active_count, effective_cap). Status is 'ok' or
-- 'cap_hit'. On cap_hit the inserted row is rolled back and active_count
-- reflects pre-insert state.
CREATE FUNCTION public.acquire_conversation_slot(
  p_user_id uuid,
  p_conversation_id uuid,
  p_effective_cap integer,
  p_workspace_id uuid
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

  -- workspace_id added to the INSERT column list (the mig-059 NOT NULL fix).
  -- Value is the caller-supplied active workspace (== the conversation's
  -- workspace_id). Do NOT add workspace_id to `do update set` — an existing
  -- row keeps its backfilled value.
  insert into public.user_concurrency_slots (user_id, conversation_id, workspace_id)
  values (p_user_id, p_conversation_id, p_workspace_id)
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

-- Re-issue grants for the NEW 4-arg signature (the DROP removed the 3-arg
-- function and its grant; nothing carries over to a different arg list).
revoke all on function public.acquire_conversation_slot(uuid, uuid, integer, uuid) from public;
grant execute on function public.acquire_conversation_slot(uuid, uuid, integer, uuid) to service_role;

COMMENT ON FUNCTION public.acquire_conversation_slot(uuid, uuid, integer, uuid) IS
  'Service-role-only slot writer for user_concurrency_slots. Re-issued in '
  'mig 093 with p_workspace_id (4th arg) to populate the workspace_id NOT '
  'NULL column added in mig 059 — closes Sentry 23502 acquireSlot. The '
  'caller passes the session-active workspace so slot.workspace_id == '
  'conversation.workspace_id.';

COMMIT;
