-- Reverse 100_append_kb_sync_row_for_user_rpc.sql — drop the service-role-only
-- workspace-keyed audit writer. The owner-attributed `append_kb_sync_row` (053)
-- is untouched; post-rollback, owner-less workspaces revert to the prior
-- skip-the-audit-row behavior (KB content still syncs via self-heal). No data
-- migration: kb_sync_history rows already written are unaffected.

DROP FUNCTION IF EXISTS public.append_kb_sync_row_for_user(uuid, jsonb, int);
