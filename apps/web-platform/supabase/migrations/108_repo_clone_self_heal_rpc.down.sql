-- 108_repo_clone_self_heal_rpc.down.sql
-- Reverse of 108_repo_clone_self_heal_rpc.sql — drop the two dispatch
-- self-heal RPCs. No schema/data change to reverse (the fns are additive;
-- repo_status/repo_last_synced_at/repo_error predate this migration).

BEGIN;

DROP FUNCTION IF EXISTS public.set_repo_status(uuid, text, text);
DROP FUNCTION IF EXISTS public.claim_repo_clone_lock(uuid);

COMMIT;
