-- Add onboarding state columns to users table
-- Nullable by design: NULL means "not yet completed/dismissed"

ALTER TABLE public.users
  ADD COLUMN onboarding_completed_at timestamptz,
  ADD COLUMN pwa_banner_dismissed_at timestamptz;
