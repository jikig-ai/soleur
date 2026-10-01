-- Allow authenticated Web settings to store a user-owned OpenAI API key.
-- Managed ChatGPT credentials remain a separate auth-mode flow.
ALTER TABLE public.api_keys
  DROP CONSTRAINT api_keys_provider_check,
  ADD CONSTRAINT api_keys_provider_check
  CHECK (provider IN (
    'anthropic', 'openai', 'anthropic_oauth', 'bedrock', 'vertex',
    'cloudflare', 'stripe', 'plausible', 'hetzner',
    'github', 'doppler', 'resend',
    'x', 'linkedin', 'bluesky', 'buttondown'
  ));
