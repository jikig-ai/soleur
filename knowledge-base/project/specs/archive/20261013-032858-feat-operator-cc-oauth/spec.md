---
feature: operator-cc-oauth
date: 2026-06-02
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
closes: 4825
pr: 4824
brainstorm: knowledge-base/project/brainstorms/2026-06-02-operator-cc-subscription-auth-brainstorm.md
---

# Spec: Operator Claude Code Subscription Auth (`oauth_token` credential)

## Problem Statement

Soleur's server-side agents run on `@anthropic-ai/claude-agent-sdk`, authenticated today
exclusively by BYOK Anthropic **API keys** (`ANTHROPIC_API_KEY`). The Soleur team dogfoods
the product by driving its web-app agents to build Soleur itself — heavy agent usage that
is billed at per-token API rates and is **cost-prohibitive** at volume.

As of **June 15, 2026**, Anthropic permits funding Agent SDK usage — including *"third-party
apps that authenticate with your Claude subscription through the Agent SDK"* — from a
per-user monthly subscription credit. Routing the operator's **own** dogfooding runs onto
the operator's **own** Claude Max subscription would cut that cost, and is now sanctioned
**provided** the subscription credential funds only its owner's runs.

## Goals

- G1. Let an operator/internal account register a Claude Code **subscription OAuth token**
  as an alternative to an Anthropic API key, reusing the existing BYOK storage/lease path.
- G2. Route the operator's own server-side agent runs onto the subscription credit instead
  of API billing, with no risk of cross-tenant token use.
- G3. Make the feature impossible to operate before the policy is in force (June 15, 2026)
  or for any non-owner run.

## Non-Goals

- NG1. **Customer-facing** subscription login. Killed by CLO (Consumer-Terms violation) and
  CPO (illusory onboarding win for a non-technical ICP). Out of scope permanently for this
  feature; any future revisit is a new spec with a fresh CLO verdict.
- NG2. Delegation of an `oauth_token` credential (`byok_delegations` + oauth_token). The
  per-user/no-share constraint forbids it; explicitly disallowed.
- NG3. Operator-pooled subscription (one sub serving many users) — hard ToS violation.
- NG4. External marketing, pricing, or customer documentation of the capability.

## Functional Requirements

- **FR1.** An operator/internal account can store a `CLAUDE_CODE_OAUTH_TOKEN` credential;
  non-internal accounts cannot select the `oauth_token` type. *(CLO Guardrail 3)*
- **FR2.** At agent runtime, exactly one auth env var is injected — `ANTHROPIC_API_KEY`
  **or** `CLAUDE_CODE_OAUTH_TOKEN`, never both. The credential's `credential_type` selects
  the branch. *(Key Decision 3 — both-keys trap)*
- **FR3.** The `oauth_token` execution path fails closed before `2026-06-15T00:00:00Z`.
  *(CLO Guardrail 1)*
- **FR4.** The lease boundary rejects any attempt to use an `oauth_token` credential for a
  run whose owner ≠ the token owner, fail-closed. *(CLO Guardrail 2)*
- **FR5.** Subscription credit/rate-limit exhaustion surfaces as a distinct
  `subscription_limit` error cause with correct UI copy (not "key invalid").
- **FR6.** Token validity is checked via a subscription-auth probe (not a `/v1/models`
  API-key GET), writing the existing `is_valid` state.
- **FR7.** The entire capability is gated behind a feature flag.

## Technical Requirements

- **TR1.** Add `credential_type text not null default 'api_key' check (credential_type in
  ('api_key','oauth_token'))` to `api_keys`. No parallel table — preserve HKDF/zeroize/RLS/
  `is_valid`/`(user_id, provider)`-unique machinery. *(CTO)*
- **TR2.** `byok-lease.ts` selects and returns the credential type (e.g. `{ value, type }`),
  not a bare string; `getApiKey()` consumers updated across the 5 lease call sites.
- **TR3.** `agent-env.ts` `buildAgentEnv` takes a credential *type*, not a bare key string,
  and branches with an exhaustive `: never` rail (mirroring `mapByokLeaseCauseToErrorCode`).
  The SDK `apiKey` option in `cc-dispatcher.ts` must be omitted/undefined for OAuth runs.
- **TR4.** Effective-date gate enforced in code (not config) with a CI sentinel asserting
  it cannot be bypassed.
- **TR5.** Owner-only routing assertion at the lease boundary; `oauth_token` +
  `byok_delegations` resolves to a hard rejection.
- **TR6.** New `subscription_limit` cause threaded through the WS `key_invalid`/error path
  and mirrored to Sentry (`cq-silent-fallback-must-mirror-to-sentry`,
  `hr-observability-as-plan-quality-gate`).
- **TR7.** Migration passes `soleur:preflight`; new credential field reviewed by
  `soleur:gdpr-gate`.

## Acceptance / Verification

- Both-keys-set never bills API silently (unit test: type='oauth_token' ⇒ env has
  `CLAUDE_CODE_OAUTH_TOKEN` and NO `ANTHROPIC_API_KEY`, SDK `apiKey` undefined).
- Date gate: `oauth_token` run before 2026-06-15 throws fail-closed; CI sentinel green.
- Owner-mismatch run rejected fail-closed; delegation + oauth_token rejected.
- `subscription_limit` renders distinct UI copy and a Sentry event.
- Flag off ⇒ feature fully inert.

## References

- Anthropic support article 15036540 — Use the Claude Agent SDK with your Claude plan.
- Domain Assessments (CPO/CTO/CLO) in the brainstorm doc.
