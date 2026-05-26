-- 040_message_status_aborted.sql
--
-- PR1 of feat-abort-conversation-web (#3448). Adds `status` + `usage`
-- columns to `public.messages` so the abort branch in
-- `agent-runner.ts` can persist the partial assistant text from a
-- user-initiated Stop (or a tab-close disconnect) instead of silently
-- discarding `fullText` accumulated by the SDK iterator. The honest-
-- disclosure surface (G2) reads back `usage` to render the post-Stop
-- token cost + completed-actions chip-list in the chat UI (PR2).
--
-- Additive only:
--   * `status` defaults to 'complete' so every existing row keeps its
--     pre-migration semantics.
--   * `usage` is a nullable jsonb so the abort-marker UI can branch on
--     `status = 'aborted'` and never read `usage` for the legacy
--     `complete` rows. No backfill needed.
--
-- Plan: knowledge-base/project/plans/2026-05-07-feat-abort-conversation-web-plan.md §1.1
-- Spec: knowledge-base/project/specs/feat-abort-conversation-web/spec.md
-- Issue: #3448

alter table public.messages
  add column if not exists status text not null default 'complete'
    check (status in ('complete', 'aborted'));

alter table public.messages
  add column if not exists usage jsonb;

-- usage jsonb shape (documented; not enforced by check):
--   {
--     "input_tokens": number,
--     "output_tokens": number,
--     "cost_usd": number | null,
--     "completed_actions": [
--       { "tool_name": string, "input_summary": string, "result_summary": string }
--     ]
--   }
--
-- RLS: existing `Users can read own messages` / `Users can insert own
-- messages` policies (001_initial_schema.sql:79-95) gate on
-- `conversation_id` via the conversations FK join, not column shape, so
-- the new columns inherit the same row-level access automatically.
--
-- Backward-compat: the existing `tool_calls jsonb` column continues to
-- carry the cumulative tool-use stream for completed turns; the new
-- `usage.completed_actions` array is the abort-time snapshot,
-- consumed by the chip-list renderer ONLY when `status = 'aborted'`.
