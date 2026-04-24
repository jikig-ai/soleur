-- 032_conversation_workflow_state.sql
-- Adds sticky-workflow state to `conversations` so the Command Center's new
-- `/soleur:go` runner (apps/web-platform/server/soleur-go-runner.ts, Stage 2
-- of plan 2026-04-23-feat-cc-route-via-soleur-go-plan.md) can pin a
-- conversation to the workflow it routed into on turn 1 and carry that
-- decision across subsequent turns.
--
--   active_workflow   text NULL      — the workflow name; '__unrouted__' is a
--                                      sentinel written when the runner is
--                                      pending but no workflow has been
--                                      selected yet. NULL means "legacy
--                                      router" (agent-runner.ts code path).
--   workflow_ended_at timestamptz NULL — set when `workflow_ended` WS event
--                                       fires (completed / cost_ceiling /
--                                       user_aborted / runner_runaway / etc.).
--                                       NULL while workflow is active.
--
-- COUPLING INVARIANT: the CHECK constraint below enumerates every valid
-- workflow name. The same list MUST appear verbatim in
-- apps/web-platform/server/conversation-routing.ts `WorkflowName` union and
-- in the `SENTINEL_UNROUTED` constant. Drift between the TS union and the
-- CHECK clause produces asymmetric rejection (inserts fail at the DB,
-- fine; but `parseConversationRouting` returning a widened type that the
-- CHECK would have rejected is a silent-drop). Tests in
-- test/supabase-migrations/032-workflow-state.test.ts parse this file and
-- assert every allowed value is present.
--
-- FORWARD-ONLY. Rollback = drop both columns after confirming no code path
-- references them. See knowledge-base/engineering/ops/runbooks/supabase-migrations.md.
--
-- CONCURRENTLY is NOT used. Supabase's migration runner wraps each file in a
-- transaction (SQLSTATE 25001 on CONCURRENTLY in a txn). Plain
-- `ALTER TABLE ADD COLUMN` on a nullable column is metadata-only in Postgres
-- 11+ — no table rewrite, no row scan, no lock escalation beyond
-- AccessExclusive which we already hold for other DDL in this txn.
--
-- IDEMPOTENT via `IF NOT EXISTS` on the columns and `DO $$ ... $$` guard on
-- the constraint (ADD CONSTRAINT has no IF NOT EXISTS form in PG).

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS active_workflow text,
  ADD COLUMN IF NOT EXISTS workflow_ended_at timestamptz;

COMMENT ON COLUMN public.conversations.active_workflow IS
  'Soleur Command Center sticky-workflow state. NULL = legacy router (agent-runner.ts). ''__unrouted__'' = soleur-go-runner started, no skill dispatched yet. Other values = dispatched workflow name; CHECK constraint enumerates the valid set. Must be kept in sync with server/conversation-routing.ts WorkflowName.';

COMMENT ON COLUMN public.conversations.workflow_ended_at IS
  'Timestamp when soleur-go-runner emitted workflow_ended (completed / cost_ceiling / user_aborted / runner_runaway / idle_timeout / plugin_load_failure / sandbox_denial / runner_crash / internal_error). NULL = workflow still active or conversation on legacy router.';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint
     WHERE conname = 'conversations_active_workflow_chk'
       AND conrelid = 'public.conversations'::regclass
  ) THEN
    ALTER TABLE public.conversations
      ADD CONSTRAINT conversations_active_workflow_chk
      CHECK (
        active_workflow IS NULL
        OR active_workflow IN (
          '__unrouted__',
          'one-shot',
          'brainstorm',
          'plan',
          'work',
          'review',
          'drain-labeled-backlog'
        )
      );
  END IF;
END$$;
