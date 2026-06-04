-- 099_bash_autonomous_default_on_and_ack.down.sql
-- Reverse 099: drop the two ack RPCs, drop the ack column, and reset the
-- bash_autonomous column DEFAULT back to false. Resetting the default to false
-- is the safe direction for an approval-bypass flag (new workspaces created
-- post-rollback are NOT autonomous by construction). Existing row VALUES are
-- untouched by an ALTER COLUMN ... SET DEFAULT — consistent with the
-- forward-only, no-backfill contract.

DROP FUNCTION IF EXISTS public.set_workspace_autonomous_ack(uuid);
DROP FUNCTION IF EXISTS public.get_workspace_autonomous_ack(uuid);

ALTER TABLE public.workspaces
  DROP COLUMN IF EXISTS autonomous_disclosure_ack_at;

ALTER TABLE public.workspaces
  ALTER COLUMN bash_autonomous SET DEFAULT false;
