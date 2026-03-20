-- Add key_version column for BYOK HKDF migration tracking.
-- v1 = legacy raw BYOK_ENCRYPTION_KEY (no HKDF)
-- v2 = HKDF-derived per-user key

ALTER TABLE public.api_keys ADD COLUMN key_version integer NOT NULL DEFAULT 1;
