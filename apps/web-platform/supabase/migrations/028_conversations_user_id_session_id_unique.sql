-- Superseded by migration 035 (PostgREST cannot infer ON CONFLICT against
-- a partial unique index — see knowledge-base/project/plans/2026-05-03-fix-ux-audit-seed-conflict-plan.md).
--
-- Unique (user_id, session_id) for PostgREST upsert on conflict.
-- Partial: session_id is nullable; existing NULL rows must not collide.
-- Consumer: plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts uses
-- POST /rest/v1/conversations?on_conflict=user_id,session_id with
-- Prefer: resolution=merge-duplicates.
--
-- CONCURRENTLY is not used here because Supabase's migration runner wraps
-- each migration in a transaction, and CREATE INDEX CONCURRENTLY cannot
-- run inside a transaction block (SQLSTATE 25001). Matches the pattern
-- documented in 025_context_path_archived_predicate.sql and
-- 027_mtd_cost_aggregate.sql. The conversations table is small (~1k rows
-- on prod) so a blocking build is acceptable.
--
-- Consumer contract: `on_conflict=user_id,session_id` is NOT a general
-- uniqueness invariant — it is a fixture-only crutch for the ux-audit
-- bot. Production code paths that may insert with session_id IS NULL
-- will never conflict on this index.
--
-- Rollback: drop index if exists public.uniq_conversations_user_id_session_id;
create unique index if not exists
  uniq_conversations_user_id_session_id
  on public.conversations (user_id, session_id)
  where session_id is not null;
