-- 064_action_sends_acknowledgment.down.sql (#4124 PR-A)
--
-- Restores the pre-064 schema:
--   1. Drop the three acknowledgment columns.
--   2. Restore the pure-reject UPDATE trigger (no column list — every UPDATE
--      rejected, matching mig 051 behavior).
--
-- No data loss: acknowledgment artifacts on GitHub remain; the operator
-- still has the canonical view via the linked PR comment / issue label.

-- =============================================================================
-- (b) Restore the pure-reject WORM UPDATE trigger first, so any in-flight
--     UPDATE between DROP COLUMN and CREATE TRIGGER is rejected by the new
--     column-list-less trigger.
-- =============================================================================
DROP TRIGGER IF EXISTS action_sends_no_update ON public.action_sends;
CREATE TRIGGER action_sends_no_update
  BEFORE UPDATE ON public.action_sends
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.action_sends_no_mutate();

-- =============================================================================
-- (a) Drop the three acknowledgment columns.
-- =============================================================================
ALTER TABLE public.action_sends
  DROP COLUMN IF EXISTS failure_reason,
  DROP COLUMN IF EXISTS artifact_url,
  DROP COLUMN IF EXISTS acknowledged_at;
