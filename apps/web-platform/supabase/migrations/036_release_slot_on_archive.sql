-- Release the user_concurrency_slots row when a conversation is archived.
--
-- Bug: archiving a conversation in the Command Center (or via the
-- conversation_archive MCP tool) updates `conversations.archived_at` directly
-- without calling `public.release_conversation_slot`. The WS session keeps
-- heartbeating other live conversations, so the 120s lazy sweep in
-- `acquire_conversation_slot` never fires either. The slot leaks until
-- pg_cron's 1-minute tick after full WS disconnect. Result: a free-tier
-- user (cap=1) who archives their only conversation hits
-- "Concurrent-conversation limit reached" on the next new-conversation click.
--
-- Fix: AFTER UPDATE OF archived_at trigger on public.conversations that
-- calls the existing SECURITY DEFINER `public.release_conversation_slot`
-- RPC whenever `archived_at` transitions NULL → non-NULL. Closes the gap
-- for every writer (hook, MCP tool, future API endpoint, manual DB write).
--
-- Trigger semantics (see plan Risk #5 + Sharp Edges):
--
-- 1. Archive-only. Does NOT fire on `status='completed'` because
--    `resume_session` (ws-handler.ts:812) does not call `acquireSlot`.
--    Releasing on completed-only would let a resumed conversation bypass
--    the cap.
--
-- 2. Slot identity is read from OLD (`OLD.user_id`, `OLD.id`) — the
--    pre-image is the auth-checked, immutable identity. The conversations
--    RLS policy uses `FOR ALL USING (auth.uid() = user_id)` with no
--    `WITH CHECK` clause (001_initial_schema.sql:60-62), so a malicious
--    UPDATE could change `NEW.user_id` to any value the attacker chose.
--    Using OLD pins the slot lookup to the auth-checked owner.
--
-- 3. WHEN clause uses `IS DISTINCT FROM` (not `=`) because
--    `NULL = NULL` returns NULL (not true) — `WHEN` would treat that as
--    false and silently miss the NULL → non-NULL transition.
--
-- 4. `public.release_conversation_slot` is a plain keyed DELETE in
--    migration 029. Idempotent: a second invocation (e.g., when
--    `close_conversation` already released the slot before the archive
--    UPDATE landed) is a safe no-op.
--
-- 5. Chat-on-archived-conv is safe (AC12). After archive, the WS session's
--    in-memory `session.conversationId` may still point at the archived row
--    until the next start_session/resume. `updateConversationFor` writes
--    `last_active`/`status` regardless of `archived_at` — defensible because
--    the user can unarchive and resume. The Command Center sidebar filters
--    archived rows; the explicit resume_session path is unreachable from the
--    UI for archived conversations.
--
-- search_path is pinned to `public, pg_temp` per
-- cq-pg-security-definer-search-path-pin-pg-temp; relations are qualified
-- as `public.<table>` in the body.
--
-- Bulk-archive operators: an UPDATE that flips `archived_at` on N rows
-- fires the trigger N times (one keyed DELETE each). For multi-thousand-row
-- batch archives (data retention sweeps, backfills), bypass with
-- `SET LOCAL session_replication_role = replica;` for the txn.
--
-- FORWARD-ONLY. Rollback ordering: it is safe to drop this trigger any
-- time (pre-existing leaked slots reclaim via 120s heartbeat-lapse + the
-- 1-minute pg_cron sweep in migration 029 line 219). Reverting the code
-- PR is not required, unlike 029. To reintroduce, a new migration must
-- recreate the trigger; do NOT rely on `supabase db reset` in prod.

create or replace function public.release_slot_on_archive()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- OLD.user_id is the auth-checked owner from the pre-image.
  -- See header §2 — NEW.user_id is client-controlled because the
  -- conversations RLS policy lacks a WITH CHECK clause.
  perform public.release_conversation_slot(OLD.user_id, OLD.id);
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
