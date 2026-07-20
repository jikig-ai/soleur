-- 133_heartbeat_threshold_backoff.sql
-- perf: raise every concurrency-slot / worktree-lease liveness threshold
-- 120 s → 240 s so the paired TS heartbeat cadences can back off 30 s → 60 s
-- (slot) and 25 s → 50 s (lease) WITHOUT shrinking the missed-beat tolerance.
--
-- This is the SQL half (the CONTRACT) of the Disk-IO write-reduction PR. The
-- periodic slot heartbeat (touch_conversation_slot, 30 s) and lease heartbeat
-- (touch_worktree_lease, 25 s) are steady WAL writers on the Micro tier;
-- doubling their intervals halves that WAL. The staleness thresholds that
-- decide "this slot/lease is dead, reclaim it" must rise in lockstep or a live
-- session gets false-reaped mid-run (single-user-incident surface).
--
-- Migrations apply in web-platform-release BEFORE the container restarts with
-- the 60 s-heartbeat code, so the 240 s threshold is live first — the safe
-- direction (tolerance widens before the interval lengthens).
--
-- All four objects are CREATE OR REPLACE of the BODY ONLY (copied verbatim
-- from their live source with only the interval/default literal changed):
--   (a) acquire_conversation_slot(uuid,uuid,integer,uuid)  — source mig 093:50
--   (b) user_concurrency_slots_sweep pg_cron body          — source mig 115:65 (live last-writer; cadence UNCHANGED)
--   (c) find_stuck_active_conversations(integer) default   — source mig 037:43
--   (d) acquire_worktree_lease(uuid,text,text) takeover    — source mig 116:87
--
-- GRANTS ARE DELIBERATELY OMITTED. CREATE OR REPLACE preserves the existing
-- ACL, which for all three functions is {postgres, service_role} — migration
-- 128 (#6306) revoked the residual anon/authenticated EXECUTE. Re-emitting a
-- GRANT block risks re-introducing that cross-tenant-enumeration grant, so we
-- rely on ACL preservation and change the body only.
--
-- SECURITY DEFINER + `SET search_path = public, pg_temp` preserved verbatim on
-- every function (cq-pg-security-definer-search-path-pin-pg-temp).
--
-- Coupling map (all raised to 240 s here + in the paired TS edit): the SQL
-- sites below (mig 093 lazy sweep, mig 115 pg_cron sweep, mig 037 finder
-- default, mig 116 lease takeover) couple to the TS sites
-- SLOT_STALENESS_THRESHOLD_SECONDS (ws-handler.ts + agent-runner.ts),
-- ws-handler.ts cap-drift + sibling-snapshot-restore liveCutoff gates, and LEASE_LIVENESS_WINDOW_MS
-- (worktree-write-lease.ts). See learning
-- bug-fixes/2026-05-05-cc-stuck-active-conversation-leaks-slot.md — divergent
-- thresholds silently false-reap.
--
-- FORWARD-ONLY, txn-safe (no CONCURRENTLY / VACUUM / ALTER SYSTEM).
-- Plan: knowledge-base/project/plans/2026-07-18-perf-supabase-disk-io-write-reduction-plan.md

-- =====================================================================
-- (a) acquire_conversation_slot — lazy sweep 120 s → 240 s.
--     Signature UNCHANGED (4-arg), so CREATE OR REPLACE preserves ACL.
--     Verbatim from mig 093:50-120; only the lazy-sweep interval + its
--     coupling comment changed.
-- =====================================================================
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

  -- Lazy sweep. 240s threshold matches the pg_cron schedule below so a
  -- crashed WS can reclaim a slot on reconnect even before cron runs.
  -- (Raised 120→240 in mig 133 alongside the 30s→60s slot heartbeat.)
  delete from public.user_concurrency_slots
  where user_id = p_user_id
    and last_heartbeat_at < now() - interval '240 seconds';

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

-- =====================================================================
-- (b) user_concurrency_slots_sweep pg_cron — threshold 120 s → 240 s.
--     Reproduces mig 115's idempotent DO block VERBATIM: cadence
--     '0 * * * *' (hourly) UNCHANGED — only the freshness threshold in the
--     $sweep$ body moves. mig 115 is the live last-writer (029→038→115).
-- =====================================================================
DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'user_concurrency_slots_sweep') THEN
    PERFORM cron.unschedule('user_concurrency_slots_sweep');
  END IF;
  PERFORM cron.schedule(
    'user_concurrency_slots_sweep',
    '0 * * * *',  -- cadence UNCHANGED (hourly, mig 115). 240 s freshness threshold (was 120 s, mig 133).
    $sweep$delete from public.user_concurrency_slots where last_heartbeat_at < now() - interval '240 seconds';$sweep$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron_block$;

-- =====================================================================
-- (c) find_stuck_active_conversations — default threshold 120 → 240.
--     Verbatim from mig 037:43-61 (latest live def); only the default
--     literal changed. The caller (agent-runner.ts) passes an explicit
--     threshold, but the default must move to keep the coupling honest.
-- =====================================================================
create or replace function public.find_stuck_active_conversations(
  p_threshold_seconds integer default 240
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

-- =====================================================================
-- (d) acquire_worktree_lease — cross-host takeover 120 s → 240 s.
--     Verbatim from mig 116:87-131; only the expiry-disjunct interval
--     changed so the lease-liveness window matches the 240 s TS window
--     (else a competing host seizes a live lease after only 120 s of
--     silence = 2.4 missed 50 s beats — split-brain cross-host write).
-- =====================================================================
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
  -- Bound contention on the per-key advisory lock so a same-worktree acquire
  -- race fails fast with 55P03 (lock_not_available) — which the TS client's
  -- jittered transient-retry covers — instead of blocking unboundedly (mirror
  -- 029:119). Without this, 55P03 can never arise from this RPC and that half of
  -- the client's mirrored transient set would be dead for this function.
  perform set_config('lock_timeout', '500ms', true);
  -- Shape-parity with 029:125 (per-key advisory xact lock, released on commit).
  -- Redundant-but-harmless for atomicity here (that rests on the ON CONFLICT …
  -- WHERE EvalPlanQual re-check, not this lock — no multi-statement window like
  -- 029's sweep+count+cap); kept for precedent parity + the lock_timeout above.
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
            then wl.lease_generation              -- same host: idempotent refresh, keep gen
          else wl.lease_generation + 1            -- cross-host takeover: bump in-statement
        end,
        acquired_at = case
          when wl.host_id = excluded.host_id
            then wl.acquired_at
          else now()
        end,
        heartbeat_at = now()
    where wl.host_id = excluded.host_id
       or wl.heartbeat_at < now() - interval '240 seconds'
  returning wl.host_id, wl.lease_generation;
end;
$$;
