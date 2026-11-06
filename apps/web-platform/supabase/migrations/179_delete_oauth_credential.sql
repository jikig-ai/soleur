-- 179_delete_oauth_credential.sql
-- #11524: let a user erase their own stored Claude subscription token
-- (api_keys.provider = 'anthropic_oauth') without replacing it.
--
-- Service-role-only write path, sibling of store_oauth_credential (096).
-- ADR-048's write boundary routes every 'anthropic_oauth' write through a
-- SECURITY DEFINER RPC that hardcodes the provider, so a regressed caller
-- cannot reach the user's 'anthropic' api_key row (their only fallback
-- credential). Returns true when a row existed and was deleted, false when
-- there was nothing to delete (idempotent erase).
CREATE OR REPLACE FUNCTION public.delete_oauth_credential(
  p_user_id uuid
) RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH d AS (
    DELETE FROM public.api_keys
    WHERE user_id = p_user_id
      AND provider = 'anthropic_oauth'
    RETURNING 1
  )
  SELECT EXISTS (SELECT 1 FROM d);
$$;

COMMENT ON FUNCTION public.delete_oauth_credential(uuid) IS
  'Service-role-only hard delete of the caller''s Claude subscription '
  'token (provider=anthropic_oauth, hardcoded; the anthropic api_key row '
  'is unreachable). Deliberately NO operator or CC_OAUTH_ENABLED fence: a '
  'user can always erase their own stored secret, including after the '
  'kill-switch is flipped off. Called from DELETE /api/keys with the '
  'verified user id only. See #11524, ADR-048.';

REVOKE EXECUTE ON FUNCTION public.delete_oauth_credential(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.delete_oauth_credential(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.delete_oauth_credential(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.delete_oauth_credential(uuid) TO   service_role;
