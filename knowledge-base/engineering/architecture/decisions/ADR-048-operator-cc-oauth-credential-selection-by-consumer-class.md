---
title: Operator Claude Code subscription credential — selection by consumer class + structural REST/SDK boundary
status: accepted
date: 2026-06-02
related: [4825, 4824, 11591]
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

## Addendum — 2026-10-30 (#11591): selection by the conversation binding's auth mode

For the Agent-SDK consumer class the credential is now also chosen by the conversation's engine-binding auth mode (`agent_engine_runs.auth_mode`, immutable per ADR-233), read lazily through an injected resolver. The subscription token (`anthropic_oauth`) is leased only when the kill-switch is on, a row exists, the date gate and the owner gate pass (all unchanged and evaluated first) AND the mode is exactly `managed`. Mode `api-key` selects the `anthropic` row and never decrypts the subscription row, so an unusable stored token no longer blocks an owner who chose their API key. An unreadable or invalid mode, and a lease with no resolver while a subscription row exists, fail closed with `fetch_failed` (one `auth-mode-unresolved` event carrying a closed reason). `api-key` with no saved API key is `MissingByokKeyError`; it never falls back to the subscription token, because an explicit choice is a consent boundary (the "no silent api_key fallback" rule above is preserved: this is a choice, not a fallback). Callers that only lease `getRestApiKey` pass `{ restOnly: true }`; the resolver argument of `resolveKeyOwnerThenLease` is required by type.

Source of truth is the binding, so a dropdown change applies to NEW conversations. Two documented divergences between the lease and the auth-failure diagnostic's `auth_mode` label (the label reports `unbound` for a conversation with no run): no run + `legacy` (lease: `managed`) and no run + `pending` (lease: fails closed). One exception to "an `api-key` owner is never served the subscription": a conversation created before engine binding existed behaves as `managed`. The auto-sync and support conversations are bound before dispatch so they follow the setting.

Alternatives rejected: the live workspace default (can disagree with the binding the egress policy and disclosure were recorded against, and flips mid-conversation); pre-resolving the mode on every lease (an extra read for every user to serve one); the lease reading the workspace itself (it holds no workspace id); a new `ByokLeaseError` cause (touches the exhaustive switch, the WS code and the UI for no gain); failing open to `managed` (would serve the declined account exactly when the system cannot say so). Out of scope, tracked in #11594: a delegated lease whose grantor holds a subscription row is still refused by the owner gate even under `api-key`.

Review amendments (2026-10-30, same PR; CTO rulings recorded in the PR's decision-challenges file):

- **Whose setting.** The mode is the workspace OWNER's setting (`set_workspace_default_engine` is owner-only), snapshotted into every member's conversation in that workspace, and it selects among that member's OWN credentials. No principal's credential is ever used by another (the delegation gate is untouched; #11594). Copy tuning for non-owner viewers is tracked in #11599.
- **"Immutable binding" is scoped to claude-code bindings.** A future engine that rewrites `auth_mode` on existing conversations (draft PR #9051, Codex) must ratify its own semantics in its own ADR; this addendum does not assert an invariant that PR intends to break.
- **Support thread.** The support conversation is sticky (the newest `kind=support` row is reused). Migration 141 backfilled every pre-binding unbound conversation to `legacy`, so existing support threads are `legacy`, not `pending`. A sticky `pending` or `legacy` support row is bound at its next message (the bind RPC accepts either when no run exists), snapshotting the then-current default; a `bound` row keeps its snapshot until "start a new conversation". The legacy-resolves-to-`managed` exception therefore no longer covers support threads, except when the bind of a `legacy` row fails: that refuses the message (503 path) rather than serving `managed`. A `bound` support row is re-checked for its engine on every message, as `ws-handler` does on resume.
- **Failure surface.** A mode that cannot be resolved throws `ByokLeaseError("fetch_failed")` (reason carried on the error). The client renders it with the `key_invalid` copy ("Update key") until the recovery-copy follow-up (#11599) gives it its own copy; the lease event and the generic call-site event both reach Sentry (accepted noise, bounded by the subscription-holder population). Deterministic reasons (`unbound`, `invalid_value`, `no_resolver`) are not retried by auto-sync.
- **Mint budget.** The mode read reuses the tenant client the oauth-row read has just obtained, so a cold subscription-holder lease costs one extra `is_jti_denied` RPC and one to two indexed reads; the 60/hour `precheck_jwt_mint` ceiling is not newly spent (cache hit).
- **Engine check at bind sites.** The auto-sync and support binds run `assertLegacyEngineBinding` on the returned run, as `ws-handler` does, so a non-Claude workspace default cannot bind a conversation the Claude runner executes.
- **Settings PUT.** An engine-only PUT preserves the stored auth mode (the RPC would otherwise reset it to `managed`).
