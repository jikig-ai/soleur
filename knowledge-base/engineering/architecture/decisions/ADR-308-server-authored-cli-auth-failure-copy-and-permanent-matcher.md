---
title: Server-authored copy for the Claude CLI sign-in failure, keyed by match kind and credential scheme, on a permanent matcher
status: active
date: 2026-10-29
issue: 11086
supersedes: null
related: [10455, 11085]
related_adrs: [ADR-048]
---

# ADR-308: Server-authored copy for the Claude CLI sign-in failure, keyed by match kind and credential scheme, on a permanent matcher

## Context

When the bundled Claude CLI has no usable credential it prints "Not logged in · Please run /login" as an ordinary assistant reply. Both runners streamed and persisted that raw line as the answer, with no recovery path (#11086). The classifier that recognises the line (`matchAgentAuthFailure`) lived in the temporary diagnostic module that #11085 deletes, so any product code calling it would have been removed with the diagnostic.

## Decision

- **Copy is server-authored and closed.** A table keyed by the matcher's `match_kind` (`not_logged_in`, `invalid_api_key`, `oauth_token_revoked`, `session_expired`, `structured`, plus the lease-time `oauth_unusable`) and the credential scheme (`api_key` for tenants, `oauth_token` for the operator, a neutral cell for an unknown scheme) produces the text. No raw CLI text crosses to the client or is persisted for a rewritten reply. Tenant cells name only the Anthropic API key; subscription-token wording appears only for the scheme only the operator can hold.
- **The matcher is permanent product code.** `matchAgentAuthFailure`, its forgery gate and `AgentAuthMatchKind` live in `server/agent-auth-match.ts`; the diagnostic re-exports them. `agent-auth-user-message.ts` imports the matcher from there, and an import-boundary test keeps both permanent modules free of the diagnostic, the probe, Sentry and observability. The #11085 removal checklist keeps them and `CLI_AUTH_FAILURE_REPLIES`.
- **The matcher runs on the raw message first, and the rewrite never mutates it.** The cc runner consumes a Query wrapped by the diagnostic tap (observed before the consumer sees it); the legacy runner calls the probe inline at the top of its loop. The rewrite builds a new content array and only replaces a message whose content is a single text block.
- **Recovery rides the existing `key_invalid` error code**, not a new one, with an optional closed-enum `credentialScheme` field so the client can pick the card title and action by scheme. A frame without the field renders exactly as before. The frame is sent once per turn, only for terminal kinds, and only after `stream_end`: the client tears the stream down on `key_invalid`, so an earlier frame would turn the friendly bubble into an interrupted chip. `session_expired` is bubble-only. One builder produces the frame at every site (both runners, the cc dispatch catch, the legacy error catches, the ws-handler catch).
- **A terminal failure makes the next cc dispatch cold.** A warm Query keeps the credential it was built with, so after the user fixes Settings the next dispatch tears it down with the `auth-failed` close reason (not at the result, so a message queued during the failing turn is never dropped; the persisted session id survives and resumes) and re-leases. The legacy runner builds a fresh query per turn, so it needs no eviction. This is a deliberate deviation from CTO ruling F12's wording ("after the result is processed"), which would have dropped a queued message.
- **Surfaces.** The support persona's SSE client treats any `error` frame as a canned-fallback trigger, so the recovery frame is not sent for it (it keeps the friendly bubble). A turn that ends in a terminal sign-in failure is not announced as finished (no push or inbox card).
- **History is forward-only.** Old persisted raw lines stay as they are; a render-time substitution would add a second consumer of the matcher.

Rejected: a new WebSocket error code (widens the union for no gain), a client-side rewrite (a second matcher and raw text on the wire), rewriting history, a new `match_kind` for newly measured wordings (they stay `structured`; widening the tag enum enlarges what #11085 deletes), and a subscription-to-API fallback (silently changes the billing basis).

## Consequences

- The friendly text depends on the matcher recognising the reply; a CLI wording change that the structured `authentication_failed` arm does not cover leaves the raw line visible. The wording list is re-derived on every SDK bump (the contract test and the wording comment in `claude-error-signatures.ts`).
- A tab loaded before the deploy parses the error frame with the previous strict schema and drops a frame carrying `credentialScheme`; accepted for the rollout window (the persisted bubble still shows).
- Open follow-ups: the operator cannot remove a dead stored token in-product (#11524); the chat state after the recovery frame is the existing behavior (#11525).
  - Resolved (#11524 and #11525): see Amendment — 2026-10-30 below. The bullet above is the original record and is left as written.

## Amendment — 2026-10-30

Resolves the two follow-ups the Consequences named. Rulings are in `knowledge-base/project/specs/feat-one-shot-11524-11525-oauth-remove-key-invalid-chat/decision-challenges.md`.

- **Removing a stored subscription token (#11524) is an explicit hard delete through a service-role RPC.** `DELETE /api/keys` with the exact body `{ credential_type: "oauth_token" }` calls `delete_oauth_credential(p_user_id)` (migration 179), which hardcodes `provider = 'anthropic_oauth'` so the user's `anthropic` API key (their only fallback) is unreachable; this keeps ADR-048's RPC-only write boundary. There is deliberately no operator or `CC_OAUTH_ENABLED` fence (a user can always erase their own stored secret, including after the kill-switch is off) and no soft delete ("removed" must be true). The removal creates, copies and converts nothing, so the billing-basis change stays an explicit user decision: Settings names the consequence (API key, none, or unchanged because the token is not in effect) before the user confirms. Audit is a pino line emitted at warn (the Vector drain ships only level 40 and above) plus a Sentry breadcrumb (op `oauth-credential-removed`, never the value). No cross-host warm-Query eviction: state is process-local, so a warm session keeps the token until it ends (tracked in #11596).
- **Chat state after the recovery frame (#11525) is derived, not stored.** `key_invalid` and `byok_key_missing` still tear the socket down (a reconnect storm is the alternative). The client derives a blocked state from `lastError.code`: the composer is disabled, `sendMessage` refuses before any optimistic message is shown, and an explicit **Reconnect** re-binds the existing conversation (resume, with a one-shot start fallback) instead of opening a duplicate. The frame stays user-scoped (the credential is account-global; one live socket per user), the Settings link opens in a new tab so the chat survives, and the last unanswered user message is flagged in memory. Cross-tab clearing and one-click resend are deferred (#11597, #11595).
