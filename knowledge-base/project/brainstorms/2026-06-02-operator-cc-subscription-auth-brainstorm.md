---
date: 2026-06-02
topic: operator-cc-subscription-auth
status: brainstorm-complete
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
branch: feat-operator-cc-oauth
pr: 4824
---

# Brainstorm: Operator Claude Code Subscription Auth (CC login)

## What We're Building

A second **credential type** for Soleur's server-side agent execution: a Claude Code
**subscription OAuth token** (`CLAUDE_CODE_OAUTH_TOKEN`, from `claude setup-token`),
alongside the existing BYOK Anthropic **API key** (`ANTHROPIC_API_KEY`).

**Scope is narrowed to operator self-use only.** The Soleur operator (Jikigai) funds
its **own** agent dogfooding runs — building Soleur by running Soleur's web-app agents —
on its **own** Claude Max subscription, because paying per-token API rates for heavy
agent dev work is expensive. The credential type is gated to operator/internal accounts;
each subscription token funds **only its owner's** runs. **Not offered to customers.**

## Why This Approach

The request started as "offer CC login to Soleur's users in addition to API key."
The triad killed that scope (see Domain Assessments): customer-facing subscription auth
is a Consumer-Terms violation today, and the onboarding win is illusory for a
non-technical ICP (`claude setup-token` needs a terminal + CLI install).

The pivot to **operator self-use** changes the legal analysis decisively, and an
**imminent Anthropic policy change** makes it viable:

- **Until June 15, 2026:** subscription/OAuth tokens are Claude-Code-and-claude.ai only;
  the Agent SDK requires an API key. Operator self-use is **prohibited** today.
- **From June 15, 2026:** Pro/Max/Team/Enterprise plans receive a monthly **Agent SDK
  credit** that explicitly covers *"Third-party apps that authenticate with your Claude
  subscription through the Agent SDK"*; that usage *"no longer counts toward your Claude
  plan's usage limits."* Credits are **per-user** — *"can't be pooled, transferred, or
  shared across the organization."*
  ([support article 15036540](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan))

Soleur's web app runs on `@anthropic-ai/claude-agent-sdk`, so it **is** "a third-party
app authenticating with your subscription through the Agent SDK." Funding the operator's
**own** runs on the operator's **own** subscription satisfies the per-user constraint by
construction. CLO verdict: **permitted-with-guardrails on/after June 15, 2026.**

The build is small because it reuses the entire BYOK lease/encryption/RLS machinery; the
only genuinely new work is a credential-type branch plus two hard-block guardrails.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Operator self-use only**; not customer-facing | Customer-facing = ToS-prohibited (credential sharing / pooling) + illusory onboarding win for non-technical ICP |
| 2 | Add a `credential_type` column to `api_keys` (`'api_key' \| 'oauth_token'`), not a parallel table | Reuses HKDF/zeroize/RLS/`is_valid`/lease machinery untouched; cheapest correct surface (CTO) |
| 3 | `agent-env.ts` sets **exactly one** of `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN` (mutually exclusive) | **Both-keys trap:** if both are set, `ANTHROPIC_API_KEY` silently wins → user pays API rates believing they're on subscription. Must be an exhaustive `: never`-railed branch |
| 4 | **Hard-block effective-date gate**: `oauth_token` path refuses to run before `2026-06-15T00:00:00Z` | Pre-June-15 the conduct is prohibited; gate makes a merge-before-June-15 defensible because it cannot execute. CI sentinel asserts it (CLO Guardrail 1). **[SUPERSEDED 2026-06-16 — Anthropic paused the June-15 change; this is now a spent gate, not a legal floor. See Re-review section below.]** |
| 5 | **Hard-block owner-only routing**: reject routing an `oauth_token` credential to any run whose owner ≠ the token's owner | Cross-tenant routing of a subscription token is the exact construct that earned the customer-facing PROHIBITED verdict. Fail-closed at the lease boundary (CLO Guardrail 2) |
| 6 | Gate registrability to operator/internal accounts; surface nothing to customers; no external marketing | Keeps the use inside the permitted per-user scope (CLO Guardrails 3–4) |
| 7 | New error cause `subscription_limit`, distinct from API 429 | Subscription credit/rate-limit exhaustion fails differently; mis-mapping renders it as "key invalid" telling the user to re-paste a fine token (CTO; observability gate) |
| 8 | Ship behind a feature flag | Controlled rollout, timed for on/after June 15 |

