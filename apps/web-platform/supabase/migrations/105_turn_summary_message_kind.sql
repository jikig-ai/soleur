-- 105_turn_summary_message_kind.sql
--
-- feat-reasoning-chat-boxes (#5370). Adds a nullable `message_kind`
-- discriminator to public.messages so a deliberate agent-authored "turn
-- summary" can be persisted as a distinct, user-visible chat row (rendered
-- as a confirmed box) WITHOUT touching the team-only debug stream. Mirrors
-- the additive-nullable pattern of 040_message_status_aborted.sql.
--
-- Additive + nullable:
--   * message_kind is nullable with NO default, so every existing INSERT
--     writer is unaffected (no 23502 NOT-NULL violation). Legacy rows read
--     message_kind IS NULL (i.e. ordinary 'text'); only the new summarize()
--     path writes 'turn_summary'.
--   * The check constraint pins turn_summary rows to role='assistant' as
--     defense-in-depth (single producer today; guards a future mis-write).
--     Existing rows (message_kind IS NULL) satisfy the first branch, so the
--     constraint adds clean against current data.
--
-- NOT-NULL contract: the new insert-turn-summary.ts path sets the full
-- messages NOT-NULL-undefaulted column set — conversation_id, workspace_id
-- (= founderId solo-pin), template_id ('default_legacy'), user_id, role,
-- content — per insert-draft-card.ts precedent and the
-- messages_workspace_member_insert RLS gate (059) + messages_row_kind_chk
-- (082).
--
-- DSAR: message_kind is a structural discriminator (describes the row's own
-- shape, not third-party content) → classified in MESSAGE_NON_REDACT_
-- ALLOWLIST (server/dsar-export.ts). The sweep sentinel
-- (test/dsar-message-redact-fields-sweep.test.ts) enforces classification.
--
-- RLS: new column inherits the existing workspace-member policies (059); no
-- new policy needed.
--
-- Plan: knowledge-base/project/plans/2026-06-15-feat-reasoning-narration-plan.md §Phase 1
-- Issue: #5370

alter table public.messages
  add column if not exists message_kind text;

do $$
begin
  if not exists (
    select from pg_constraint where conname = 'messages_message_kind_chk'
  ) then
    alter table public.messages
      add constraint messages_message_kind_chk
      check (
        message_kind is null
        or (message_kind = 'turn_summary' and role = 'assistant')
      );
  end if;
end $$;
