-- 069_action_sends_leader_loop.down.sql (#4379 PR-B)
--
-- Restores the pre-067 schema: drop the 6 nullable leader-loop columns.
--
-- No WORM trigger work in the down (symmetric to the up — mig 069 did not
-- alter the action_sends_no_update trigger because the BEFORE UPDATE OF
-- form admits UPDATEs on non-listed columns by default).
--
-- No data loss concern: artifacts on GitHub remain; the operator still
-- has the canonical record via the linked GitHub URL stored on
-- artifact_url (set by mig 064). The 6 dropped columns are operator-UX
-- state — losing them on rollback degrades the Today card to PR-A's
-- acknowledgment-only render path.

ALTER TABLE public.action_sends
  DROP COLUMN IF EXISTS undone_at,
  DROP COLUMN IF EXISTS prompt_version,
  DROP COLUMN IF EXISTS cancellation_requested_at,
  DROP COLUMN IF EXISTS current_turn_started_at,
  DROP COLUMN IF EXISTS current_turn,
  DROP COLUMN IF EXISTS reversal_handles;
