-- 137_byok_cap_breach_audit_row.down.sql
-- Rollback for 137 (#7829).
--
-- WHAT THIS RESTORES: the 084 function body, verbatim -- RETURNS void, with
-- refusal signalled by RAISE.
--
-- WHAT THIS DELIBERATELY DOES NOT UNDO, AND WHY.
--
-- 1. The widened attribution_shift_reason CHECK stays widened. ADR-040 set
--    this precedent for the sibling constraint on the same table ("Down
--    migration intentionally KEEPS this constraint"). Narrowing it back
--    would make every cap-reason row written while 137 was live violate the
--    constraint. That is not a theoretical tidiness concern:
--    065_art17_cascade_deadlock_repair.sql makes founder_id ON DELETE SET
--    NULL, so an account delete issues UPDATE ... SET founder_id = NULL --
--    which a narrowed CHECK re-validates, aborting the Art. 17 cascade and
--    failing auth.admin.deleteUser. That is the exact incident 065/066
--    repaired, and re-narrowing here would reintroduce it.
--
--    The constraint-skipping qualifier that defers the initial scan does NOT
--    solve this and is used nowhere in this pair: it still enforces on
--    subsequent UPDATEs, which is precisely the operation the cascade issues.
--
-- 2. The attribution_shift_reason IS NULL filter on record_byok_use_and_check_cap's
--    founder SUM stays. Rolling the code back does not delete the cap rows
--    137 already wrote. Those rows persist in the DELEGATION windows for up
--    to 24h (the daily branch) and in the Layer 1 founder window for 1h.
--    Restoring the unfiltered SUM while they are
--    still present would resume pausing grantees' own runtimes for exceeding
--    someone else's delegation cap -- the failure this filter exists to
--    prevent. The filter is correct on its own terms regardless of 137.
--
-- 3. Effects already written are not reversible by this file. Cap rows
--    remain in both delegation windows for up to 24h, and any
--    users.runtime_paused_at stamped by a contaminated Layer 1 SUM before
--    the filter landed clears only via the operator Resume route.
--
-- NOTE: run-migrations.sh SKIPS *.down.sql and does not content-sha track
-- it, so this file is never executed by the deploy path. It is executed
-- deliberately, against dev, as the AC-DOWN rollback rehearsal.

-- ORDERING PRECONDITION (verified live, SQLSTATE 42P13).
-- 084_byok_delegation_withdrawals.down.sql opens with a CREATE OR REPLACE of
-- this same function at RETURNS void. A return type cannot be changed by
-- CREATE OR REPLACE, so while 137 is live that file aborts on its FIRST
-- statement and every later step in it is skipped. THIS FILE MUST RUN FIRST.
-- (084's down has also been converted to DROP + CREATE so it is
-- order-independent; this note remains because an operator may hold an older
-- checkout of that file.)
--
-- 4. The corrected COMMENT ON COLUMN audit_byok_use.founder_id is NOT
--    reverted. After rollback it describes refusal rows that can no longer be
--    created, which is accurate for the frozen historical rows and stale for
--    new ones. Reverting it would re-assert 066's text, which was wrong for
--    cap rows in the first place.
--
-- 5. Rolling back restores 084's body verbatim, INCLUDING its
--    `token_count * unit_cost_cents` delegation windows. That is intended: a
--    rollback restores 084, defect included.
--
-- 6. A DB-only rollback (137 reverted, app still on the new bundle) makes
--    PostgREST return `null` for an admitted turn, which cost-writer.ts
--    classifies fail-closed as `unreadable-refusal-shape`. Expect one Sentry
--    event plus a read-back per delegated turn until the app is rolled back
--    too. This is correct fail-closed behaviour, not a regression.

BEGIN;

DROP FUNCTION IF EXISTS public.check_and_record_byok_delegation_use(uuid, uuid, int, int, uuid, text);

CREATE FUNCTION public.check_and_record_byok_delegation_use(
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

  IF EXISTS (
    SELECT 1 FROM public.byok_delegation_withdrawals w
     WHERE w.delegation_id = p_delegation_id
       AND w.user_id       = v_row.grantee_user_id
       AND w.withdrawn_at >= COALESCE(
         (SELECT max(a.accepted_at)
            FROM public.byok_delegation_acceptances a
           WHERE a.delegation_id = p_delegation_id
             AND a.user_id       = v_row.grantee_user_id),
         w.withdrawn_at)
  ) THEN
    INSERT INTO public.audit_byok_use (
      invocation_id, founder_id, workspace_id, agent_role,
      token_count, unit_cost_cents, delegation_id, attribution_shift_reason
    ) VALUES (
      p_invocation_id, p_caller_user_id, v_row.workspace_id, p_agent_role,
      p_token_count, p_unit_cost_cents, p_delegation_id, 'consent_withdrawn'
    )
    ON CONFLICT (invocation_id) DO NOTHING;
    RAISE EXCEPTION 'byok_delegations:consent_withdrawn'
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

-- DROP FUNCTION discards the COMMENT with the function. Without this the
-- rolled-back function carries no description at all -- neither 064's nor
-- 137's -- so the restore would not be the verbatim restore this file claims.
COMMENT ON FUNCTION public.check_and_record_byok_delegation_use(uuid, uuid, int, int, uuid, text) IS
  'Per-turn delegated-key gate (084 form, restored by 137.down). Signals '
  'refusal by RAISE, which aborts the transaction and DISCARDS the audit row '
  'inserted moments earlier -- the #7829 defect. Service-role-only.';

COMMIT;
