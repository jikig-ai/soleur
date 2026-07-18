-- 133_heartbeat_threshold_backoff.down.sql
-- Restore all four liveness thresholds to the pre-133 LIVE state (120 s),
-- reproducing the bodies of migrations 093 (acquire_conversation_slot),
-- 115 (user_concurrency_slots_sweep at '0 * * * *' — NOT 029's per-minute),
-- 037 (find_stuck_active_conversations default 120), and 116
-- (acquire_worktree_lease). Body-only CREATE OR REPLACE preserves ACL; no
-- GRANTs re-emitted (128's anon/authenticated revokes stay in force).
--
-- ROLLBACK ORDERING (Sharp Edge E5): if reverting the whole PR, redeploy the
-- OLD 30 s-heartbeat code BEFORE applying this down file — otherwise the live
-- 60 s-heartbeat code runs against the restored 120 s threshold (2 missed-beat
-- tolerance) and can false-reap a session that pauses ~120 s.

CREATE OR REPLACE FUNCTION public.acquire_conversation_slot(
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
  perform set_config('lock_timeout', '500ms', true);
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 0));

  -- Lazy sweep. 120s threshold matches the pg_cron schedule below.
  delete from public.user_concurrency_slots
  where user_id = p_user_id
    and last_heartbeat_at < now() - interval '120 seconds';

  insert into public.user_concurrency_slots (user_id, conversation_id, workspace_id)
  values (p_user_id, p_conversation_id, p_workspace_id)
  on conflict (user_id, conversation_id)
    do update set last_heartbeat_at = now()
  returning (xmax = 0) into v_was_insert;

  select count(*) into v_count
    from public.user_concurrency_slots where user_id = p_user_id;

  if v_count > p_effective_cap then
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

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'user_concurrency_slots_sweep') THEN
    PERFORM cron.unschedule('user_concurrency_slots_sweep');
  END IF;
  PERFORM cron.schedule(
    'user_concurrency_slots_sweep',
    '0 * * * *',  -- restore mig 115 cadence (hourly) + 120 s threshold
    $sweep$delete from public.user_concurrency_slots where last_heartbeat_at < now() - interval '120 seconds';$sweep$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron_block$;

create or replace function public.find_stuck_active_conversations(
  p_threshold_seconds integer default 120
) returns table (id uuid, user_id uuid)
language sql
security definer
set search_path = public, pg_temp
as $$
  select c.id, c.user_id
  from public.conversations c
  left join public.user_concurrency_slots s
    on s.user_id = c.user_id
   and s.conversation_id = c.id
  where c.status = 'active'
    and c.archived_at is null
    and (
      s.id is null
      or s.last_heartbeat_at < now() - (p_threshold_seconds || ' seconds')::interval
    );
$$;

create or replace function public.acquire_worktree_lease(
  p_workspace_id uuid,
  p_worktree_id text,
  p_host_id text
) returns table (host_id text, lease_generation bigint)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform set_config('lock_timeout', '500ms', true);
  perform pg_advisory_xact_lock(
    hashtextextended(p_workspace_id::text || ':' || p_worktree_id, 0)
  );

  return query
  insert into public.worktree_write_lease as wl (workspace_id, worktree_id, host_id)
  values (p_workspace_id, p_worktree_id, p_host_id)
  on conflict (workspace_id, worktree_id) do update
    set host_id = excluded.host_id,
        lease_generation = case
          when wl.host_id = excluded.host_id
            then wl.lease_generation
          else wl.lease_generation + 1
        end,
        acquired_at = case
          when wl.host_id = excluded.host_id
            then wl.acquired_at
          else now()
        end,
        heartbeat_at = now()
    where wl.host_id = excluded.host_id
       or wl.heartbeat_at < now() - interval '120 seconds'
  returning wl.host_id, wl.lease_generation;
end;
$$;
