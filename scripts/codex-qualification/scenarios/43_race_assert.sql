\set ON_ERROR_STOP on
SET statement_timeout='30s';
SET lock_timeout='5s';
-- Controller MUST attest 42 passed, holder committed, waiter exited zero.
SELECT codex_rehearsal.assert((SELECT auth_mode='managed' AND auth_mode_generation=2 FROM public.agent_engine_runs WHERE id=codex_rehearsal.id(1001)),'holder generation committed');
SELECT codex_rehearsal.assert(NOT EXISTS(SELECT 1 FROM public.agent_engine_recovery_checkpoints WHERE run_id=codex_rehearsal.id(1001)),'racing stale checkpoint could not reappear');
SELECT codex_rehearsal.assert(NOT EXISTS(SELECT 1 FROM public.codex_history_transfer_acknowledgments WHERE conversation_id=codex_rehearsal.id(101)),'generation purges acknowledgment');
INSERT INTO public.agent_engine_attempts(id,run_id,attempt_key,auth_mode_generation) VALUES(codex_rehearsal.id(5004),codex_rehearsal.id(1001),'synthetic-current-after-race',2);
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',false);
SELECT public.save_agent_engine_recovery_checkpoint(codex_rehearsal.id(1001),codex_rehearsal.id(5004),'{"threadId":"synthetic-current-after-race"}'::jsonb);
RESET ROLE;
SELECT codex_rehearsal.assert((SELECT checkpoint->>'threadId'='synthetic-current-after-race' FROM public.agent_engine_recovery_checkpoints WHERE run_id=codex_rehearsal.id(1001)),'current generation checkpoint positive control');
INSERT INTO codex_rehearsal.snapshots VALUES('before-erasure',codex_rehearsal.state());
