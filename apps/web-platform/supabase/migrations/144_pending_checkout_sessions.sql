-- 144_pending_checkout_sessions.sql
-- One-pending-checkout-per-user claim table for POST /api/checkout (#8918).
-- Today each POST calls stripe.checkout.sessions.create with no server-side
-- dedup: two near-simultaneous POSTs both pass the subscription_status guard
-- and produce two checkout sessions — worst case two live Stripe
-- subscriptions on one customer. The claim is an INSERT-first dedup mirroring
-- migration 030's processed_stripe_events precedent: the PK on user_id is the
-- only serialization point that survives Vercel's per-invocation concurrency
-- model.
--
-- Semantics differ from 030 by design in exactly two places:
--   * the claim is OWNED — the winner UPDATEs the row with session_id after
--     sessions.create returns (030 rows are write-once tombstones);
--   * the row is RECLAIMABLE — the route DELETES it on session completion /
--     expiry (webhook), on retrieve-status complete/expired, on a null-marker
--     older than STALE_NULL_MARKER_MS (90s, > stripe-node's 80s default
--     timeout), and on a different-tier open session after sessions.expire
--     (030 rows persist for the retention window). A daily pg_cron sweep
--     below bounds retention for never-returning users — the 030→094
--     precedent argues against deferring it.
--
-- NOT using CONCURRENTLY: the Supabase migration runner wraps each file in a
-- transaction (see migration 030's header comment). CREATE TABLE is
-- transaction-safe.
--
-- LAWFUL_BASIS: Art. 6(1)(b) contract — the pending-checkout linkage is
-- necessary to provision the subscription the user initiated. The row stores
-- user_id + Stripe session_id + target tier only; client_secret (a bearer
-- capability) is deliberately NOT persisted (Art. 5(1)(c) data-minimization —
-- reuse re-reads it from Stripe retrieve).
--
-- RLS: table is service-role-only. Service-role bypasses RLS via the
-- Authorization header, so no policies are required or desirable.

CREATE TABLE IF NOT EXISTS public.pending_checkout_sessions (
  user_id     uuid        PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  session_id  text,
  -- Domain-pinned: the four PlanTiers plus the 'legacy' sentinel the route
  -- writes for the no-targetTier path. NOT NULL because the claim insert
  -- always supplies resolvedTier; the CHECK documents that 'legacy' is a
  -- sentinel, not a tier, and forbids rows the reuse predicate can't read.
  target_tier text        NOT NULL CHECK (target_tier IN ('solo','startup','scale','enterprise','legacy')),
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Defense in depth: enable RLS with zero policies. Service-role bypasses RLS
-- via the Authorization header; anon and authenticated clients are denied by
-- default.
ALTER TABLE public.pending_checkout_sessions ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.pending_checkout_sessions IS
  'One-pending-checkout-per-user claim (#8918). Insert-first dedup: a '
  'unique-violation on user_id routes the loser into the marker-hit path '
  '(retrieve → reuse open session / reclaim complete/expired/stale). '
  'Transient lifecycle: DELETEd on checkout.session.completed / '
  'checkout.session.expired, on route reclaim paths, and by the daily '
  '24h cron sweep below; Art. 5(1)(e) retention = session lifecycle + '
  '≤24h stranded-row bound. ON DELETE CASCADE on user_id satisfies the '
  'Art. 17 erasure path. Service-role-only; no RLS policies.';

-- =====================================================================
-- Retention sweep — stranded markers (abandoned checkouts, crashed claims)
-- self-heal only on the same user's NEXT POST or webhook; a user who never
-- returns keeps a row indefinitely. Stripe embedded sessions self-expire
-- at ~24h, so nothing older is completable — a daily 24h sweep bounds
-- retention without touching anything live. Mirrors the 094 cron block
-- verbatim (unschedule guard + duplicate_object catch).
-- =====================================================================
DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'pending_checkout_sessions_retention') THEN
    PERFORM cron.unschedule('pending_checkout_sessions_retention');
  END IF;
  PERFORM cron.schedule(
    'pending_checkout_sessions_retention',
    '0 4 * * *',
    $$DELETE FROM public.pending_checkout_sessions WHERE created_at < now() - interval '24 hours'$$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron_block$;
