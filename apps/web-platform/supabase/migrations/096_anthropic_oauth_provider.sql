-- 096_anthropic_oauth_provider.sql
-- feat-operator-cc-oauth: add the 'anthropic_oauth' provider for the
-- operator Claude Code subscription OAuth token.
--
-- Two-row-by-provider model (plan § Deepen-Plan Resolution):
--   provider='anthropic'        -> the api_key (raw-REST consumers)
--   provider='anthropic_oauth'  -> the oauth_token (Agent-SDK subprocess)
-- The (user_id, provider) UNIQUE constraint enforces at-most-one-of-each
-- per user; the provider value IS the credential-type discriminator (no
-- new column). Back-compat: metadata-only CHECK re-validate; existing
-- rows are unaffected. Mirrors 014_expand_provider_check.sql.

ALTER TABLE api_keys
  DROP CONSTRAINT api_keys_provider_check,
  ADD CONSTRAINT api_keys_provider_check
  CHECK (provider IN (
    'anthropic', 'anthropic_oauth', 'bedrock', 'vertex',
    'cloudflare', 'stripe', 'plausible', 'hetzner',
    'github', 'doppler', 'resend',
    'x', 'linkedin', 'bluesky', 'buttondown'
  ));

-- Predicate-locked write path for the oauth_token credential. Mirrors
-- 033_migrate_api_key_to_v2_rpc.sql: SECURITY DEFINER, search_path pinned
-- public-first, REVOKE authenticated/anon/PUBLIC + GRANT service_role.
--
-- The provider is HARDCODED to 'anthropic_oauth' in the function body, so
-- a regressed caller cannot smuggle a different provider (e.g. overwrite
-- the raw-REST 'anthropic' row) through this function. Operator-identity
-- authorization is enforced at the /api/keys route via ADMIN_USER_IDS
-- before this RPC is reached; the service_role-only grant is the DB-level
-- defense against a direct client call.
CREATE OR REPLACE FUNCTION public.store_oauth_credential(
  p_user_id   uuid,
  p_encrypted text,
  p_iv        text,
  p_tag       text
) RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  INSERT INTO public.api_keys (
    user_id, provider, encrypted_key, iv, auth_tag,
    is_valid, key_version, updated_at
  ) VALUES (
    p_user_id, 'anthropic_oauth', p_encrypted, p_iv, p_tag,
    true, 2, NOW()
  )
  ON CONFLICT (user_id, provider) DO UPDATE
    SET encrypted_key = EXCLUDED.encrypted_key,
        iv            = EXCLUDED.iv,
        auth_tag      = EXCLUDED.auth_tag,
        is_valid      = true,
        key_version   = 2,
        updated_at    = NOW();
$$;

COMMENT ON FUNCTION public.store_oauth_credential(uuid, text, text, text) IS
  'Service-role-only write of the operator Claude Code subscription '
  'oauth_token (provider=anthropic_oauth, hardcoded). Operator-identity is '
  'enforced at the /api/keys route via ADMIN_USER_IDS. See '
  'feat-operator-cc-oauth.';

REVOKE EXECUTE ON FUNCTION public.store_oauth_credential(uuid, text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.store_oauth_credential(uuid, text, text, text) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.store_oauth_credential(uuid, text, text, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.store_oauth_credential(uuid, text, text, text) TO   service_role;
