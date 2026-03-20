-- Add columns needed by BYOK key storage and Stripe integration

-- BYOK: store iv and auth_tag separately for AES-256-GCM
alter table public.api_keys
  add column if not exists iv text,
  add column if not exists auth_tag text,
  add column if not exists updated_at timestamptz default now();

-- Unique constraint for upsert on (user_id, provider)
alter table public.api_keys
  add constraint api_keys_user_provider_unique unique (user_id, provider);

-- Stripe: store customer ID and subscription status on users
alter table public.users
  add column if not exists stripe_customer_id text,
  add column if not exists subscription_status text default 'none'
    check (subscription_status in ('none', 'active', 'cancelled', 'past_due'));
