-- Add NOT NULL constraints to iv and auth_tag columns.
-- These columns were added as nullable in migration 002 but application code
-- (agent-runner.ts, byok.ts) assumes they are always present.
-- The upsert in app/api/keys/route.ts always provides both values,
-- so no null rows should exist in production.
--
-- Locking: ALTER COLUMN SET NOT NULL acquires ACCESS EXCLUSIVE lock.
-- The api_keys table is small (one row per user per provider),
-- so lock duration is negligible.
--
-- Idempotency: SET NOT NULL on a column that already has the constraint
-- is a silent no-op in PostgreSQL. No conditional guard needed.

-- Safety check: fail if any null rows exist (should never happen,
-- but protects against silent data loss).
-- This runs in the same transaction as the ALTER below (Supabase wraps
-- each migration file in a single transaction), so no TOCTOU risk.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.api_keys
    WHERE iv IS NULL OR auth_tag IS NULL
  ) THEN
    RAISE EXCEPTION 'Cannot add NOT NULL constraints: null iv or auth_tag rows exist in api_keys';
  END IF;
END $$;

ALTER TABLE public.api_keys
  ALTER COLUMN iv SET NOT NULL,
  ALTER COLUMN auth_tag SET NOT NULL;