## Open Questions

1. **Credit economics (CFO, non-blocking):** is the monthly Agent SDK credit actually
   large enough to cover the team's dogfooding volume vs. current API spend? The article
   doesn't quantify it. The whole motivation is cost — confirm the savings are real.
   If volume routinely exceeds the credit, the article's own steer applies: move back to
   an API key (a cost decision, not a compliance one).
2. **Token validation probe:** `setup-token` tokens can't be validated by a cheap
   `/v1/models` GET like API keys — needs a minimal subscription-auth probe reusing the
   existing `is_valid` write path (CTO).
3. **Delegation interaction:** `byok_delegations` resolves *which user's row* funds a run.
   For v1 (operator self-use, no delegation), the owner-only guardrail (Decision 5)
   forbids an `oauth_token` credential from ever funding a non-owner — so delegation +
   oauth_token must be explicitly disallowed until/unless re-reviewed.
4. **Post-June-15 text re-confirm:** re-read article 15036540 on/after June 15 before the
   first live run; the verdict is null and void if Anthropic amends the article.
   > **[SUPERSEDED 2026-06-16 — this trigger fired: Anthropic paused the June-15 change and amended article 15036540. See Re-review section at the end of this doc.]**

## Domain Assessments

**Assessed:** Product, Engineering, Legal (Marketing, Operations, Sales, Finance, Support
not separately spawned; Finance/CFO flagged as a non-blocking cost input — see Open Q1).

### Product (CPO)

**Summary:** Killed the **customer-facing** scope — the onboarding win is illusory
(`setup-token` needs a terminal + CLI install, a *higher* cliff than the web-console
API-key flow for a non-technical ICP) and it inverts the BYOK ~97%-margin economics. The
operator self-use re-scope is a legitimate internal cost play, not an ICP-facing feature;
never surface `setup-token` auth to non-technical users.

### Engineering (CTO)

**Summary:** Feasible, **~M (days)**, reusing all BYOK machinery. Load-bearing trap: when
both `ANTHROPIC_API_KEY` and `CLAUDE_CODE_OAUTH_TOKEN` are set, the API key silently wins
(`agent-env.ts:46-49` sets `ANTHROPIC_API_KEY` unconditionally today) — injection must be
mutually exclusive via an exhaustive branch, not an allowlist add. Change surface:
`credential_type` column on `api_keys`; `byok-lease.ts` returns `{value, type}`;
`agent-env.ts` + `cc-dispatcher.ts` (the SDK `apiKey` option must be omitted for OAuth
runs); a subscription-auth validation probe; `subscription_limit` error mapping. No new
infra; isolation guarantee intact. **Capability gaps: none.**

### Legal (CLO)

> **[SUPERSEDED 2026-06-16 — Anthropic paused the June-15 Agent SDK credit change. The "explicit permission" premise below never landed. New verdict: AMBIGUOUS, leaning tolerated (NOT explicitly-permitted), owner-only operator-self-use; basis downgraded permitted → tolerated risk-acceptance. The original verdict is preserved as the historical record. See the Re-review section at the end of this doc and the audit `knowledge-base/legal/audits/2026-06-16-clo-re-review-cc-oauth.md`.]**

**Summary:** **Permitted-with-guardrails, on/after June 15, 2026** (prohibited before).
The June 15 article is the explicit permission that lifts Consumer Terms §3's
automated-access bar (*"or where we otherwise explicitly permit it"*) for Agent SDK use;
the per-user constraint is satisfied because the token funds only its owner's runs. The
*"shared production automation → use an API key"* line is **guidance keyed on "shared" and
"production," not a prohibition** — operator dogfooding is neither, so it stays on the safe
side. **The line is: serving runs to anyone other than the token's owner.** No external
disclosure / no new sub-processor (operator processes its own data on its own
subscription; existing Anthropic PBC DPA row covers it). Load-bearing guardrails =
Decisions 4, 5, 6. Re-review trigger: any extension to a non-owner/customer run, or any
amendment to article 15036540 / the Consumer Terms.

