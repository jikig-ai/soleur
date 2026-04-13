-- Prevent duplicate subscription records from concurrent checkout race.
-- Partial index: only enforces uniqueness on non-null values, so rows
-- where stripe_subscription_id IS NULL are unaffected.

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_stripe_subscription_id_unique
  ON public.users (stripe_subscription_id)
  WHERE stripe_subscription_id IS NOT NULL;
