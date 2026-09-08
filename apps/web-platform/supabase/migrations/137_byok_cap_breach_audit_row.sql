-- 137_byok_cap_breach_audit_row.sql
-- fix(byok): a refusal must persist its audit row (#7829).
--
-- LAWFUL_BASIS: Art. 6(1)(b) — billing accounting for a delegated key.
-- RETENTION: 7 years (unchanged; inherits audit_byok_use).
--
-- THE DEFECT, AND IT IS WIDER THAN THE ISSUE TITLE SAYS.
--
-- #7829 was filed against the two cap branches of
-- check_and_record_byok_delegation_use, which SELECT the spend window and
-- then RAISE without writing an audit_byok_use row -- while the three
-- sibling refusal branches (revoked_post_grace, consent_withdrawn, expired)
-- visibly INSERT before raising and therefore looked correct.
--
-- They are not correct. An unhandled plpgsql RAISE EXCEPTION aborts the
-- transaction, and the INSERT executed earlier in that same transaction is
-- rolled back with it. The function declares no EXCEPTION handler (verified:
-- zero WHEN clauses in the 084 body). So NO refusal branch has ever
-- persisted a row -- the defect is five branches, not two, and the obvious
-- repair ("add the two missing INSERTs") would have shipped green while
-- still writing nothing.
--
-- WHY THAT COSTS THE GRANTOR MONEY. persistTurnCost runs after
-- messages.create, so the provider has already been charged by the time the
-- refusal is decided. Both cap windows are SUMs over exactly the rows that
-- are not being written, so the numerator never advances: every later turn
-- in the window also exceeds, also refuses, also writes nothing. The state
-- is self-sustaining until the window rolls, and it is invisible in the
-- ledger the whole time. Migration 061 states the house rule this violates
-- ("accounting is sacred").
--
-- THE FIX: refusal stops being an exception and becomes a RETURNED VALUE.
-- A return-type change cannot use CREATE OR REPLACE, so this is DROP +
-- CREATE; run-migrations.sh applies with --single-transaction, so the
-- window is atomic. The shape converges on the sibling cap RPC in the same
-- family -- 121's record_byok_use_and_check_cap already RETURNS TABLE and
-- signals its cap trip by returning kill_tripped for the caller to act on.
-- This is the established in-family shape, not a novel design.
--
-- ADR-040 Decision #1 is preserved and strengthened: FOR UPDATE, both window
-- SUMs and the audit INSERT remain in ONE transaction under ONE row lock.
-- Only the refusal signal changes. Because the refusal row now commits
-- inside the lock, a concurrent caller's SUM can see it -- which is the
-- TOCTOU close D1 exists for and which the current code silently fails to
-- deliver.
--
-- SCOPE NOTE: this migration corrects the unit semantics of its OWN
-- delegation windows only. unit_cost_cents holds the WHOLE TURN's cost
-- (cost-writer.ts: Math.round(costDelta * 100) where costDelta =
-- totalCostUsd), so `token_count * unit_cost_cents` is dimensionally
-- cents-times-tokens and trips any real cap on the first turn. Because a
-- refusal here decides founder_id -- grantee on refusal, grantor on
-- admission -- shipping that defect would mis-attribute the billing party
-- on 100% of delegated rows into a WORM table. Correcting attribution is
-- #7829's remit. The founder-wide instances of the same expression
-- (migrations 061 and 121, ADR-041 Layer 1) are deliberately UNTOUCHED and
-- remain tracked separately, so the delegation accumulator and the founder
-- accumulator carry different formulas until that lands. Recorded in ADR-208.

BEGIN;

-- =====================================================================
-- 1. Widen the attribution_shift_reason CHECK to admit the cap reasons
-- =====================================================================
-- Underscores, matching the three existing values ('revoked_post_grace',
-- 'expired', 'consent_withdrawn' -- see 084's
-- audit_byok_use_attribution_shift_reason_check). NOT the hyphenated
-- Sentry `op` slugs -- migration 064 establishes that only `cross-tenant`
-- is hyphenated, and harmonising the two vocabularies is out of scope.
--
-- Deliberately NOT declared with the constraint-skipping qualifier that
-- defers the initial scan: it still enforces on subsequent UPDATEs, and
-- 065_art17_cascade_deadlock_repair.sql makes founder_id ON DELETE SET
-- NULL, so an account delete issues UPDATE ... SET founder_id = NULL. A
-- cap-reason row plus a narrowed constraint would abort that cascade and
-- fail auth.admin.deleteUser -- the exact incident 065/066 repaired.

ALTER TABLE public.audit_byok_use
  DROP CONSTRAINT IF EXISTS audit_byok_use_attribution_shift_reason_check;

ALTER TABLE public.audit_byok_use
  ADD CONSTRAINT audit_byok_use_attribution_shift_reason_check
  CHECK (
    attribution_shift_reason IS NULL
    OR attribution_shift_reason IN (
      'revoked_post_grace',
      'expired',
      'consent_withdrawn',
      'hourly_cap_exceeded',
      'daily_cap_exceeded'
    )
  );

-- =====================================================================
-- 2. check_and_record_byok_delegation_use — refusal returns, never raises
-- =====================================================================
-- Signature, SECURITY DEFINER, search_path pin and grants are re-issued
-- verbatim from 084 (cq-pg-security-definer-search-path-pin-pg-temp).
-- Only the return type and the refusal signalling change.

DROP FUNCTION IF EXISTS public.check_and_record_byok_delegation_use(uuid, uuid, int, int, uuid, text);

CREATE FUNCTION public.check_and_record_byok_delegation_use(
  p_delegation_id    uuid,
  p_invocation_id    uuid,
  p_token_count      int,
  p_unit_cost_cents  int,
  p_caller_user_id   uuid,
  p_agent_role       text
) RETURNS TABLE(refusal_reason text)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_row             public.byok_delegations%ROWTYPE;
  v_this_cost       int := p_unit_cost_cents;
  v_hourly_spent    int;
  v_daily_spent     int;
BEGIN
  -- Validation failures still RAISE. These are caller bugs or anonymised
  -- state, not accounted refusals: no provider call is attributable to a
  -- delegation that does not resolve, so there is no row owed.
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

  -- Caller identity pin. NOTE the reason above does NOT extend to this
  -- branch: here the delegation RESOLVES fine and the provider has already
  -- been charged, so money moved and nothing is ledgered. Booking the row
  -- anyway is worse (it would assert a billing party we know is wrong), so
  -- the gap is accepted and tracked rather than papered over.
  -- 084 never validated p_caller_user_id against the
  -- delegation: the consent re-gate reads withdrawals by grantee_user_id
  -- while every INSERT writes founder_id = p_caller_user_id. Once a refusal
  -- row actually persists, founder_id becomes a durable BILLING assertion
  -- that enters the named user's DSAR export -- so an unvalidated caller
  -- would let one user's refusal be booked against another's identity.
  IF p_caller_user_id IS DISTINCT FROM v_row.grantee_user_id THEN
    RAISE EXCEPTION 'byok_delegations:caller_not_grantee'
      USING ERRCODE = '42501';
  END IF;

  -- Grace check (clock_timestamp() not now()): revoke past 60s grace.
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
    refusal_reason := 'revoked_post_grace';
    RETURN NEXT;
    RETURN;
  END IF;

  -- Per-turn consent re-gate (#4625 deepen P1): a mid-run withdrawal that
  -- post-dates the latest current-version acceptance stops in-flight
  -- billing within ONE turn and DEBITS THE GRANTEE.
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
    refusal_reason := 'consent_withdrawn';
    RETURN NEXT;
    RETURN;
  END IF;

  -- Expired check.
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
    refusal_reason := 'expired';
    RETURN NEXT;
    RETURN;
  END IF;

  -- Hourly cap SUM (rolling 1h). Unfiltered on attribution_shift_reason by
  -- design: the refusal rows record money that HAS already moved, so
  -- excluding them would freeze the numerator at its last in-cap value and
  -- let every turn small enough to fit under (cap - frozen) pass forever.
  SELECT COALESCE(SUM(au.unit_cost_cents), 0)::int
    INTO v_hourly_spent
    FROM public.audit_byok_use au
   WHERE au.delegation_id = p_delegation_id
     AND au.ts > clock_timestamp() - interval '1 hour';

  IF v_hourly_spent + v_this_cost > v_row.hourly_usd_cap_cents THEN
    INSERT INTO public.audit_byok_use (
      invocation_id, founder_id, workspace_id, agent_role,
      token_count, unit_cost_cents, delegation_id, attribution_shift_reason
    ) VALUES (
      p_invocation_id, p_caller_user_id, v_row.workspace_id, p_agent_role,
      p_token_count, p_unit_cost_cents, p_delegation_id, 'hourly_cap_exceeded'
    )
    ON CONFLICT (invocation_id) DO NOTHING;
    refusal_reason := 'hourly_cap_exceeded';
    RETURN NEXT;
    RETURN;
  END IF;

  -- Daily cap SUM (rolling 24h). Same unfiltered rationale as above.
  SELECT COALESCE(SUM(au.unit_cost_cents), 0)::int
    INTO v_daily_spent
    FROM public.audit_byok_use au
   WHERE au.delegation_id = p_delegation_id
     AND au.ts > clock_timestamp() - interval '24 hours';

  IF v_daily_spent + v_this_cost > v_row.daily_usd_cap_cents THEN
    INSERT INTO public.audit_byok_use (
      invocation_id, founder_id, workspace_id, agent_role,
      token_count, unit_cost_cents, delegation_id, attribution_shift_reason
    ) VALUES (
      p_invocation_id, p_caller_user_id, v_row.workspace_id, p_agent_role,
      p_token_count, p_unit_cost_cents, p_delegation_id, 'daily_cap_exceeded'
    )
    ON CONFLICT (invocation_id) DO NOTHING;
    refusal_reason := 'daily_cap_exceeded';
    RETURN NEXT;
    RETURN;
  END IF;

  -- Pass: write audit row with grantor attribution (normal accounting).
  INSERT INTO public.audit_byok_use (
    invocation_id, founder_id, workspace_id, agent_role,
    token_count, unit_cost_cents, delegation_id, attribution_shift_reason
  ) VALUES (
    p_invocation_id, v_row.grantor_user_id, v_row.workspace_id, p_agent_role,
    p_token_count, p_unit_cost_cents, p_delegation_id, NULL
  )
  ON CONFLICT (invocation_id) DO NOTHING;

  refusal_reason := NULL;
  RETURN NEXT;
  RETURN;
END;
$$;

REVOKE ALL ON FUNCTION public.check_and_record_byok_delegation_use(uuid, uuid, int, int, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_record_byok_delegation_use(uuid, uuid, int, int, uuid, text)
  TO service_role;

COMMENT ON FUNCTION public.check_and_record_byok_delegation_use(uuid, uuid, int, int, uuid, text) IS
  'Per-turn delegated-key gate. Returns refusal_reason (NULL = admitted). '
  'Every refusal persists an audit_byok_use row attributed to the grantee '
  'BEFORE returning; refusal is never signalled by RAISE, because an '
  'unhandled RAISE would roll back that row (#7829). Service-role-only.';

-- =====================================================================
-- 3. record_byok_use_and_check_cap — personal cap excludes delegated spend
-- =====================================================================
-- Consequence of section 2, and introduced BY it. Cap rows are attributed
-- to the grantee (founder_id = p_caller_user_id). 121's founder SUM groups
-- by founder_id with no delegation filter and flips users.runtime_paused_at
-- on breach, so a persisted grantee-attributed cap row would enter the
-- GRANTEE's own ADR-041 Layer 1 accumulator against their personal
-- runtime_cost_cap_cents. Net effect: a grantee who exceeds SOMEONE ELSE's
-- delegation cap gets their own agent runtime paused and must manually
-- Resume. That was unreachable before this migration precisely because no
-- refusal row persisted.
--
-- The filter excludes exactly the refusal rows this migration creates --
-- nothing else. `delegation_id IS NULL` was considered and REJECTED as
-- over-broad: 121's founder SUM has no delegation filter at all, so ADMITTED
-- delegated rows (founder_id = grantor, attribution_shift_reason IS NULL)
-- have always counted against the grantor's own Layer 1 cap, and correctly
-- so -- the grantor's key paid. Excluding them would be an undeclared
-- weakening of ADR-041 Layer 1 that #7829 never asked for, and under the
-- corrected delegation arithmetic it would leave the grantor's real
-- delegated exposure unmeasured by any accumulator.
--
-- Body is 121's verbatim except for that filter. The token_count product
-- HERE is deliberately left ALONE and is the DEFECT held pending the
-- founder-wide fix -- not the correct form. See ADR-208 Decision 3.

CREATE OR REPLACE FUNCTION public.record_byok_use_and_check_cap(
  p_invocation_id   uuid,
  p_founder_id      uuid,
  p_workspace_id    uuid,
  p_agent_role      text,
  p_token_count     int,
  p_unit_cost_cents int
) RETURNS TABLE(cumulative_cents int, kill_tripped boolean)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_cap        int;
  v_paused_at  timestamptz;
  v_total      int;
  v_tripped    boolean := false;
BEGIN
  SELECT runtime_cost_cap_cents, runtime_paused_at
    INTO v_cap, v_paused_at
    FROM public.users
   WHERE id = p_founder_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'record_byok_use_and_check_cap: founder % not found', p_founder_id
      USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.audit_byok_use (
    invocation_id, founder_id, workspace_id, agent_role, token_count, unit_cost_cents
  ) VALUES (
    p_invocation_id, p_founder_id, p_workspace_id, p_agent_role, p_token_count, p_unit_cost_cents
  );

  -- attribution_shift_reason IS NULL added by 137 (#7829): excludes exactly
  -- the refusal rows this migration creates, and nothing else.
  SELECT COALESCE(SUM(token_count * unit_cost_cents), 0)::int
    INTO v_total
    FROM public.audit_byok_use
   WHERE founder_id = p_founder_id
     AND attribution_shift_reason IS NULL
     AND ts > now() - interval '1 hour';

  IF v_total > v_cap THEN
    UPDATE public.users
       SET runtime_paused_at = now()
     WHERE id = p_founder_id
       AND runtime_paused_at IS NULL;
    v_tripped := FOUND;
  END IF;

  cumulative_cents := v_total;
  kill_tripped     := v_tripped;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.record_byok_use_and_check_cap(uuid, uuid, uuid, text, int, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_byok_use_and_check_cap(uuid, uuid, uuid, text, int, int)
  TO service_role;

-- =====================================================================
-- 4. Correct the founder_id column comment (mig 066 is forward-only)
-- =====================================================================
-- 066's comment calls founder_id "Owner of the BYOK invocation" and advises
-- aggregating on workspace_id. Both are wrong for the rows section 2 now
-- writes: on a refused delegated turn founder_id is the GRANTEE while
-- workspace_id stays the GRANTOR-scoped delegation workspace, so the two
-- columns name DIFFERENT parties on exactly those rows.

COMMENT ON COLUMN public.audit_byok_use.founder_id IS
  'The party CHARGED for the invocation - not necessarily the owner of the key '
  'it ran on. On a non-delegated row (delegation_id IS NULL) the two coincide. '
  'On a delegated row they can differ: an ADMITTED delegated turn '
  '(delegation_id IS NOT NULL, attribution_shift_reason IS NULL) carries the '
  'GRANTOR (the key owner); a REFUSED delegated turn (attribution_shift_reason '
  'IS NOT NULL - revoked_post_grace, expired, consent_withdrawn, '
  'hourly_cap_exceeded, daily_cap_exceeded; mig 137, #7829) carries the '
  'GRANTEE, because cost follows the party who continued past the boundary '
  '(ADR-045, ADR-208). workspace_id stays the GRANTOR-scoped delegation '
  'workspace on both, so on those rows founder_id and workspace_id name '
  'DIFFERENT parties. NULL after Art. 17 anonymisation (SET NULL cascade from '
  'public.users delete, mig 065 Part 2). AGGREGATION: neither column is a safe '
  'key on its own. For full historical cost coverage despite NULL founder_id, '
  'aggregate on workspace_id - but that books a grantee-attributed refusal into '
  'the GRANTOR''s workspace, so any PER-USER rollup must key on founder_id and '
  'discriminate delegated rows with delegation_id / attribution_shift_reason. '
  'NULL-founder rows are still present in the WORM ledger but have no live user '
  'FK.';

COMMIT;

-- Tracking row written in the same transaction by run-migrations.sh
-- (canonical) or the Doppler+pg fallback applier.
