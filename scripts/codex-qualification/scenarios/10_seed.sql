\set ON_ERROR_STOP on
SET statement_timeout = '30s';
SET lock_timeout = '5s';
-- Actual auth provisioning triggers populate profiles/organizations/workspaces.
INSERT INTO auth.users(id,email) VALUES
 (codex_rehearsal.id(1),'codex9051-owner@example.test'),
 (codex_rehearsal.id(2),'codex9051-other@example.test'),
 (codex_rehearsal.id(3),'codex9051-member@example.test');
SELECT codex_rehearsal.assert((SELECT count(*)=1 FROM public.workspace_members WHERE user_id=codex_rehearsal.id(1) AND role='owner'),'one owner workspace');
SELECT codex_rehearsal.assert((SELECT count(*)=1 FROM public.workspace_members WHERE user_id=codex_rehearsal.id(2) AND role='owner'),'one other workspace');
INSERT INTO codex_rehearsal.ids SELECT 'owner-workspace',workspace_id FROM public.workspace_members WHERE user_id=codex_rehearsal.id(1) AND role='owner';
INSERT INTO codex_rehearsal.ids SELECT 'other-workspace',workspace_id FROM public.workspace_members WHERE user_id=codex_rehearsal.id(2) AND role='owner';
INSERT INTO public.workspace_members(workspace_id,user_id,role)
 SELECT value,codex_rehearsal.id(3),'member' FROM codex_rehearsal.ids WHERE label='owner-workspace';
INSERT INTO public.conversations(id,workspace_id,user_id,status,visibility,engine_binding_state)
 SELECT codex_rehearsal.id(101),value,codex_rehearsal.id(1),'active','workspace','bound' FROM codex_rehearsal.ids WHERE label='owner-workspace';
INSERT INTO public.conversations(id,workspace_id,user_id,status,visibility,engine_binding_state)
 SELECT codex_rehearsal.id(201),value,codex_rehearsal.id(2),'active','workspace','bound' FROM codex_rehearsal.ids WHERE label='other-workspace';
INSERT INTO public.conversations(id,workspace_id,user_id,status,visibility,engine_binding_state)
 SELECT codex_rehearsal.id(102),value,codex_rehearsal.id(1),'active','workspace','bound' FROM codex_rehearsal.ids WHERE label='owner-workspace';
INSERT INTO public.conversations(id,workspace_id,user_id,status,visibility,engine_binding_state)
 SELECT codex_rehearsal.id(103),value,codex_rehearsal.id(3),'active','workspace','bound' FROM codex_rehearsal.ids WHERE label='owner-workspace';
INSERT INTO public.workspace_engine_settings(workspace_id,default_engine_id,default_auth_mode,codex_auth_mode,updated_by)
 SELECT value,'claude-code','managed','managed',codex_rehearsal.id(CASE label WHEN 'owner-workspace' THEN 1 ELSE 2 END) FROM codex_rehearsal.ids;
INSERT INTO public.agent_engine_runs(id,workspace_id,execution_kind,conversation_id,engine_id,auth_mode,adapter_version,status,created_by,auth_mode_generation)
 SELECT codex_rehearsal.id(1001),value,'conversation',codex_rehearsal.id(101),'codex','managed','codex-v1','queued',codex_rehearsal.id(1),0 FROM codex_rehearsal.ids WHERE label='owner-workspace';
INSERT INTO public.agent_engine_runs(id,workspace_id,execution_kind,conversation_id,engine_id,auth_mode,adapter_version,status,created_by,auth_mode_generation)
 SELECT codex_rehearsal.id(2001),value,'conversation',codex_rehearsal.id(201),'codex','api-key','codex-v1','queued',codex_rehearsal.id(2),9 FROM codex_rehearsal.ids WHERE label='other-workspace';
INSERT INTO public.agent_engine_runs(id,workspace_id,execution_kind,conversation_id,engine_id,auth_mode,adapter_version,status,created_by,auth_mode_generation)
 SELECT codex_rehearsal.id(1002),value,'conversation',codex_rehearsal.id(102),'claude-code','managed','claude-code-v1','queued',codex_rehearsal.id(1),7 FROM codex_rehearsal.ids WHERE label='owner-workspace';
INSERT INTO public.agent_engine_runs(id,workspace_id,execution_kind,conversation_id,engine_id,auth_mode,adapter_version,status,created_by,auth_mode_generation)
 SELECT codex_rehearsal.id(1003),value,'conversation',codex_rehearsal.id(103),'claude-code','managed','claude-code-v1','queued',codex_rehearsal.id(3),7 FROM codex_rehearsal.ids WHERE label='owner-workspace';
INSERT INTO public.agent_engine_runs(id,workspace_id,execution_kind,routine_id,routine_run_id,engine_id,auth_mode,adapter_version,status,created_by,auth_mode_generation)
 SELECT codex_rehearsal.id(1004),value,'routine','synthetic-routine','synthetic-routine-run','codex','managed','codex-v1','queued',codex_rehearsal.id(1),8 FROM codex_rehearsal.ids WHERE label='owner-workspace';
INSERT INTO public.agent_engine_attempts(id,run_id,attempt_key,auth_mode_generation) VALUES
 (codex_rehearsal.id(5001),codex_rehearsal.id(1001),'synthetic-accepted-old',0),
 (codex_rehearsal.id(5002),codex_rehearsal.id(1001),'synthetic-unaccepted-old',0),
 (codex_rehearsal.id(6001),codex_rehearsal.id(2001),'synthetic-other-tenant',9),
 (codex_rehearsal.id(6002),codex_rehearsal.id(1002),'synthetic-claude-control',7),
 (codex_rehearsal.id(6003),codex_rehearsal.id(1003),'synthetic-member-control',7),
 (codex_rehearsal.id(6004),codex_rehearsal.id(1004),'synthetic-routine-control',8);
INSERT INTO public.messages(workspace_id,template_id,conversation_id,role,content)
 SELECT value,'work',codex_rehearsal.id(101),'user','Synthetic full-schema rehearsal fixture.' FROM codex_rehearsal.ids WHERE label='owner-workspace';
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',false);
SELECT public.assert_agent_engine_attempt_generation(codex_rehearsal.id(5001));
SELECT public.transition_agent_engine_attempt(codex_rehearsal.id(5001),'running');
SELECT public.save_agent_engine_recovery_checkpoint(codex_rehearsal.id(1001),codex_rehearsal.id(5001),'{"threadId":"synthetic-old"}'::jsonb);
SELECT public.save_agent_engine_recovery_checkpoint(codex_rehearsal.id(2001),codex_rehearsal.id(6001),'{"threadId":"synthetic-other"}'::jsonb);
SELECT public.save_agent_engine_recovery_checkpoint(codex_rehearsal.id(1002),codex_rehearsal.id(6002),'{"threadId":"synthetic-claude"}'::jsonb);
SELECT public.save_agent_engine_recovery_checkpoint(codex_rehearsal.id(1003),codex_rehearsal.id(6003),'{"threadId":"synthetic-member"}'::jsonb);
SELECT public.save_agent_engine_recovery_checkpoint(codex_rehearsal.id(1004),codex_rehearsal.id(6004),'{"threadId":"synthetic-routine"}'::jsonb);
RESET ROLE;
INSERT INTO codex_rehearsal.snapshots VALUES('before-rebind',codex_rehearsal.state());
