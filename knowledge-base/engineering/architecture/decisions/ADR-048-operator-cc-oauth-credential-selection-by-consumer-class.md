---
title: Operator Claude Code subscription credential — selection by consumer class + structural REST/SDK boundary
status: accepted
date: 2026-06-02
related: [4825, 4824]
related_adrs: [ADR-042]
related_plans:
  - knowledge-base/project/plans/archive/20261013-032858-2026-06-02-feat-operator-cc-oauth-credential-plan.md
brand_survival_threshold: single-user incident
---

# ADR-048: Operator CC OAuth credential — selection by consumer class + structural REST/SDK boundary

## Status

**Accepted** (2026-06-02, PR #4824; #4825). CLO-gated: the credential is
operator-internal only and the `oauth_token` execution path is permitted only
on/after 2026-06-15 (Anthropic Agent-SDK-credit policy: per-user, no pooling).

## Context

Soleur's server-side agents authenticate to Anthropic exclusively via BYOK
**API keys** (`ANTHROPIC_API_KEY`), billed per token. Anthropic now permits
funding Agent-SDK usage from a per-user Claude **subscription** OAuth token
(`CLAUDE_CODE_OAUTH_TOKEN`, from `claude setup-token`), so the operator can run
its own dogfooding on its own subscription. Two facts forced the data-model and
boundary decisions:

1. **Six credential consumers, two auth transports.** Four consumers send the
   credential to Anthropic's **raw REST** API via `x-api-key`
   (`domain-router.ts` classify, `agent-on-spawn-requested.ts`, two stubs) — an
   OAuth token CANNOT authenticate those. Only the two **Agent-SDK** consumers
   (`agent-runner.ts startAgentSession`, `cc-dispatcher.ts`) can carry an OAuth
   token (it reaches the CLI subprocess env as `CLAUDE_CODE_OAUTH_TOKEN`). So
   the operator needs BOTH credentials simultaneously, selected by consumer
   class.

2. **Injecting both auth vars silently bills the API account** while the
   operator believes they are on the subscription (the "both-keys trap", FR2).

## Decision

**Two rows by provider — no `credential_type` column.**

- `provider='anthropic'` row = the api_key (raw-REST consumers).
- `provider='anthropic_oauth'` row = the oauth_token (Agent-SDK path).
- The existing `(user_id, provider)` UNIQUE constraint enforces at-most-one of
  each per user for free. **The provider value IS the credential-type
  discriminator.** Rejected: a `credential_type` column on the single
  `(user_id,'anthropic')` row (cannot hold both secrets) and a parallel
  oauth-column trio (partial-NULL states, doubled secret surface).

**The REST/SDK boundary is STRUCTURAL, not a runtime check.** `byok-lease.ts`
exposes two accessors instead of the former `getApiKey()`:

- `getRestApiKey()` queries ONLY `provider='anthropic'` → physically cannot
  return an oauth token (it lives in a row this query never reads). The
  oauth→`x-api-key` leak is impossible by construction.
- `getAgentCredential()` prefers `provider='anthropic_oauth'` (gated), falls
  back to `'anthropic'`; returns `{ value, scheme }`. `buildAgentEnv` branches
  on `scheme` and injects EXACTLY ONE auth var (non-selected var deleted;
  exhaustive `: never` rail) — closing the both-keys trap at a single site.

**All policy gates fire on the oauth read only**, centralized in
`getAgentCredential`'s oauth branch (the sole reader of the `anthropic_oauth`
row): kill-switch (`CC_OAUTH_ENABLED`, default off), date gate
(`CC_OAUTH_EFFECTIVE_DATE = 2026-06-15`, throws `OauthNotYetPermittedError`),
owner gate (`delegationId == null && keyOwnerUserId === workspaceContextUserId`,
throws `OauthDelegationForbiddenError`). All fail-closed — never a silent
api_key fallback.

**Write path** goes through a service_role-only `SECURITY DEFINER` RPC
(`store_oauth_credential`, migration 096) with the provider hardcoded to
`'anthropic_oauth'` (a regressed caller cannot overwrite the raw-REST row); the
authoritative operator-authorization fence is the `/api/keys` route check
(`ADMIN_USER_IDS` + kill-switch), not UI hiding.

## Consequences

- The structural boundary means a future raw-REST consumer that mistakenly
  calls `getAgentCredential()` is the only way to leak oauth to REST — caught
  by the consumer-class routing convention (4 consumers enumerated in the plan)
  and the architecture review, not by a runtime guard that could regress.
- `subscription_limit` (FR5) is pre-wired end-to-end (cause → `WSErrorCode` →
  non-retryable UI) but has no producer until the Phase 5 SDK credit-signal
  classifier lands ("defer to first real hit").
- Operator-only blast radius; the `oauth_token` gate-throws surface as
  fail-closed run failures captured by the runner's generic Sentry path.

## Addendum — 2026-10-29 (#11086)

A stored `anthropic_oauth` value of a class the bundled CLI is measured to drop (an API-key shape, an embedded space or tab, or blank) is refused at the lease with the fail-closed cause `oauth_unusable`, mapped to `key_invalid`; the read of an EXISTING dropped `anthropic_oauth` row is never a silent `api_key` fallback, which would change the billing basis without telling anyone (the documented fallback when NO oauth row exists is unchanged). The write boundary (`POST /api/keys`, `credential_type=oauth_token`) validates the allowlist shape `sk-ant-oat<NN>-<url-safe tail>` before encryption. Rationale and the friendly-error half: ADR-308.

## Addendum — 2026-10-30 (#11524)

The operator-held `anthropic_oauth` row can now be removed by its owner, with no replacement. Removal is the user's explicit act through a second service-role-only `SECURITY DEFINER` RPC, `delete_oauth_credential(p_user_id)` (migration 179, sibling of `store_oauth_credential`), invoked by `DELETE /api/keys`; the provider is hardcoded in the function, so the RPC-only write boundary is kept and the `anthropic` row cannot be reached. There is no operator or kill-switch fence on erase. The documented fallback when NO oauth row exists (the owner's `anthropic` api_key) is what makes the Settings confirmation's billing sentence true after removal. Removing the owner's token also returns delegated leases to the owner's API key: with the row gone a delegated or owner-mismatched lease no longer throws `OauthDelegationForbiddenError` and falls through to the owner's `anthropic` key, the baseline pre-oauth delegation behavior (pinned by a lease test). The operator-only POST fence is unchanged. Rationale: ADR-308 amendment of the same date.
