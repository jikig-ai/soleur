-- 070_action_sends_realtime_publication.sql (#4379 PR-B — review finding fix)
--
-- Adds `public.action_sends` to the `supabase_realtime` publication so the
-- Today card's <LeaderLoopStatus> subscription receives UPDATE events as the
-- Inngest leader loop writes per-turn progress, acknowledgment, failure
-- reasons, and undo state.
--
-- WHY THIS LANDS AS A SEPARATE MIGRATION FROM 069:
-- Phase 8.2 multi-agent review (security-sentinel) surfaced this gap:
-- LeaderLoopStatus subscribes via the browser tenant client with
-- `filter: message_id=eq.<id>`, but the `filter` is enforced by the
-- publisher — not by RLS — so the table must be a `supabase_realtime`
-- publication member AND RLS-aware delivery must be active. Without the
-- publication add, the subscribe call succeeds and reports SUBSCRIBED but
-- delivers ZERO updates; the operator UX silently degrades to the 2s poll
-- fallback (FR3) on every spawn. RLS-aware delivery is implicit when the
-- table has RLS enabled + a SELECT policy (mig 051 lines 159-163 enabled
-- both: `ENABLE ROW LEVEL SECURITY` + `action_sends_owner_select` policy
-- `USING (user_id = auth.uid())`); Realtime applies the SELECT policy
-- to the broadcast payload, so a user who guesses another user's
-- `message_id` receives no UPDATE events (cross-tenant disclosure
-- blocked).
--
-- Pattern mirrors mig 034 (conversations + messages publication adds) —
-- the `pg_publication_tables` existence check is the canonical idempotent
-- form for `ALTER PUBLICATION`. Re-running this migration on a project
-- where the table is already a publication member is a no-op.
--
-- REPLICA IDENTITY: mig 064 created `public.action_sends` with the default
-- replica identity (PRIMARY KEY). For postgres_changes UPDATE events that
-- only need the new-row payload (which is what LeaderLoopStatus consumes —
-- the deriveTodayCardState() function reads only the post-UPDATE values),
-- default identity is sufficient. DELETE events would need REPLICA
-- IDENTITY FULL to populate `payload.old.user_id`; mig 034's discovery
-- (and the conversations-side handling in use-conversations.ts:242-248)
-- documents the pattern, but LeaderLoopStatus only handles UPDATE.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'action_sends'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.action_sends;
  END IF;
END $$;
