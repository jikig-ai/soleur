-- Down-migration 089: revert revoke_template_authorization to the 088 body.
--
-- Restores migration 088's body VERBATIM (the founder-attribution gate before
-- the 089 carve-out): an authenticated caller (auth.uid() non-NULL) with any
-- reason <> 'founder_revoked' — including 'expired'/'quota_exhausted' — is
-- rejected with 42501. The authenticated-session guard, 8-value enum gate,
-- `SET LOCAL app.worm_bypass` on/off bracket, `RETURNS integer` shape,
-- `WHERE founder_id = v_founder_id` UPDATE, search_path pin, SECURITY DEFINER,
-- grants, and COMMENT are identical to migration 088. Reverting re-introduces
-- #4709 (auto-revoke can never persist).
--
-- Refs: migration 088 (the body this restores), 089 (the carve-out this reverts)

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

  -- Authenticated callers (founder-initiated revoke surface at
  -- /api/template-authorizations/revoke) MUST use reason='founder_revoked'.
  -- The other 7 enum values are reserved for service-role / postgres
  -- callers: 'quota_exhausted' / 'expired' fire from the
  -- isTemplateAuthorized predicate's auto-revoke side effect; 'dsr_erasure'
  -- fires from anonymise_template_authorizations; the remaining four are
  -- reserved for operator surfaces (regulator orders, vendor TOS, AUP
  -- enforcement, classifier feedback in PR-I+1). Without this gate, an
  -- authenticated founder calling supabase-js RPC directly could stamp
  -- their OWN row with any reason in the enum (RLS scopes by auth.uid()
  -- so cross-tenant is impossible, but the founder's own audit-trail
  -- attribution would break — surfaced by PR-I multi-agent review,
  -- user-impact-reviewer FINDING 1).
  IF auth.uid() IS NOT NULL AND p_reason <> 'founder_revoked' THEN
    RAISE EXCEPTION 'revoke_template_authorization: authenticated callers must use reason=founder_revoked (got %)', p_reason
      USING ERRCODE = '42501';
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
  'not display lying rows. WORM bypass via SET LOCAL app.worm_bypass=''on'' '
  '(privilege-free; replaces the prior superuser-only replica-role GUC that '
  'raised 42501 on managed Supabase); re-armed ''off'' after the UPDATE. #4702.';

-- Down-migration 089 ends.
