-- Add billing columns for subscription lifecycle tracking.
-- These columns are NOT in the authenticated GRANT list (migration 006),
-- so they are automatically service-role-only.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS stripe_subscription_id text,
  ADD COLUMN IF NOT EXISTS current_period_end timestamptz,
  ADD COLUMN IF NOT EXISTS cancel_at_period_end boolean NOT NULL DEFAULT false;
