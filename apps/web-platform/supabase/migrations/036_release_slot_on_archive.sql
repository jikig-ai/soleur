-- Release the user_concurrency_slots row when a conversation is archived.
--
-- Bug: archiving a conversation in the Command Center (or via the
-- conversation_archive MCP tool) updates `conversations.archived_at` directly
-- without calling `public.release_conversation_slot`. The WebSocket session
-- continues heartbeating other live conversations, so the lazy 120s sweep in
-- `acquire_conversation_slot` never fires either. The slot leaks until pg_cron
-- reclaims it on the next 1-minute tick, which only happens after the user
-- fully disconnects every WS. Result: a free-tier user (cap=1) who archives
-- their only conversation hits "Concurrent-conversation limit reached" on the
-- next "+ New conversation" click, with no in-product recovery path.
--
-- Fix: AFTER UPDATE trigger on public.conversations that calls the existing
-- SECURITY DEFINER `public.release_conversation_slot` RPC whenever
-- `archived_at` transitions from NULL to non-NULL. Closes the slot-release
-- gap for every current and future writer (hook, MCP tool, future API
-- endpoint, manual DB write) without coupling each writer to slot lifecycle.
--
-- Trigger semantics (see plan Risk #5 + Sharp Edges):
--
-- 1. Fires on `archived_at` transitions ONLY, NOT on `status='completed'`.
--    Reason: `resume_session` in ws-handler.ts does NOT call `acquireSlot`,
--    so releasing on completed-only would let a resumed conversation run
--    outside the slot ledger and effectively bypass the cap.
--
-- 2. `AFTER UPDATE OF archived_at` keeps the trigger no-op for unrelated
--    column updates — Postgres skips trigger evaluation entirely when the
--    named column wasn't in the UPDATE's SET list.
--
-- 3. WHEN clause uses `IS DISTINCT FROM` (not `=`) because
--    `NULL = NULL` returns NULL (not true), which `WHEN` treats as false →
--    the trigger would silently miss the NULL → non-NULL transition.
--
-- 4. The body invokes `public.release_conversation_slot(NEW.user_id, NEW.id)`,
--    which is a plain keyed DELETE in migration 029. Idempotent: a second
--    invocation (e.g., when `close_conversation` already released the slot
--    before the row was archived) is a safe no-op.
--
-- search_path is pinned to `public, pg_temp` per
-- cq-pg-security-definer-search-path-pin-pg-temp; relations are qualified
-- as `public.<table>` in the body.
--
-- CONCURRENTLY is NOT used — Supabase wraps each migration in a txn and
-- CREATE INDEX CONCURRENTLY fails with SQLSTATE 25001. (Not relevant here
-- since the migration declares no indexes — kept in the header for
-- consistency with 025/027/029/032 which the cq lint scans.)
--
-- FORWARD-ONLY: rollback requires a new migration that DROPs the trigger.

create or replace function public.release_slot_on_archive()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.release_conversation_slot(NEW.user_id, NEW.id);
  return NEW;
end;
$$;

revoke all on function public.release_slot_on_archive() from public;

drop trigger if exists conversations_release_slot_on_archive on public.conversations;

create trigger conversations_release_slot_on_archive
  after update of archived_at on public.conversations
  for each row
  when (
    OLD.archived_at IS DISTINCT FROM NEW.archived_at
    AND NEW.archived_at IS NOT NULL
  )
  execute function public.release_slot_on_archive();
