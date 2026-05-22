-- =====================================================================
-- 063_post_workspace_rpc_repair.down.sql
-- =====================================================================
--
-- Restores the pre-063 RPC body (verbatim copy from 051:256-295) and
-- REVOKEs the additive is_workspace_member grant.
--
-- IMPORTANT CAVEAT: applying this down migration WHILE the migration-059
-- CHECK constraint `scope_grants_workspace_id_check` is still in place
-- leaves the database in a knowingly-broken state — any subsequent call
-- to `grant_action_class` will fail with 23514 because the restored RPC
-- body does NOT populate `workspace_id`. This is acceptable for
-- rollback semantics (the operator is reverting toward the broken state
-- that prompted issue #4342); the up-migration is the canonical path
-- forward. Do NOT run this in production except as a controlled
-- regression test.
-- =====================================================================

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
  IF p_tier NOT IN ('auto', 'draft_one_click', 'approve_every_time', 'auto_with_digest') THEN
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

REVOKE EXECUTE ON FUNCTION public.is_workspace_member(uuid, uuid) FROM service_role;
