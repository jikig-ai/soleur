\set ON_ERROR_STOP on
SET statement_timeout = '30s';
SET lock_timeout = '5s';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',false);
SELECT set_config('request.jwt.claim.sub',codex_rehearsal.id(1)::text,false);
SELECT public.set_workspace_default_engine((SELECT value FROM codex_rehearsal.ids WHERE label='owner-workspace'),'codex','api-key',true,1);
RESET ROLE;
SELECT codex_rehearsal.assert((SELECT auth_mode_generation=1 AND auth_mode='api-key' FROM public.agent_engine_runs WHERE id=codex_rehearsal.id(1001)),'rebind generation');
SELECT codex_rehearsal.assert(NOT EXISTS(SELECT 1 FROM public.agent_engine_recovery_checkpoints WHERE run_id=codex_rehearsal.id(1001)),'stale checkpoint purged');
SELECT codex_rehearsal.assert((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM public.agent_engine_runs r WHERE id IN(codex_rehearsal.id(1002),codex_rehearsal.id(1003),codex_rehearsal.id(1004),codex_rehearsal.id(2001)))=(SELECT jsonb_agg(x ORDER BY x->>'id') FROM codex_rehearsal.snapshots s,jsonb_array_elements(s.state->'public.agent_engine_runs'->'rows') x WHERE s.label='before-rebind' AND x->>'id' IN(codex_rehearsal.id(1002)::text,codex_rehearsal.id(1003)::text,codex_rehearsal.id(1004)::text,codex_rehearsal.id(2001)::text)),'Claude routine member other-tenant complete runs unchanged by rebind');
SELECT codex_rehearsal.assert((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.run_id) FROM public.agent_engine_recovery_checkpoints c WHERE run_id<>codex_rehearsal.id(1001))=(SELECT jsonb_agg(x ORDER BY x->>'run_id') FROM codex_rehearsal.snapshots s,jsonb_array_elements(s.state->'public.agent_engine_recovery_checkpoints'->'rows') x WHERE s.label='before-rebind' AND x->>'run_id'<>codex_rehearsal.id(1001)::text),'all unrelated complete checkpoints unchanged by rebind');
INSERT INTO public.agent_engine_attempts(id,run_id,attempt_key,auth_mode_generation) VALUES(codex_rehearsal.id(5003),codex_rehearsal.id(1001),'synthetic-current',1);
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',false);
SELECT public.save_agent_engine_recovery_checkpoint(codex_rehearsal.id(1001),codex_rehearsal.id(5003),'{"threadId":"synthetic-current"}'::jsonb);
RESET ROLE;
INSERT INTO codex_rehearsal.snapshots VALUES('before-application-replacement',codex_rehearsal.state());
-- Controller must additionally snapshot actual storage/workspace file bytes.
