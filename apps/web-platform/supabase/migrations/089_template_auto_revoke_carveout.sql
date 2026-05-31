-- Migration 089: auto-revoke carve-out for revoke_template_authorization (#4709)
--
-- ❶ WHAT THIS DOES
--   `CREATE OR REPLACE`s `revoke_template_authorization` (same (text,text)
--   signature, same `RETURNS integer` — an in-place replace, NOT a DROP+CREATE,
--   so no rolling-deploy gap and no grant churn) to add a narrow carve-out to
--   the founder-attribution gate: an AUTHENTICATED founder may auto-revoke their
--   OWN row with reason 'expired' or 'quota_exhausted', but ONLY when this RPC
--   RE-DERIVES the dead state server-side. The passed p_reason is never trusted;
--   a spoofed reason on a still-live row raises 42501.
--
--   This file is migration 088's body REPRODUCED VERBATIM except the single
--   founder-attribution gate block (088 L134-150), which is replaced by the
--   carve-out below. Everything else — the authenticated-session guard, the
--   8-value p_reason enum gate, the `SET LOCAL app.worm_bypass` on/off bracket,
--   the `RETURNS integer` / `GET DIAGNOSTICS affected = ROW_COUNT` / `RETURN
--   affected` shape, the `WHERE founder_id = v_founder_id` UPDATE, the
--   search_path pin, SECURITY DEFINER, and the grants — is unchanged from 088.
--
--   Migration 053 created the RPC; 087/088 swapped it onto the privilege-free
--   `app.worm_bypass` GUC; 089 adds the carve-out.
--
-- ❷ WHY (#4709)
--   The send-gate (`server/templates/is-template-authorized.ts`) detects an
--   expired / quota-exhausted authorization and fires
--   `autoRevoke(client, hash, 'expired'|'quota_exhausted')` to persist
--   `revoked_at` / `revocation_reason` so the scope-grants UI does not render
--   dead-but-"active" lying rows. That call uses the AUTHENTICATED request
--   client, so inside the RPC `auth.uid()` is non-NULL and the founder-
--   attribution gate (053, preserved verbatim in 087/088) raised 42501 for any
--   authenticated caller whose reason <> 'founder_revoked' — so the auto-revoke
--   could NEVER persist. The bug is upstream of the WORM bypass; migration 088
--   (the GUC swap) did not and could not fix it.
--
-- ❸ SECURITY INVARIANT PRESERVED
--   The gate exists to stop an authenticated founder stamping ARBITRARY
--   revocation reasons on their own WORM audit rows (PR-I user-impact-reviewer
--   FINDING 1). The carve-out does NOT reopen that: it admits ONLY
--   'expired'/'quota_exhausted', ONLY for the caller's own most-recent row, and
--   ONLY after RE-DERIVING the dead state from `expires_at` / the `action_sends`
--   count (>= max_sends — boundary parity with is-template-authorized.ts:152).
--   Every other non-'founder_revoked' reason (dsr_erasure, regulator_ordered,
--   vendor_tos_revoked, policy_violation, quarantine_retroactive) still raises
--   42501 for authenticated callers. The authenticated-session guard
--   (auth.uid() IS NULL -> 42501) and the 8-value enum gate (22023) are
--   unchanged, so service-role / postgres callers remain rejected exactly as in
--   088.
--
-- ❹ ROLLBACK
--   `089_..._carveout.down.sql` reverts revoke_template_authorization to the 088
--   body verbatim (re-raises 42501 for authenticated expired/quota_exhausted).
--
-- Refs: migration 053 (template authz gate), 087/088 (WORM swap), this (089)

CREATE OR REPLACE FUNCTION public.revoke_template_authorization(
  p_template_hash text,
  p_reason        text
) RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  affected integer;
  v_founder_id uuid := auth.uid();
  -- 089 carve-out locals (re-derivation of dead state).
  v_row public.template_authorizations%ROWTYPE;
  v_sends_used integer;
  v_state_ok boolean;
BEGIN
  IF v_founder_id IS NULL THEN
    RAISE EXCEPTION 'revoke_template_authorization: authenticated session required'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason NOT IN (
    'founder_revoked', 'quota_exhausted', 'expired', 'dsr_erasure',
    'regulator_ordered', 'vendor_tos_revoked', 'policy_violation',
    'quarantine_retroactive'
  ) THEN
    RAISE EXCEPTION 'revoke_template_authorization: invalid reason %', p_reason
      USING ERRCODE = '22023';
  END IF;

  -- Founder-attribution gate (mig 053, preserved) + auto-revoke carve-out
  -- (mig 089, #4709).
  --
  -- An authenticated caller may revoke freely with reason='founder_revoked'
  -- (the /api/template-authorizations/revoke surface). For the auto-revoke
  -- reasons 'expired'/'quota_exhausted' fired by the isTemplateAuthorized
  -- predicate, the RPC RE-DERIVES the dead state for the CALLER'S OWN
  -- most-recent row and rejects a spoofed reason with 42501 — the passed
  -- p_reason is never trusted. Every OTHER non-'founder_revoked' reason stays
  -- forbidden for authenticated callers, preserving the 053 attribution
  -- invariant (user-impact-reviewer FINDING 1): an authenticated founder must
  -- not be able to stamp dsr_erasure / regulator_ordered / vendor_tos_revoked /
  -- policy_violation / quarantine_retroactive on their own audit rows.
  IF v_founder_id IS NOT NULL AND p_reason <> 'founder_revoked' THEN
    IF p_reason IN ('expired', 'quota_exhausted') THEN
      -- Re-derive against the caller's own most-recent row (mirrors the
      -- predicate's `order by authorized_at desc limit 1`).
      --
      -- Deliberately NOT filtered by `revoked_at IS NULL`: the partial-UNIQUE
      -- index `template_authorizations_active_unique (founder_id,
      -- template_hash) WHERE revoked_at IS NULL` (mig 053) guarantees at most
      -- one active row per (founder, hash), and that active row is the most
      -- recent (authorize_template is first-writer-wins), so the row checked
      -- here IS the row the UPDATE below targets. The already-revoked case is
      -- the idempotent no-op: re-derivation passes on the dead row's bounds,
      -- then the UPDATE's `revoked_at IS NULL` matches zero rows → affected=0,
      -- no throw (regression test `(#4709 carve-out: idempotent)`). Adding
      -- `AND revoked_at IS NULL` here would instead raise 42501 on the second
      -- fire — do NOT add it.
      SELECT * INTO v_row
        FROM public.template_authorizations
       WHERE template_hash = p_template_hash
         AND founder_id = v_founder_id
       ORDER BY authorized_at DESC
       LIMIT 1;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'revoke_template_authorization: no self-owned row to auto-revoke (hash=%)', p_template_hash
          USING ERRCODE = '42501';
      END IF;

      IF p_reason = 'expired' THEN
        v_state_ok := v_row.expires_at <= now();
      ELSE  -- 'quota_exhausted'
        SELECT count(*) INTO v_sends_used
          FROM public.action_sends
         WHERE user_id = v_founder_id
           AND template_hash = p_template_hash;
        -- Boundary parity with is-template-authorized.ts:152 (>=, not >).
        v_state_ok := v_sends_used >= v_row.max_sends;
      END IF;

      IF NOT v_state_ok THEN
        RAISE EXCEPTION 'revoke_template_authorization: reason=% does not match derived row state (anti-spoof)', p_reason
          USING ERRCODE = '42501';
      END IF;
    ELSE
      -- All other non-founder_revoked reasons remain forbidden for
      -- authenticated callers (053 attribution invariant).
      RAISE EXCEPTION 'revoke_template_authorization: authenticated callers must use reason=founder_revoked (got %)', p_reason
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- WORM trigger blocks all UPDATEs including founder-initiated revoke; bypass is required.
  -- app.worm_bypass='on' makes the no-mutate trigger function skip its reject for
  -- this transaction (privilege-free GUC honored by template_authorizations_no_mutate
  -- after mig 087; was session_replication_role, superuser-only → 42501 on managed
  -- Supabase, #4702). Re-armed 'off' after the UPDATE.
  SET LOCAL app.worm_bypass = 'on';
  UPDATE public.template_authorizations
     SET revoked_at = now(),
         revocation_reason = p_reason
   WHERE founder_id = v_founder_id
     AND template_hash = p_template_hash
     AND revoked_at IS NULL;
  GET DIAGNOSTICS affected = ROW_COUNT;
  SET LOCAL app.worm_bypass = 'off';

  RETURN affected;
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_template_authorization(text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.revoke_template_authorization(text, text)
  TO authenticated;

COMMENT ON FUNCTION public.revoke_template_authorization(text, text) IS
  'Founder-initiated revoke (Art. 7(3) "as easily withdrawable as given"). '
  'Also called auto-revoke-side-effect from the isTemplateAuthorized '
  'predicate on quota/expired detection so the scope-grants UI does '
  'not display lying rows. Mig 089 (#4709) adds a narrow carve-out: an '
  'authenticated founder may revoke their OWN row with reason '
  '''expired''/''quota_exhausted'' ONLY when the RPC re-derives the dead '
  'state server-side (anti-spoof); all other non-''founder_revoked'' reasons '
  'still raise 42501 for authenticated callers. WORM bypass via SET LOCAL '
  'app.worm_bypass=''on'' (privilege-free; replaces the prior superuser-only '
  'replica-role GUC that raised 42501 on managed Supabase); re-armed ''off'' '
  'after the UPDATE. #4702, #4709.';

-- Migration 089 ends.
