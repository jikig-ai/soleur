-- 062_workspace_member_actions.down.sql
-- Reverse-dependency DROP order for migration 062.
--
-- NOT REVERTED: the set_config('workspace_audit.actor_user_id', ...)
-- calls prepended to mig 058's invite_workspace_member,
-- remove_workspace_member, and anonymise_workspace_members RPCs. Once
-- the AFTER trigger that reads the GUC is dropped, set_config becomes
-- a harmless no-op. Pinning and restoring mig 058's RPC bodies on
-- down-migration would be fragile (plan-review P0-4).

-- Unschedule the cron job first (idempotent: cron.unschedule returns
-- false if the job doesn't exist).
SELECT cron.unschedule('workspace-member-actions-retention')
  WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'workspace-member-actions-retention'
  );

-- Wrapper RPCs.
DROP FUNCTION IF EXISTS public.purge_workspace_member_actions();
DROP FUNCTION IF EXISTS public.anonymise_workspace_member_actions(uuid);
DROP FUNCTION IF EXISTS public.list_workspace_member_actions(uuid, int, timestamptz);

-- AFTER trigger on workspace_members.
DROP TRIGGER IF EXISTS workspace_members_audit_trigger ON public.workspace_members;
DROP FUNCTION IF EXISTS public.workspace_members_audit();

-- WORM trigger on workspace_member_actions.
DROP TRIGGER IF EXISTS workspace_member_actions_no_update ON public.workspace_member_actions;
DROP TRIGGER IF EXISTS workspace_member_actions_no_delete ON public.workspace_member_actions;
DROP FUNCTION IF EXISTS public.workspace_member_actions_no_mutate();

-- Indexes drop automatically with the table, but explicit for parity.
DROP INDEX IF EXISTS public.workspace_member_actions_actor_idx;
DROP INDEX IF EXISTS public.workspace_member_actions_target_idx;
DROP INDEX IF EXISTS public.workspace_member_actions_workspace_created_idx;

-- Table.
DROP TABLE IF EXISTS public.workspace_member_actions;
