-- 051_action_class_widening_and_action_sends.down.sql
-- PR-H (#4077) — reverse migration. Restores pre-051 state.
--
-- ORDER MATTERS: drop dependent objects (triggers, indexes, RLS, RPC)
-- before tables; restore the prior scope_grants_tier_check before
-- accepting that mig 051's widening is gone.

-- (i) Restore grant_action_class to 3-tier list (mig 048 shape).
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

-- (h) Drop anonymise_action_sends RPC.
DROP FUNCTION IF EXISTS public.anonymise_action_sends(uuid);

-- (d-g) Drop action_sends table + dependents.
DROP TRIGGER IF EXISTS action_sends_no_update ON public.action_sends;
DROP TRIGGER IF EXISTS action_sends_no_delete ON public.action_sends;
DROP FUNCTION IF EXISTS public.action_sends_no_mutate();
DROP INDEX IF EXISTS public.action_sends_user_clicked_idx;
DROP POLICY IF EXISTS action_sends_owner_select ON public.action_sends;
DROP POLICY IF EXISTS action_sends_owner_insert ON public.action_sends;
DROP TABLE IF EXISTS public.action_sends;

-- (c) Drop messages.action_class column.
ALTER TABLE public.messages
  DROP COLUMN IF EXISTS action_class;

-- (b) Drop scope_grants enum-absence CHECK.
ALTER TABLE public.scope_grants
  DROP CONSTRAINT IF EXISTS scope_grants_action_class_not_locked;

-- (a) Restore scope_grants_tier_check to 3-tier list (mig 048 shape).
ALTER TABLE public.scope_grants
  DROP CONSTRAINT IF EXISTS scope_grants_tier_check;
ALTER TABLE public.scope_grants
  ADD CONSTRAINT scope_grants_tier_check
  CHECK (tier IN ('auto', 'draft_one_click', 'approve_every_time'));
