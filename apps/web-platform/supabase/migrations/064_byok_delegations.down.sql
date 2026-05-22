-- 064_byok_delegations.down.sql (renumbered from 063 mid-flight).
-- Reverse of 064_byok_delegations.sql. Drops in dependency-safe order:
--   1. Workspace-members trigger (depends on byok_delegations_on_member_delete fn)
--   2. RPCs that reference byok_delegations
--   3. WORM + same-workspace triggers
--   4. Trigger functions
--   5. audit_byok_use.delegation_id column (FK back into byok_delegations)
--   6. byok_delegations table
--   7. audit_byok_use.attribution_shift_reason + invocation_id UNIQUE

BEGIN;

-- 1. Workspace-members cascade trigger
DROP TRIGGER IF EXISTS workspace_members_byok_delegations_revoke
  ON public.workspace_members;
DROP FUNCTION IF EXISTS public.byok_delegations_on_member_delete();

-- 2. RPCs
DROP FUNCTION IF EXISTS public.anonymise_byok_delegations(uuid);
DROP FUNCTION IF EXISTS public.check_and_record_byok_delegation_use(uuid, uuid, int, int, uuid, text);
DROP FUNCTION IF EXISTS public.resolve_byok_key_owner(uuid, uuid);
DROP FUNCTION IF EXISTS public.revoke_byok_delegation(uuid, uuid, text);
DROP FUNCTION IF EXISTS public.grant_byok_delegation(uuid, uuid, uuid, int, int, timestamptz, uuid);

-- 3. WORM + same-workspace triggers (table triggers drop with table,
-- but explicit drop is safer in case of partial-apply rollback paths).
DROP TRIGGER IF EXISTS byok_delegations_no_delete ON public.byok_delegations;
DROP TRIGGER IF EXISTS byok_delegations_no_update ON public.byok_delegations;
DROP TRIGGER IF EXISTS byok_delegations_same_workspace ON public.byok_delegations;

-- 4. Trigger functions
DROP FUNCTION IF EXISTS public.byok_delegations_no_mutate();
DROP FUNCTION IF EXISTS public.byok_delegations_check_same_workspace();

-- 5. audit_byok_use.delegation_id (drop FK column BEFORE byok_delegations)
DROP INDEX IF EXISTS public.audit_byok_use_delegation_ts_idx;
ALTER TABLE public.audit_byok_use
  DROP COLUMN IF EXISTS delegation_id;

-- 6. byok_delegations table (CASCADE removes RLS policy + indexes)
DROP TABLE IF EXISTS public.byok_delegations CASCADE;

-- 7. audit_byok_use trailing columns + UNIQUE constraint
ALTER TABLE public.audit_byok_use
  DROP COLUMN IF EXISTS attribution_shift_reason;

-- Keep audit_byok_use.invocation_id UNIQUE: the constraint becomes
-- load-bearing for Inngest-retry idempotency once any record_byok_use_*
-- / write_byok_audit caller uses ON CONFLICT (invocation_id) DO
-- NOTHING. Dropping it on rollback would silently re-open the
-- double-write window. Operators reapplying 064 will see the
-- IF NOT EXISTS guard in the DO block — no-op.

COMMIT;
