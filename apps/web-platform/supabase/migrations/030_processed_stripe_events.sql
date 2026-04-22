-- 030_processed_stripe_events.sql
-- At-least-once Stripe webhook delivery dedup table. See issue #2772.
-- Every Stripe webhook event is inserted into this table at the top of
-- POST /api/webhooks/stripe. A unique-violation (SQLSTATE 23505) on
-- event_id indicates a replay — the handler returns 200 without
-- re-running side effects.
--
-- NOT using CONCURRENTLY: Supabase migration runner wraps each file in
-- a transaction (see migrations 025, 027, 029_conversations_repo_url
-- comments). CREATE TABLE + CREATE INDEX are transaction-safe.
--
-- Retention: rows older than Stripe's replay window (90d) are prunable.
-- A pg_cron-based sweep is tracked separately (follow-up issue) — at
-- Soleur's current event rate the table grows by <10 rows/day. Ship
-- the index on processed_at now so the eventual prune is index-backed.
--
-- RLS: table is service-role-only. Service-role bypasses RLS via the
-- Authorization header, so no policies are required or desirable.

CREATE TABLE IF NOT EXISTS public.processed_stripe_events (
  event_id     text         PRIMARY KEY,
  event_type   text         NOT NULL,
  processed_at timestamptz  NOT NULL DEFAULT now()
);

-- Defense in depth: enable RLS with zero policies. Service-role bypasses RLS
-- via the Authorization header; anon and authenticated clients are denied by
-- default. This protects against a future misconfig that exposes the table
-- through PostgREST without us noticing.
ALTER TABLE public.processed_stripe_events ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.processed_stripe_events IS
  'Dedup gate for at-least-once Stripe webhook delivery. Insert-first: '
  'a unique-violation on event_id short-circuits the handler with 200. '
  'On handler error, the row is DELETEd before the 500 so Stripe retry '
  'can re-enter. Service-role-only; no RLS policies.';

COMMENT ON COLUMN public.processed_stripe_events.event_type IS
  'Stripe event.type (e.g. customer.subscription.updated). Retained for '
  'operational visibility during retention window.';

CREATE INDEX IF NOT EXISTS idx_processed_stripe_events_processed_at
  ON public.processed_stripe_events (processed_at);
