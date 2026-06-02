-- Reverse 096_anthropic_oauth_provider.sql.
--
-- ORDER IS LOAD-BEARING: surviving 'anthropic_oauth' rows must be removed
-- BEFORE restoring the prior CHECK list, otherwise the re-ADD CONSTRAINT
-- fails validation against rows whose provider is no longer permitted.

DROP FUNCTION IF EXISTS public.store_oauth_credential(uuid, text, text, text);

DELETE FROM api_keys WHERE provider = 'anthropic_oauth';

ALTER TABLE api_keys
  DROP CONSTRAINT api_keys_provider_check,
  ADD CONSTRAINT api_keys_provider_check
  CHECK (provider IN (
    'anthropic', 'bedrock', 'vertex',
    'cloudflare', 'stripe', 'plausible', 'hetzner',
    'github', 'doppler', 'resend',
    'x', 'linkedin', 'bluesky', 'buttondown'
  ));
