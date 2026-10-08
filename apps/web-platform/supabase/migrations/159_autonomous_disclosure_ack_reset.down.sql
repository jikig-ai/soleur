-- 159_autonomous_disclosure_ack_reset.down.sql
-- Reverse 159: drop the audit column. The live autonomous_disclosure_ack_at
-- values that 159 reset to NULL are deliberately NOT restored: they evidenced
-- consent to the superseded copy, and NULL is the fail-closed HOLD (the safe
-- direction for an approval-bypass flag). Owners re-ack on their next held
-- command. The superseded timestamps are discarded with the column: THIS DOWN IS
-- LOSSY (it destroys the only record of the prior consent time), so copy the
-- column out (e.g. to a dated table) before running it.

ALTER TABLE public.workspaces
  DROP COLUMN IF EXISTS autonomous_disclosure_ack_superseded_at;
