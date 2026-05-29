-- 084_byok_delegation_withdrawals.down.sql
-- Reverse of 084_byok_delegation_withdrawals.sql. Order:
--   1. Restore check_and_record_byok_delegation_use to its mig 064 form
--      (drop the per-turn consent re-gate).
--   2. Restore resolve_byok_key_owner to its mig 083 form (acceptance gate
--      kept; withdrawal clause removed).
--   3. Restore attribution_shift_reason CHECK to the pre-084 enum.
--   4. Drop the withdrawal RPCs + WORM trigger fn.
--   5. Drop byok_delegation_withdrawals (CASCADE removes RLS + indexes +
--      triggers).
--
-- NOTE: step 3 narrows the enum. If any audit_byok_use row carries
-- attribution_shift_reason='consent_withdrawn' (written by the re-gate
-- before rollback), the ADD CONSTRAINT will fail — null those rows first
-- in an operator step. Acceptable for a deliberate rollback.

BEGIN;

-- 1. Restore cap RPC to mig 064 form (no consent re-gate).
CREATE OR REPLACE FUNCTION public.check_and_record_byok_delegation_use(
  p_delegation_id    uuid,
  p_invocation_id    uuid,
  p_token_count      int,
  p_unit_cost_cents  int,
  p_caller_user_id   uuid,
  p_agent_role       text
) RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_row             public.byok_delegations%ROWTYPE;
  v_this_cost       int := p_token_count * p_unit_cost_cents;
  v_hourly_spent    int;
  v_daily_spent     int;
