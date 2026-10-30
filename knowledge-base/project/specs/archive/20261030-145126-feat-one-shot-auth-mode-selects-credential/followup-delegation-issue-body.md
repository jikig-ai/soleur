## What was deferred

Follow-up to #11591 (the Authentication mode setting selects the Concierge credential). A delegated lease whose grantor holds an `anthropic_oauth` (Claude subscription) row still throws `OauthDelegationForbiddenError` in `apps/web-platform/server/byok-lease.ts` `fetchAgentCredentialIntoSlot`, even when the conversation's authentication mode is `api-key` and the subscription token would never be used. Pre-existing behaviour: the date and owner gates fire as soon as an oauth row exists, before and regardless of the mode.

## Why deferred

#11591 keeps the owner-only and kill-switch gates byte-unchanged (its brief and the CTO ruling). Letting `api-key` bypass the owner gate for delegated leases changes who can run on a grantor's key and needs its own legal read of the owner-only/no-share basis (knowledge-base/legal/audits/2026-06-16-clo-re-review-cc-oauth.md).

## Re-evaluation criteria

Revisit when a delegated workspace first includes a grantor who holds a subscription row, or when #11591 has shipped and the owner reports delegation blocked while on My API key.

Mandated-By: wg-when-deferring-a-capability-create-a

Ref #11591
