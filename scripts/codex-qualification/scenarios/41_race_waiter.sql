\set ON_ERROR_STOP on
SET application_name='codex9051-rehearsal-waiter';
SET statement_timeout='30s';
SET lock_timeout='25s';
SET ROLE service_role;
SELECT set_config('request.jwt.claim.role','service_role',false);
-- Checkpoint RPC locks run then reads attempt generation. While holder is open
-- waits on its run lock; after COMMIT the generation check must reject 55000.
SELECT codex_rehearsal.expect_error($q$SELECT public.save_agent_engine_recovery_checkpoint(codex_rehearsal.id(1001),codex_rehearsal.id(5003),'{"threadId":"synthetic-racing-stale"}'::jsonb)$q$,'55000');
RESET ROLE;
