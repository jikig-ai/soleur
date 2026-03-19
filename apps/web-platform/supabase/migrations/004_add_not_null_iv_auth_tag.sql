-- Add NOT NULL constraints to iv and auth_tag columns.
-- Migration 002 added these as nullable, but application code
-- (agent-runner.ts, byok.ts) always provides both values.

ALTER TABLE public.api_keys
  ALTER COLUMN iv SET NOT NULL,
  ALTER COLUMN auth_tag SET NOT NULL;