## User-Brand Impact

- **Threshold:** single-user incident (here the "user" is the operator's own Max account).
- **Artifact at risk:** the operator's stored `CLAUDE_CODE_OAUTH_TOKEN` (subscription
  credential — tied to a personal Claude account, cannot be scoped/capped like an API key).
- **Vectors:**
  1. **Cross-tenant routing** — a bug routes the operator's subscription token into a
     customer's agent run → breaches Anthropic's per-user/no-share rule **and** risks the
     operator's own account ban. Mitigated by Decision 5 (owner-only routing, fail-closed).
  2. **Premature execution** — running the `oauth_token` path before June 15 is a ToS
     violation. Mitigated by Decision 4 (hard date gate + CI sentinel).
  3. **Silent mis-billing** — both-keys-set silently bills API. Mitigated by Decision 3
     (mutually-exclusive injection, exhaustive branch).
  4. **Token leak** — same surface as BYOK API keys; reuses HKDF encryption + zeroize.

## Capability Gaps

None reported. Engineering owns the full surface (`soleur:gdpr-gate`, `soleur:preflight`,
`soleur:flag-create`); legal disclosure tooling (`legal-compliance-auditor`) exists if
ever needed. Evidence: CTO grep confirmed BYOK lease/dispatcher/env files exist and no
`CLAUDE_CODE_OAUTH_TOKEN` handling exists yet (net-new branch, not a missing primitive).

## Lane

cross-domain (USER_BRAND_CRITICAL → triad CPO+CLO+CTO mandatory).

## Re-review 2026-06-16 — Anthropic paused the June 15 credit change

**This supersedes the original Legal (CLO) verdict above.** The original verdict
(2026-06-02) was conditioned on a **predicted** Anthropic policy transition: that on
2026-06-15, support article 15036540 would grant Pro/Max/Team/Enterprise plans a per-user
monthly "Agent SDK credit" that *"explicitly permits"* third-party apps to authenticate
with a Claude subscription, lifting Consumer Terms §3's automated-access bar. That
predicted permission was the entire load-bearing hook for the "permitted-with-guardrails"
disposition.

On **2026-06-16** Anthropic emailed that the change is **PAUSED**, and the live article
now reads:

> **Update June 15:** We're pausing the changes to Claude Agent SDK usage described below.
> For now, nothing has changed: Claude Agent SDK, `claude -p`, and third-party app usage
> still draw from your subscription's usage limits.

The pre-registered re-review trigger (Open Question 4 + the Legal summary's "any amendment
to article 15036540") has therefore **fired**.

### Superseding verdict

- **Disposition:** **AMBIGUOUS, leaning tolerated** (NOT explicitly-permitted) for the
  owner-only operator-self-use construction. The paused article's "still draw from your
  subscription's usage limits" is *metered tolerance*, not an explicit permission lifting
  the Consumer Terms §3 automated-access bar.
- **What survived intact:** the **per-user / no-pooling / no-share constraint** — the real
  risk axis — is still imposed by the article and is **enforced in code** by the owner-only
  routing guardrail (`OauthDelegationForbiddenError`). This did NOT change when the credit
  was paused.
- **Basis downgrade:** permitted → **tolerated / metered subscription use, owner-only
  no-share enforced in code, operator-borne risk-acceptance.**
- **Disabling is NOT mandatory.** The operator has elected to **keep `CC_OAUTH_ENABLED=1`**
  (dev + prd) as documented risk-acceptance.
- **Customer-facing / non-owner extension remains PROHIBITED** — and is now *harder* to
  justify, since there is no per-user-credit framework to point at.

### Updated re-review trigger

Replaces the old "any amendment to article 15036540 / the Consumer Terms" trigger with:
**Anthropic un-pauses / ships its promised advance-notice update; OR amends the "still
draw from your subscription's usage limits" sentence; OR any move off owner-only
operator-self-use (delegation, customer-facing, pooling).**

Full assessment: `knowledge-base/legal/audits/2026-06-16-clo-re-review-cc-oauth.md`.
