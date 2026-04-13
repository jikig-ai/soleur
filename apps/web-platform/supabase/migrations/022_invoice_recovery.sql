-- Expand subscription_status CHECK constraint to include 'unpaid'.
-- Needed for invoice history + failed payment recovery (#1079).
alter table public.users
  drop constraint if exists users_subscription_status_check;

alter table public.users
  add constraint users_subscription_status_check
  check (subscription_status in ('none', 'active', 'cancelled', 'past_due', 'unpaid'));
