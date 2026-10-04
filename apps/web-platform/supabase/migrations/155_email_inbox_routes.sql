-- =====================================================================
-- 155. email_inbox_routes — inbound recipient address → (workspace, owner)
--      (ADR-269 / #9458)
--
-- The tenancy key for email-triage ingress. email-on-received resolves the
-- webhook's normalized recipient addresses against this table and claims the
-- row under the matched route's (workspace_id, owner_user_id); an address that
-- matches no route — and every event without recipients — keeps using the
-- env-pinned EMAIL_TRIAGE_OWNER_USER_ID. The table ships EMPTY: production
-- behavior is unchanged until a route exists, and no non-operator route may be
-- created until the hard preconditions in ADR-269 / #9459 are met (workspace-
-- scoped claim_key, quarantine instead of operator fallback, multi-route
-- fan-out).
--
-- LAWFUL_BASIS: legitimate interest (Art. 6(1)(f)), see article-30-register
--   PA-27. Rows are service configuration (addresses + workspace/owner ids);
--   they hold no correspondent data and no message content.
-- Retention: a route lives while configured. There is no purge job: rows are
--   removed by the workspace-member cascade below.
--
-- Access: service-role only. RLS is enabled with NO policies and every
-- privilege is revoked from anon/authenticated, so no client session can read
-- or write routes (a route is a tenancy boundary: a mis-keyed row hands one
-- tenant's mail to another).
--
-- The composite FK makes the route's owner a MEMBER of its workspace at write
-- time. `role = 'owner'` cannot be expressed in a FK and stays an application
-- check in resolveInboundRoute. ON DELETE CASCADE (gdpr-gate GDPR-Art-17): a
-- route is configuration, not statutory evidence, so it must not block account
-- or workspace deletion. Consequence recorded in ADR-269: deleting a route
-- re-routes that address to the operator fallback — a hard #9459 precondition
-- before any non-operator route exists.
--
-- The address CHECK is deliberately LOOSE (shape only). The strict validator
-- is normalizeInboundAddress in server/email-triage/events.ts, so the two
-- cannot drift: a change to the address rules is a one-place edit.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.email_inbox_routes (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  address       text        NOT NULL,
  workspace_id  uuid        NOT NULL,
  owner_user_id uuid        NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT email_inbox_routes_owner_member_fk
    FOREIGN KEY (workspace_id, owner_user_id)
    REFERENCES public.workspace_members (workspace_id, user_id)
    ON DELETE CASCADE,
  CONSTRAINT email_inbox_routes_address_shape
    CHECK (
      address = lower(address)
      AND char_length(address) <= 320
      AND address LIKE '%_@_%'
      AND address NOT LIKE '%@%@%'
    )
);

COMMENT ON TABLE public.email_inbox_routes IS
  'Inbound recipient address -> (workspace, owner) routing for email triage '
  '(ADR-269). Service-role only; ships empty. Unmatched addresses and events '
  'without recipients fall back to EMAIL_TRIAGE_OWNER_USER_ID.';

CREATE UNIQUE INDEX IF NOT EXISTS email_inbox_routes_address_key
  ON public.email_inbox_routes (address);

ALTER TABLE public.email_inbox_routes ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.email_inbox_routes FROM anon, authenticated;
