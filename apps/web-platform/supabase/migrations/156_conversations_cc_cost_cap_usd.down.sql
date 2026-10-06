-- 156_conversations_cc_cost_cap_usd.down.sql
-- Reverts mig 156. Any in-flight raise overrides are discarded;
-- conversations revert to the env-derived caps. ORDER: roll back the
-- CODE first, or the runner's read of cc_cost_cap_usd returns the
-- column until code no longer selects it — SELECT with a missing
-- column errors (400) on the chat-case routing lookup, which falls
-- back to legacy routing on error, so the failure is degraded, not fatal.

ALTER TABLE public.conversations
  DROP COLUMN IF EXISTS cc_cost_cap_usd;
