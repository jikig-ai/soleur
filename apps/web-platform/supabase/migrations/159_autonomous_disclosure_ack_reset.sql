-- 159_autonomous_disclosure_ack_reset.sql
-- CPO3-R2 / #9776 — reset the autonomous-mode first-run consent ack after the
-- disclosure copy was re-locked (2026-10-08) to name the unblocked force-push
-- over the default branch and infrastructure-teardown exposure.
--
-- WHY: the existing autonomous_disclosure_ack_at rows evidence consent to copy
-- that affirmatively said the work was "backed up in git" and that dangerous
-- commands are always blocked. That consent is not informed for the exposure
-- the new copy discloses, so it is superseded, not preserved.
--
-- MECHANISM: add a nullable audit column, then in ONE UPDATE move the old ack
-- timestamp into it and NULL the live ack for workspaces that are autonomous
-- AND had acked. A NULL ack is already the fail-closed HOLD in the server
-- (resolveAckPosture): the next non-blocked Bash command is held and the new
-- banner shows; "Got it" re-acks via set_workspace_autonomous_ack (099).
--
-- ** THIS MIGRATION DOES NOT WRITE THE bash_autonomous TOGGLE COLUMN. **
-- The 099 sentinel (no bulk write to the toggle) stays valid. Workspaces with
-- bash_autonomous = false are untouched (their ack, if any, is not an
-- approval-bypass consent record).
--
-- DEPLOY ORDER: the new-copy build must be live BEFORE or WITH this migration,
-- otherwise a reset owner could re-ack against the OLD copy.
--
-- LAWFUL_BASIS: GDPR Art. 6(1)(b) — contract performance (the owner's own
--   consent-to-risk record for their own workspace); Art. 7(1) demonstrability
--   is preserved by keeping the superseded timestamp. Non-PII timestamp; no
--   new purpose, category, recipient or sub-processor.
-- Retention: dies with the workspace row (existing cascades cover it).

ALTER TABLE public.workspaces
  ADD COLUMN IF NOT EXISTS autonomous_disclosure_ack_superseded_at timestamptz;

COMMENT ON COLUMN public.workspaces.autonomous_disclosure_ack_superseded_at IS
  'Audit trail (#9776, migration 159): the autonomous_disclosure_ack_at value '
  'that was superseded when the disclosure copy was re-locked 2026-10-08 to '
  'name force-push-over-default-branch and infrastructure-teardown exposure. '
  'NULL = never superseded. Not read by the permission path; the live consent '
  'record remains autonomous_disclosure_ack_at.';

UPDATE public.workspaces
SET autonomous_disclosure_ack_superseded_at = autonomous_disclosure_ack_at,
    autonomous_disclosure_ack_at = NULL
WHERE bash_autonomous
  AND autonomous_disclosure_ack_at IS NOT NULL;