BEGIN
  IF p_delegation_id IS NULL OR p_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'check_and_record_byok_delegation_use: p_delegation_id and p_caller_user_id are required'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_row
    FROM public.byok_delegations
   WHERE id = p_delegation_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'check_and_record_byok_delegation_use: delegation % not found', p_delegation_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_row.grantor_user_id IS NULL OR v_row.workspace_id IS NULL THEN
    RAISE EXCEPTION 'byok_delegations:anonymised'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_row.revoked_at IS NOT NULL
     AND clock_timestamp() > v_row.revoked_at + interval '60 seconds' THEN
    INSERT INTO public.audit_byok_use (
      invocation_id, founder_id, workspace_id, agent_role,
      token_count, unit_cost_cents, delegation_id, attribution_shift_reason
    ) VALUES (
      p_invocation_id, p_caller_user_id, v_row.workspace_id, p_agent_role,
      p_token_count, p_unit_cost_cents, p_delegation_id, 'revoked_post_grace'
    )
    ON CONFLICT (invocation_id) DO NOTHING;
    RAISE EXCEPTION 'byok_delegations:revoked_post_grace'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_row.expires_at IS NOT NULL
     AND clock_timestamp() > v_row.expires_at THEN
    INSERT INTO public.audit_byok_use (
      invocation_id, founder_id, workspace_id, agent_role,
      token_count, unit_cost_cents, delegation_id, attribution_shift_reason
    ) VALUES (
      p_invocation_id, p_caller_user_id, v_row.workspace_id, p_agent_role,
      p_token_count, p_unit_cost_cents, p_delegation_id, 'expired'
    )
    ON CONFLICT (invocation_id) DO NOTHING;
    RAISE EXCEPTION 'byok_delegations:expired'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE(SUM(au.token_count * au.unit_cost_cents), 0)::int
    INTO v_hourly_spent
    FROM public.audit_byok_use au
   WHERE au.delegation_id = p_delegation_id
     AND au.ts > clock_timestamp() - interval '1 hour';

  IF v_hourly_spent + v_this_cost > v_row.hourly_usd_cap_cents THEN
    RAISE EXCEPTION 'byok_delegations:hourly_cap_exceeded'
      USING ERRCODE = 'P0001',
            DETAIL = format('hourly cap %s cents, spent %s, attempted +%s',
                            v_row.hourly_usd_cap_cents, v_hourly_spent, v_this_cost);
  END IF;

  SELECT COALESCE(SUM(au.token_count * au.unit_cost_cents), 0)::int
    INTO v_daily_spent
    FROM public.audit_byok_use au
   WHERE au.delegation_id = p_delegation_id
     AND au.ts > clock_timestamp() - interval '24 hours';

  IF v_daily_spent + v_this_cost > v_row.daily_usd_cap_cents THEN
    RAISE EXCEPTION 'byok_delegations:daily_cap_exceeded'
      USING ERRCODE = 'P0001',
            DETAIL = format('daily cap %s cents, spent %s, attempted +%s',
                            v_row.daily_usd_cap_cents, v_daily_spent, v_this_cost);
  END IF;

  INSERT INTO public.audit_byok_use (
    invocation_id, founder_id, workspace_id, agent_role,
    token_count, unit_cost_cents, delegation_id, attribution_shift_reason
  ) VALUES (
    p_invocation_id, v_row.grantor_user_id, v_row.workspace_id, p_agent_role,
    p_token_count, p_unit_cost_cents, p_delegation_id, NULL
  )
  ON CONFLICT (invocation_id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.check_and_record_byok_delegation_use(uuid, uuid, int, int, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_record_byok_delegation_use(uuid, uuid, int, int, uuid, text)
  TO service_role;

-- 2. Restore resolver to mig 083 form (acceptance gate kept; no withdrawal clause).
CREATE OR REPLACE FUNCTION public.resolve_byok_key_owner(
  p_caller_user_id uuid,
  p_workspace_id   uuid
) RETURNS TABLE (
  key_owner_user_id uuid,
  delegation_id     uuid
)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'resolve_byok_key_owner: p_caller_user_id is NULL'
      USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.api_keys WHERE user_id = p_caller_user_id
  ) THEN
    key_owner_user_id := p_caller_user_id;
    delegation_id     := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  RETURN QUERY
    SELECT bd.grantor_user_id, bd.id
      FROM public.byok_delegations bd
     WHERE bd.grantee_user_id = p_caller_user_id
       AND bd.workspace_id    = p_workspace_id
       AND bd.revoked_at IS NULL
       AND (bd.expires_at IS NULL OR bd.expires_at > clock_timestamp())
       AND EXISTS (
         SELECT 1 FROM public.byok_delegation_acceptances a
          WHERE a.delegation_id = bd.id
            AND a.user_id       = bd.grantee_user_id
            AND a.side_letter_version = public.current_byok_side_letter_version()
       )
     ORDER BY bd.created_at DESC
     LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_byok_key_owner(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_byok_key_owner(uuid, uuid)
  TO service_role;

-- 3. Restore the pre-084 attribution_shift_reason enum.
ALTER TABLE public.audit_byok_use
  DROP CONSTRAINT IF EXISTS audit_byok_use_attribution_shift_reason_check;
ALTER TABLE public.audit_byok_use
  ADD CONSTRAINT audit_byok_use_attribution_shift_reason_check
  CHECK (
    attribution_shift_reason IS NULL
    OR attribution_shift_reason IN ('revoked_post_grace','expired')
  );

-- 4. Drop withdrawal RPCs + WORM trigger fn.
DROP FUNCTION IF EXISTS public.withdraw_byok_delegation_consent(uuid);
DROP FUNCTION IF EXISTS public.anonymise_byok_delegation_withdrawals(uuid);
DROP TRIGGER IF EXISTS byok_delegation_withdrawals_no_update ON public.byok_delegation_withdrawals;
DROP TRIGGER IF EXISTS byok_delegation_withdrawals_no_delete ON public.byok_delegation_withdrawals;
DROP FUNCTION IF EXISTS public.byok_delegation_withdrawals_no_mutate();

-- 5. Drop the table (CASCADE removes RLS policies + indexes).
DROP TABLE IF EXISTS public.byok_delegation_withdrawals CASCADE;

COMMIT;
