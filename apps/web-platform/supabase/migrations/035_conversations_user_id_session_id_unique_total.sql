-- Replaces partial index from migration 028 with a non-partial unique index
-- so PostgREST can infer ON CONFLICT for the bot-fixture seed path.
--
-- Root cause: PostgREST does not emit the index's WHERE predicate during
-- inference, so Postgres cannot pick a partial unique index for upsert.
-- Live repro on prd 2026-05-03 returned 42P10 against the partial index
-- in 028 ("there is no unique or exclusion constraint matching the
-- ON CONFLICT specification"). Postgres docs (sql-insert.html) require an
-- explicit index_predicate on the INSERT for partial-index inference;
-- PostgREST does not synthesize one. This migration removes that ambiguity.
--
-- Safety: NULLS DISTINCT is Postgres's default. Multiple (user_id, NULL)
-- rows already exist on prod (verified 14 rows, including 6 per user for
-- two users) — they continue to coexist under a non-partial unique index
-- because NULLs are not equal under unique semantics.
--
-- CONCURRENTLY is forbidden inside the Supabase migration transaction
-- (SQLSTATE 25001). Matches 025, 027, 028 precedent.
--
-- Consumer: plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts
-- upsertConversation() POSTs to
-- /rest/v1/conversations?on_conflict=user_id,session_id with
-- Prefer: resolution=merge-duplicates.
--
-- Rollback: drop index if exists public.uniq_conversations_user_id_session_id_total;
--           recreate the partial index from 028 (and accept that the bot
--           fixture seed will start failing again with 42P10).

drop index if exists public.uniq_conversations_user_id_session_id;

create unique index if not exists
  uniq_conversations_user_id_session_id_total
  on public.conversations (user_id, session_id);
