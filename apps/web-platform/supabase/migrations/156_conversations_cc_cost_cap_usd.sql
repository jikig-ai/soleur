-- =====================================================================
-- 156. conversations.cc_cost_cap_usd — per-conversation Concierge cost
--      cap override (feat-cc-cap-raise-resume / #9565)
--
-- The Concierge cc runner enforces a per-conversation USD ceiling.
-- Before this migration the cap was env-derived and unchangeable: a
-- BYOK conversation that breached it had its SDK Query torn down and
-- the only advice was "start a new conversation", which discarded the
-- accumulated context. The resumable-cap flow (#9565) lets the user
-- pick a raise tier in chat; the chosen ceiling is written here so it
-- survives idle reap, server restart, and reload — the ws-handler
-- seeds it back into the runner's ActiveQuery on the next turn.
--
-- LAWFUL_BASIS: GDPR Art. 6(1)(b) — contract performance with the data
--   subject: a user-chosen spend ceiling applied to their own
--   conversation. The column is a non-PII numeric; it is not
--   special-category data under Art. 9.
-- Retention: dies with the conversation row (account/workspace deletion
--   cascades already cover conversations — gdpr-gate GDPR-Art-17 needs
--   no new rule). NULL means "no override; env-derived cap applies".
--
-- Managed (oauth_token) sessions never read or write this column — the
-- per-conversation cap is not enforced for them at all.
-- =====================================================================

-- Cross-file precondition: conversations must exist (created well
-- before this migration).
DO $$ BEGIN
  IF to_regclass('public.conversations') IS NULL THEN
    RAISE EXCEPTION 'Precondition failed: public.conversations must exist before 156';
  END IF;
END $$;

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS cc_cost_cap_usd numeric,
  ADD CONSTRAINT cc_cost_cap_usd_positive
    CHECK (cc_cost_cap_usd IS NULL OR cc_cost_cap_usd > 0);

COMMENT ON COLUMN public.conversations.cc_cost_cap_usd IS
  'feat-cc-cap-raise-resume (#9565) — user-chosen per-conversation USD '
  'cost cap override for the Concierge cc runner. NULL = env-derived '
  'cap. Written by the in-chat raise affordance (BYOK only).';
