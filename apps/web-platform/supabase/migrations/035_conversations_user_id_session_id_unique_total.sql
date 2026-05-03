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
-- Realtime/replication: index-only change. Postgres logical replication and
-- the supabase_realtime publication are table-level; REPLICA IDENTITY is a
-- table-level setting. Index DDL is transparent to subscribers — no resync,
-- no missed events.
--
-- Consumer: plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts
-- upsertConversation() POSTs to
-- /rest/v1/conversations?on_conflict=user_id,session_id with
-- Prefer: resolution=merge-duplicates. (Today the only consumer; grep
-- before adding more.)
--
-- Rollback: drop index if exists public.uniq_conversations_user_id_session_id_total;
--           recreate the partial index from 028. Before rolling back, audit
--           any new consumer using on_conflict=user_id,session_id (grep
--           apps/** plugins/**) — non-bot upserts added after this migration
--           would silently lose merge-duplicates semantics under the partial
--           form (PostgREST cannot infer partial indexes → 42P10).

drop index if exists public.uniq_conversations_user_id_session_id;

create unique index if not exists
  uniq_conversations_user_id_session_id_total
  on public.conversations (user_id, session_id);
