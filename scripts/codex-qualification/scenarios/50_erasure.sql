\set ON_ERROR_STOP on
SET statement_timeout='30s';
SET lock_timeout='5s';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',false);
SELECT set_config('request.jwt.claim.sub',codex_rehearsal.id(1)::text,false);
SELECT codex_rehearsal.assert(public.record_codex_history_transfer_acknowledgment(codex_rehearsal.id(101),2),'pre-erasure owner ack');
SELECT codex_rehearsal.expect_error('SELECT public.anonymise_agent_engine_data(codex_rehearsal.id(1))','42501');
RESET ROLE;
INSERT INTO codex_rehearsal.snapshots VALUES('before-engine-erasure',codex_rehearsal.state());
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',false);
SELECT public.anonymise_agent_engine_data(codex_rehearsal.id(1));
SELECT codex_rehearsal.expect_error($q$SELECT public.save_agent_engine_recovery_checkpoint(codex_rehearsal.id(1001),codex_rehearsal.id(5004),'{"threadId":"synthetic-after-erasure"}'::jsonb)$q$,'55000');
RESET ROLE;
SELECT codex_rehearsal.assert((SELECT created_by IS NULL FROM public.agent_engine_runs WHERE id=codex_rehearsal.id(1001)),'run creator anonymized');
SELECT codex_rehearsal.assert((SELECT updated_by IS NULL AND codex_auth_mode='managed' FROM public.workspace_engine_settings WHERE workspace_id=(SELECT value FROM codex_rehearsal.ids WHERE label='owner-workspace')),'setting mode retained without updater');
SELECT codex_rehearsal.assert(NOT EXISTS(SELECT 1 FROM public.agent_engine_recovery_checkpoints WHERE run_id=codex_rehearsal.id(1001)),'erasure purges checkpoint');
SELECT codex_rehearsal.assert(NOT EXISTS(SELECT 1 FROM public.agent_engine_recovery_checkpoints WHERE run_id IN(codex_rehearsal.id(1002),codex_rehearsal.id(1004))),'owner Claude/routine checkpoints purged');
SELECT codex_rehearsal.assert((SELECT count(*)=2 FROM public.agent_engine_runs WHERE id IN(codex_rehearsal.id(1002),codex_rehearsal.id(1004)) AND created_by IS NULL),'owner Claude/routine lineage anonymized');
SELECT codex_rehearsal.assert((SELECT to_jsonb(r) FROM public.agent_engine_runs r WHERE id=codex_rehearsal.id(1003))=(SELECT x FROM codex_rehearsal.snapshots s,jsonb_array_elements(s.state->'public.agent_engine_runs'->'rows') x WHERE s.label='before-engine-erasure' AND x->>'id'=codex_rehearsal.id(1003)::text),'same-workspace member complete run retained');
SELECT codex_rehearsal.assert((SELECT to_jsonb(c) FROM public.agent_engine_recovery_checkpoints c WHERE run_id=codex_rehearsal.id(1003))=(SELECT x FROM codex_rehearsal.snapshots s,jsonb_array_elements(s.state->'public.agent_engine_recovery_checkpoints'->'rows') x WHERE s.label='before-engine-erasure' AND x->>'run_id'=codex_rehearsal.id(1003)::text),'same-workspace member complete checkpoint retained');
-- Engine-only anonymisation retains the account/membership/ack ledger. The
-- separate account deletion path removes acknowledgments by the users FK;
-- that full account deletion is outside this scoped SQL scenario.
-- Complete other-tenant rows, not selected columns, must remain byte-equal as
-- normalized JSON. Excludes our intended owner mutation only by exact row key.
SELECT codex_rehearsal.assert((SELECT to_jsonb(r) FROM public.agent_engine_runs r WHERE id=codex_rehearsal.id(2001))=(SELECT x FROM codex_rehearsal.snapshots s,jsonb_array_elements(s.state->'public.agent_engine_runs'->'rows') x WHERE s.label='before-erasure' AND x->>'id'=codex_rehearsal.id(2001)::text),'other tenant full run retained');
SELECT codex_rehearsal.assert((SELECT to_jsonb(c) FROM public.agent_engine_recovery_checkpoints c WHERE run_id=codex_rehearsal.id(2001))=(SELECT x FROM codex_rehearsal.snapshots s,jsonb_array_elements(s.state->'public.agent_engine_recovery_checkpoints'->'rows') x WHERE s.label='before-erasure' AND x->>'run_id'=codex_rehearsal.id(2001)::text),'other tenant full checkpoint retained');
SELECT codex_rehearsal.assert((codex_rehearsal.state()->'public._schema_migrations')=(SELECT state->'public._schema_migrations' FROM codex_rehearsal.snapshots WHERE label='before-erasure'),'full ledger unchanged');
SELECT codex_rehearsal.assert((codex_rehearsal.state()->'auth.users')=(SELECT state->'auth.users' FROM codex_rehearsal.snapshots WHERE label='before-erasure'),'engine-only erasure leaves auth rows');
SELECT codex_rehearsal.assert(
 (codex_rehearsal.state()-'public.agent_engine_runs'-'public.workspace_engine_settings'-'public.agent_engine_recovery_checkpoints')=
 (SELECT state-'public.agent_engine_runs'-'public.workspace_engine_settings'-'public.agent_engine_recovery_checkpoints' FROM codex_rehearsal.snapshots WHERE label='before-engine-erasure'),
 'every unrelated full public/auth/storage row and census unchanged by engine erasure');
SELECT codex_rehearsal.assert((SELECT to_jsonb(s) FROM public.workspace_engine_settings s WHERE workspace_id=(SELECT value FROM codex_rehearsal.ids WHERE label='other-workspace'))=(SELECT x FROM codex_rehearsal.snapshots s,jsonb_array_elements(s.state->'public.workspace_engine_settings'->'rows') x WHERE s.label='before-engine-erasure' AND x->>'workspace_id'=(SELECT value::text FROM codex_rehearsal.ids WHERE label='other-workspace')),'other tenant settings full row retained');
INSERT INTO codex_rehearsal.snapshots VALUES('after-scenarios',codex_rehearsal.state());
-- Engine-scoped anonymisation is not full account deletion or legal clearance.
