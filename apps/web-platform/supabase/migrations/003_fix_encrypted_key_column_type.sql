-- Fix encrypted_key column type: bytea -> text
-- PostgREST returns bytea in hex format (\x...) but the app
-- reads/writes base64 strings. Align with iv and auth_tag (both text).
--
-- The stored bytea contains the ASCII bytes of the base64 string
-- (PostgREST interpreted the base64 text as raw bytes on write).
-- convert_from extracts the original base64 text. This conversion is
-- academic since all rows are invalidated below, but it preserves
-- data correctly in case invalidation is ever removed.

ALTER TABLE public.api_keys
  ALTER COLUMN encrypted_key TYPE text
  USING convert_from(encrypted_key, 'UTF8');

-- Invalidate existing keys — they were likely corrupted by the
-- bytea/base64 mismatch. Users will be prompted to re-save.
-- Also reset validated_at to prevent stale validation timestamps.
UPDATE public.api_keys SET is_valid = false, validated_at = NULL;
