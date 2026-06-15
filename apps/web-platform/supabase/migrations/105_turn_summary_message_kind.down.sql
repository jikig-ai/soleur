-- 105_turn_summary_message_kind.down.sql
--
-- Reverts 105_turn_summary_message_kind.sql. Drops the check constraint
-- before the column (constraint depends on the column). Idempotent.

alter table public.messages
  drop constraint if exists messages_message_kind_chk;

alter table public.messages
  drop column if exists message_kind;
