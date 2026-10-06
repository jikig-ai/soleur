-- =====================================================================
-- 157. CHECK constraint on conversations.cc_cost_cap_usd — defense in
--      depth for the resumable cap (feat-cc-cap-raise-resume / #9565)
--
-- Split out from migration 156 because 156 was applied to the shared
-- dev project before this constraint was added (dev-ledger-parity arm
-- A1: an applied migration body is immutable). The column's only
-- writer is the runner's raise path, which whitelist-validates tiers;
-- this constraint is the second line of defense against a stray
-- writer persisting a non-positive ceiling.
-- =====================================================================

ALTER TABLE public.conversations
  ADD CONSTRAINT cc_cost_cap_usd_positive
    CHECK (cc_cost_cap_usd IS NULL OR cc_cost_cap_usd > 0);
