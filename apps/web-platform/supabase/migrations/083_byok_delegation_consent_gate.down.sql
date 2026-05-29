-- 083_byok_delegation_consent_gate.down.sql
-- Reverse of 083_byok_delegation_consent_gate.sql.
--   1. Restore resolve_byok_key_owner to its mig 064 form (no acceptance
--      gate) so the lease path behaves exactly as it did pre-083.
--   2. Drop current_byok_side_letter_version() (introduced by 083).
--
-- Order matters: restore the resolver FIRST (while the version fn still
-- exists for any concurrent reader), then drop the version fn.

BEGIN;

-- 1. Restore the pre-gate resolver (verbatim mig 064:583 body).
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
     ORDER BY bd.created_at DESC
     LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_byok_key_owner(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_byok_key_owner(uuid, uuid)
  TO service_role;

-- 2. Drop the version source-of-truth function.
DROP FUNCTION IF EXISTS public.current_byok_side_letter_version();

COMMIT;
