BEGIN;
SET LOCAL lock_timeout = '30s';
SET LOCAL statement_timeout = '5min';

DROP TRIGGER workspace_members_purge_codex_history_ack_on_update ON public.workspace_members;
DROP TRIGGER workspace_members_purge_codex_history_ack_on_delete ON public.workspace_members;
DROP TRIGGER agent_engine_runs_purge_stale_codex_history_ack ON public.agent_engine_runs;
DROP FUNCTION public.purge_codex_history_transfer_acknowledgments_on_member_change();
DROP FUNCTION public.purge_stale_codex_history_transfer_acknowledgments();
DROP FUNCTION public.codex_history_transfer_acknowledged(uuid, bigint);
DROP FUNCTION public.record_codex_history_transfer_acknowledgment(uuid, bigint);
DROP TABLE public.codex_history_transfer_acknowledgments;

COMMIT;
