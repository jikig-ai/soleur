-- Unique (user_id, session_id) for PostgREST upsert on conflict.
-- Partial: session_id is nullable; existing NULL rows must not collide.
-- Consumer: plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts uses
-- POST /rest/v1/conversations?on_conflict=user_id,session_id with
-- Prefer: resolution=merge-duplicates.
create unique index concurrently if not exists
  uniq_conversations_user_id_session_id
  on public.conversations (user_id, session_id)
  where session_id is not null;
