-- 051_action_class_widening_and_action_sends.down.sql
-- PR-H (#4077) — reverse migration. Restores pre-051 state.
--
-- ORDER MATTERS: drop dependent objects (triggers, indexes, RLS, RPC)
-- before tables; restore the prior scope_grants_tier_check before
-- accepting that mig 051's widening is gone.

-- (i) Restore grant_action_class to 3-tier list (mig 048 shape).
-- REVOKE/GRANT pattern mirrors the forward migration: explicit REVOKE from
-- PUBLIC + anon + authenticated, then GRANT to authenticated. CREATE OR
-- REPLACE preserves existing grants but the linter (test/migration-rpc-
-- grants.test.ts) requires the explicit REVOKE statement to be visible in
-- the migration source.
CREATE OR REPLACE FUNCTION public.grant_action_class(
  p_action_class text,
  p_tier         text
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_founder_id uuid := auth.uid();
  v_grant_id   uuid;
BEGIN
  IF v_founder_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;
  IF p_tier NOT IN ('auto', 'draft_one_click', 'approve_every_time') THEN
    RAISE EXCEPTION 'invalid tier: %', p_tier USING ERRCODE = '22P02';
  END IF;

  UPDATE public.scope_grants
     SET revoked_at = now(),
         revoked_reason = 'tier_change'
   WHERE founder_id = v_founder_id
     AND action_class = p_action_class
     AND revoked_at IS NULL;

  INSERT INTO public.scope_grants (founder_id, action_class, tier)
       VALUES (v_founder_id, p_action_class, p_tier)
  RETURNING id INTO v_grant_id;

  RETURN v_grant_id;
END;
$$;

REVOKE ALL ON FUNCTION public.grant_action_class(text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.grant_action_class(text, text)
  TO authenticated;

-- (h) Drop anonymise_action_sends RPC.
DROP FUNCTION IF EXISTS public.anonymise_action_sends(uuid);

-- (d-g) Drop action_sends table + dependents.
-- DROP TABLE ... CASCADE first removes the table along with its triggers,
-- policies, and indexes in a single statement. This is idempotent against
-- both apply-then-rollback (table exists) and fresh-rollback (table never
-- created) without needing a DO-block table-existence guard. PostgreSQL's
-- "DROP TRIGGER ... ON nonexistent_table" raises a 42P01 even with IF
-- EXISTS, so listing triggers/policies/indexes before the table fails on a
-- fresh DB where 051 never ran forward.
DROP TABLE IF EXISTS public.action_sends CASCADE;
-- The shared function survives table drop — it lives in pg_proc, not
-- pg_trigger. Drop it explicitly.
DROP FUNCTION IF EXISTS public.action_sends_no_mutate();

-- (c) Drop messages.action_class column + CHECK constraint.
ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_action_class_not_locked;
ALTER TABLE public.messages
  DROP COLUMN IF EXISTS action_class;

-- (b) Drop scope_grants enum-absence CHECK + active-grant partial UNIQUE.
DROP INDEX IF EXISTS public.scope_grants_active_unique;
ALTER TABLE public.scope_grants
  DROP CONSTRAINT IF EXISTS scope_grants_action_class_not_locked;

-- (a) Restore scope_grants_tier_check to 3-tier list (mig 048 shape).
ALTER TABLE public.scope_grants
  DROP CONSTRAINT IF EXISTS scope_grants_tier_check;
ALTER TABLE public.scope_grants
  ADD CONSTRAINT scope_grants_tier_check
  CHECK (tier IN ('auto', 'draft_one_click', 'approve_every_time'));
