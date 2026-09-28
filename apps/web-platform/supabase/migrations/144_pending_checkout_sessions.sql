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
--   * the row is RECLAIMABLE — the route DELETES it on session completion
--     (webhook), on retrieve-status complete/expired, on a ≥60s null-marker
--     (crashed-claim residue), and on a different-tier open session after
--     sessions.expire (030 rows persist for the retention window).
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
  target_tier text,
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
  'Transient lifecycle: DELETEd on checkout.session.completed and on '
  'reclaim; Art. 5(1)(e) retention = session lifecycle, no long-term '
  'retention. ON DELETE CASCADE on user_id satisfies the Art. 17 erasure '
  'path. Service-role-only; no RLS policies.';
