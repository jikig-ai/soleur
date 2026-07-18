-- 130_authorize_template_grant_ownership_guard.sql (#6336)
--
-- authorize_template(p_template_hash, p_action_class, p_grant_id) is SECURITY
-- DEFINER, so it bypasses base-table RLS — any tenancy guarantee must be
-- re-asserted in the body, it is not inherited (learning
-- security-issues/2026-07-09-security-definer-rpc-bypasses-jti-rls-and-new-user-fk-table-trips-two-dsar-gates).
-- The original body (053_template_authorizations.sql:222-303) inserts
-- `grant_id = p_grant_id` verbatim with NO check that p_grant_id belongs to the
-- calling founder — only the FK `grant_id → scope_grants(id)` enforces existence,
-- not ownership. So a founder can mint a template_authorizations row (their own
-- founder_id) backed by ANOTHER founder's scope_grant, corrupting the
-- GDPR Art. 5(2) integrity/provenance of the WORM consent ledger.
--
-- Fix: before the INSERT, RAISE 42501 if p_grant_id references a scope_grants
-- row not owned by the caller (v_founder_id = auth.uid()). CREATE OR REPLACE
-- (NOT DROP+CREATE — a DROP would sever the `authenticated` EXECUTE grant and
-- break the legitimate first-send-IS-authorization path). The
-- `SET search_path = public, pg_temp` pin is preserved
-- (cq-pg-security-definer-search-path-pin-pg-temp). Body is otherwise the exact
-- mig-053 definition; REVOKE/GRANT re-stated verbatim; COMMENT updated for #6336.
--
-- No top-level BEGIN/COMMIT (run-migrations.sh --single-transaction).
--
-- Ref #6336; found by #6307 (RLS/authz-fuzz harness Phase 7); ADR-111.

CREATE OR REPLACE FUNCTION public.authorize_template(
  p_template_hash text,
  p_action_class  text,
  p_grant_id      uuid
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_founder_id uuid := auth.uid();
  v_existing_id uuid;
  v_new_id uuid;
BEGIN
  IF v_founder_id IS NULL THEN
    RAISE EXCEPTION 'authorize_template: authenticated session required'
      USING ERRCODE = '42501';
  END IF;

  -- Input validation (defense-in-depth alongside the column CHECKs).
  IF p_template_hash IS NULL OR length(p_template_hash) < 1 OR length(p_template_hash) > 128 THEN
    RAISE EXCEPTION 'authorize_template: invalid template_hash length'
      USING ERRCODE = '22023';
  END IF;
  IF p_action_class IS NULL OR p_action_class !~ '^[a-z][a-z0-9_.]*$' OR length(p_action_class) > 64 THEN
    RAISE EXCEPTION 'authorize_template: invalid action_class'
      USING ERRCODE = '22023';
  END IF;

  -- #6336 ownership guard: p_grant_id is a caller-supplied resource reference;
  -- the SECURITY DEFINER context bypasses scope_grants RLS, so re-derive
  -- ownership here. NULL short-circuits (the grant_id NOT NULL FK rejects a NULL
  -- insert unchanged). A cross-founder grant_id is a 42501 (matches the harness
  -- classifier + the authenticated-session guard above).
  IF p_grant_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.scope_grants
        WHERE id = p_grant_id AND founder_id = v_founder_id
     ) THEN
    RAISE EXCEPTION 'authorize_template: grant not owned by caller'
      USING ERRCODE = '42501';
  END IF;

  BEGIN
    INSERT INTO public.template_authorizations (
      founder_id, template_hash, action_class, grant_id
    )
    VALUES (
      v_founder_id, p_template_hash, p_action_class, p_grant_id
    )
    RETURNING id INTO v_new_id;
    RETURN v_new_id;
  EXCEPTION
    WHEN unique_violation THEN
      -- 23505 against template_authorizations_active_unique. Concurrent
      -- first-send raced us; return the winner's id. Idempotent first-
      -- writer-wins (learning 2026-05-03).
      --
      -- NOTE: do NOT filter by `revoked_at IS NULL` here. The partial
      -- UNIQUE only covers active rows, so the 23505 implies an active
      -- winner existed at INSERT time — but read-committed semantics let
      -- a concurrent revoke land between the failed INSERT and this
      -- SELECT, in which case `WHERE revoked_at IS NULL` would return
      -- zero rows and force a false re-raise. Ordering by authorized_at
      -- DESC LIMIT 1 returns the most-recent row regardless of state;
      -- the caller (send/route.ts first_send branch) treats the returned
      -- id as the authorization id and proceeds to writeActionSend. If
      -- the row was just revoked, the next predicate call will detect
      -- the revocation and surface the appropriate DenyReason. Surfaced
      -- by PR-I multi-agent review (data-migration-expert F1).
      SELECT id INTO v_existing_id
        FROM public.template_authorizations
       WHERE founder_id = v_founder_id
         AND template_hash = p_template_hash
       ORDER BY authorized_at DESC
       LIMIT 1;
      IF v_existing_id IS NULL THEN
        -- Shouldn't happen — the 23505 by definition implies a row
        -- exists. Re-raise rather than fabricate.
        RAISE;
      END IF;
      RETURN v_existing_id;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.authorize_template(text, text, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.authorize_template(text, text, uuid)
  TO authenticated;

COMMENT ON FUNCTION public.authorize_template(text, text, uuid) IS
  'First-send-IS-authorization writer. INSERTs a template_authorizations '
  'row for the calling founder. Idempotent on 23505 partial-UNIQUE '
  'conflict (returns existing active row''s id). Validates p_grant_id '
  'ownership (42501 if the grant is not owned by the caller — #6336). '
  'Art. 7(3) "specific" + "informed" consent — call site is the founder''s Send click.';
