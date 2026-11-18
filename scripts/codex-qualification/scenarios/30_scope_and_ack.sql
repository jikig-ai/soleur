\set ON_ERROR_STOP on
SET statement_timeout = '30s';
SET lock_timeout = '5s';
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',false);
SELECT codex_rehearsal.expect_error('SELECT public.assert_agent_engine_attempt_generation(codex_rehearsal.id(5001))','55000');
SELECT codex_rehearsal.expect_error('SELECT public.assert_agent_engine_attempt_generation(codex_rehearsal.id(5002))','55000');
SELECT codex_rehearsal.expect_error($q$SELECT public.start_agent_engine_attempt(codex_rehearsal.id(1001),'synthetic-stale','managed',0)$q$,'55000');
SELECT codex_rehearsal.expect_error($q$SELECT public.save_agent_engine_recovery_checkpoint(codex_rehearsal.id(1001),codex_rehearsal.id(5001),'{"threadId":"synthetic-stale"}'::jsonb)$q$,'55000');
SELECT public.append_agent_engine_lifecycle_event(codex_rehearsal.id(1001),codex_rehearsal.id(5001),'{"type":"lifecycle","source_type":"status","status":"completed"}'::jsonb);
SELECT public.transition_agent_engine_attempt(codex_rehearsal.id(5002),'cancelled');
SELECT public.assert_agent_engine_attempt_generation(codex_rehearsal.id(5003));
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',false);
SELECT set_config('request.jwt.claim.sub',codex_rehearsal.id(3)::text,false);
SELECT codex_rehearsal.expect_error($q$SELECT public.set_workspace_default_engine((SELECT value FROM codex_rehearsal.ids WHERE label='owner-workspace'),'codex','managed',true,1)$q$,'42501');
SELECT codex_rehearsal.assert(NOT public.record_codex_history_transfer_acknowledgment(codex_rehearsal.id(101),1),'member cannot acknowledge owners conversation');
SELECT codex_rehearsal.assert(NOT public.codex_history_transfer_acknowledged(codex_rehearsal.id(101),1),'member cannot borrow acknowledgment');
SELECT codex_rehearsal.expect_error('SELECT * FROM public.agent_engine_recovery_checkpoints','42501');
SELECT codex_rehearsal.expect_error('SELECT * FROM public.agent_engine_attempts','42501');
SELECT codex_rehearsal.expect_error('SELECT public.assert_agent_engine_attempt_generation(codex_rehearsal.id(5003))','42501');
SELECT codex_rehearsal.assert((SELECT count(*)=1 FROM public.agent_engine_runs WHERE id=codex_rehearsal.id(1001)),'member RLS positive control');
SELECT set_config('request.jwt.claim.sub',codex_rehearsal.id(2)::text,false);
SELECT codex_rehearsal.assert((SELECT count(*)=0 FROM public.agent_engine_runs WHERE id=codex_rehearsal.id(1001)),'other tenant RLS fence');
SELECT codex_rehearsal.assert((SELECT count(*)=1 FROM public.agent_engine_runs WHERE id=codex_rehearsal.id(2001)),'other tenant positive control');
SELECT codex_rehearsal.assert(NOT public.record_codex_history_transfer_acknowledgment(codex_rehearsal.id(101),1),'other tenant acknowledgment fence');
SELECT codex_rehearsal.expect_error($q$SELECT public.set_workspace_default_engine((SELECT value FROM codex_rehearsal.ids WHERE label='owner-workspace'),'codex','managed',true,1)$q$,'42501');
SELECT codex_rehearsal.assert(public.record_codex_history_transfer_acknowledgment(codex_rehearsal.id(201),9),'other owner acknowledgment');
SELECT set_config('request.jwt.claim.sub',codex_rehearsal.id(1)::text,false);
SELECT codex_rehearsal.assert((SELECT count(*)=0 FROM public.agent_engine_runs WHERE id=codex_rehearsal.id(2001)),'owner reciprocal RLS fence');
SELECT codex_rehearsal.assert(public.record_codex_history_transfer_acknowledgment(codex_rehearsal.id(101),1),'owner acknowledgment');
SELECT codex_rehearsal.assert(public.codex_history_transfer_acknowledged(codex_rehearsal.id(101),1),'owner acknowledgment read');
SELECT codex_rehearsal.assert(NOT public.record_codex_history_transfer_acknowledgment(codex_rehearsal.id(101),2),'wrong generation refusal');
RESET ROLE;
-- A changed membership epoch invalidates the acknowledgment, then owner can
-- acknowledge again. Only task-owned generated fixture rows are touched.
UPDATE public.workspace_members SET created_at=created_at+interval '1 microsecond'
 WHERE workspace_id=(SELECT value FROM codex_rehearsal.ids WHERE label='owner-workspace') AND user_id=codex_rehearsal.id(1);
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',codex_rehearsal.id(1)::text,false);
SELECT codex_rehearsal.assert(NOT public.codex_history_transfer_acknowledged(codex_rehearsal.id(101),1),'membership epoch invalidation');
SELECT codex_rehearsal.assert(public.record_codex_history_transfer_acknowledgment(codex_rehearsal.id(101),1),'owner reacknowledgment');
RESET ROLE;
INSERT INTO codex_rehearsal.snapshots VALUES('before-race',codex_rehearsal.state());
