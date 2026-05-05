-- Periodic stuck-active conversation reaper — finder RPC.
--
-- Bug: a conversation can land at status='active' with the
-- user_concurrency_slots row missing or stale-heartbeat-ed when the
-- agent-runner result branch throws between `saveMessage` and the
-- terminal `updateConversationStatus(..., "waiting_for_user")` write
-- (six throw-eligible steps; AC1 of the stuck-active plan covers the
-- happy-path catch). The free-tier user (cap=1) is then locked out of
-- "Ask about this document" until the row is manually cleared.
--
-- Fix: an application-layer periodic reaper (server/agent-runner.ts
-- `startStuckActiveReaper`) calls this RPC every 60 s. The signal is
-- slot-heartbeat staleness, NOT `conversations.last_active`:
--   - `last_active` is updated only by `updateConversationStatus`
--     (agent-runner.ts) and `cc-dispatcher.ts`, so a long tool-heavy
--     turn that streams partials without status writes would have
--     stale `last_active` and be falsely reaped.
--   - `user_concurrency_slots.last_heartbeat_at` is refreshed every
--     30 s by `ws-handler.ts` for the active conversation. Its
--     absence/staleness is the authoritative liveness signal: no WS
--     session is heartbeating this conversation, so the agent run is
--     either dead or stuck and the row should be finalized.
--
-- Threshold: 120 s. Matches the existing pg_cron sweep threshold in
-- migration 029 line 219 — the two sweep mechanisms agree on a single
-- liveness threshold.
--
-- search_path is pinned to `public, pg_temp` per
-- cq-pg-security-definer-search-path-pin-pg-temp; relations are
-- qualified as `public.<table>` in the body.
--
-- FORWARD-ONLY. The RPC is read-only — rolling back is just
-- `drop function`. No data dependency. Applying before the deploy is
-- safe (the new RPC is unused by existing code). Applying after the
-- deploy is also safe (the reaper handles "RPC not found" via its
-- error branch). Recommended order: migration first, then deploy.

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

revoke all on function public.find_stuck_active_conversations(integer) from public;
grant execute on function public.find_stuck_active_conversations(integer) to service_role;
