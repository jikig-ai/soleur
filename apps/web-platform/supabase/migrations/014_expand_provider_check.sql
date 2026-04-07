-- Expand the provider CHECK constraint to support third-party service integrations.
-- Adds 11 new providers alongside the 3 existing LLM providers.
ALTER TABLE api_keys
  DROP CONSTRAINT api_keys_provider_check,
  ADD CONSTRAINT api_keys_provider_check
  CHECK (provider IN (
    'anthropic', 'bedrock', 'vertex',
    'cloudflare', 'stripe', 'plausible', 'hetzner',
    'github', 'doppler', 'resend',
    'x', 'linkedin', 'bluesky', 'buttondown'
  ));
