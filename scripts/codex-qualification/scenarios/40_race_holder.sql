-- Interactive owned holder session. Controller sends COMMIT separately only
-- after 42 observes the exact waiter blocked by this holder. Never auto-commit.
\set ON_ERROR_STOP on
SET application_name='codex9051-rehearsal-holder';
SET statement_timeout='30s';
SET lock_timeout='5s';
SET idle_in_transaction_session_timeout='30s';
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub',codex_rehearsal.id(1)::text,true);
SELECT public.set_workspace_default_engine((SELECT value FROM codex_rehearsal.ids WHERE label='owner-workspace'),'codex','managed',true,1);
SELECT 'owned-holder-switch-uncommitted' AS rehearsal_marker;
-- Transaction remains open; latest RPC holds workspace/settings/run locks.
