---
title: "CLO re-review — operator Claude Code subscription OAuth (Anthropic paused the June 15 Agent SDK credit)"
type: counsel-review
date: 2026-06-16
related_pr: 4824
related_branch: feat-one-shot-correct-cc-oauth-legal-rationale
artifact: apps/web-platform/server/byok-lease.ts (operator-cc-oauth / oauth_token credential)
brand_survival_threshold: single-user incident
status: DRAFT (CLO-agent-attested, Soleur-as-tenant-zero v1 internal assessment)
disposition: AMBIGUOUS-LEANING-TOLERATED — keep enabled as documented risk-acceptance
reviewed_by: "CLO agent (v1 internal counsel-review attestation, Soleur-as-tenant-zero posture)"
operator: "Jean Deruelle (Jikigai SARL gérant)"
re_evaluation_triggers: "Anthropic un-pauses / ships its promised advance-notice update; OR amends the 'still draw from your subscription's usage limits' sentence; OR any move off owner-only operator-self-use (e.g. delegation, customer-facing, pooling)"
draft_notice: "Draft internal legal guidance for a non-lawyer founder. NOT a substitute for licensed external counsel."
---

# CLO re-review — operator Claude Code subscription OAuth

> **Draft notice.** This is draft internal legal guidance prepared for a non-lawyer
> founder operating Soleur as tenant-zero. It is **not** a substitute for licensed
> external counsel. It records a v1 internal CLO-agent attestation of the operator's
> own ToS posture for funding the operator's own agent runs on the operator's own
> Claude Max subscription.

## 1. What changed (the trigger)

The original verdict (brainstorm `2026-06-02-operator-cc-subscription-auth-brainstorm.md`,
Legal/CLO summary) was **"permitted-with-guardrails, on/after June 15, 2026."** It was
conditioned entirely on a **predicted** Anthropic policy transition: that on 2026-06-15,
support article 15036540 would grant Pro/Max/Team/Enterprise plans a per-user monthly
"Agent SDK credit" that *"explicitly permits"* third-party apps to authenticate with a
Claude subscription — the §3(b) "or where we otherwise explicitly permit it" hook that
would lift the Consumer Terms automated-access bar for Agent SDK use.

On **2026-06-16** Anthropic emailed the operator that this change is **PAUSED**
("we're not making this change today … there's no credit to claim … Your subscription
limits are unchanged"). The live article now reads, verbatim:

> **Update June 15:** We're pausing the changes to Claude Agent SDK usage described below.
> For now, nothing has changed: Claude Agent SDK, `claude -p`, and third-party app usage
> still draw from your subscription's usage limits.

The premise that "the conduct becomes explicitly-permitted on June 15" is therefore now
**false**. The pre-registered re-review trigger (brainstorm Open Question 4: "the verdict
is null and void if Anthropic amends the article") has fired.

## 2. The five answered questions

**Q1 — Is operator self-use currently permitted, prohibited, or ambiguous?**
**AMBIGUOUS, leaning tolerated** (NOT explicitly-permitted) for the owner-only
operator-self-use construction. The paused article's "Agent SDK … usage still draw from
your subscription's usage limits" is *metered tolerance* — Anthropic affirmatively
describes third-party Agent-SDK subscription usage as a working, metered path with no
prohibition caveat. That is materially weaker than an affirmative §3(b) "explicit
permission," but it is not a prohibition either.

**Q2 — Does the pre-June-15 "prohibited" analysis now control?**
**No** — but neither does the original "explicitly permitted" analysis. The original
turned on the *predicted permission*, which did not land. What **did** survive intact is
the **per-user / no-pooling / no-share constraint** — the real risk axis. Anthropic still
states credits/usage "belong to individual accounts" and cannot be "shared or pooled."
Soleur satisfies that by construction: the token funds only its own owner's runs.

**Q3 — Must the feature be disabled (`CC_OAUTH_ENABLED=0`)?**
**No — disabling is NOT mandatory.** The conduct is tolerated/metered; owner-only is
enforced in code (`OauthDelegationForbiddenError`); the operator bears the small,
owner-self-use residual risk. The operator has elected to **keep it enabled** as
documented risk-acceptance. Residual risk if kept on (operator-borne): if Anthropic later
un-pauses *and changes the rules* to disallow raw subscription draw for third-party apps,
the downside is enforcement against the **operator's own** Claude account
(rate-limiting / suspension) — not a customer or sub-processor risk.

**Q4 — Is the owner-only / non-customer boundary unchanged?**
**Yes — unchanged and still load-bearing.** `OauthDelegationForbiddenError`
(`apps/web-platform/server/byok-lease.ts`, fired in the oauth-read branch of
`fetchAgentCredentialIntoSlot`) enforces it fail-closed: a delegated lease or a keyOwner
that differs from the workspace-context owner is rejected. This is the gate the entire
tolerated basis rests on. The customer-facing / multi-user extension remains
**PROHIBITED** and is now *harder* to justify (no per-user-credit framework to point at).

**Q5 — New re-review trigger going forward?**
The old trigger ("any amendment to article 15036540 / the Consumer Terms") has fired and
is discharged by this review. Re-review and reconfirm before continued reliance if ANY of:
Anthropic **un-pauses / ships its promised advance-notice update**; OR **amends the "still
draw from your subscription's usage limits" sentence** (now the load-bearing tolerance
signal); OR **any move off owner-only operator-self-use** (delegation, customer-facing,
pooling) — which also escalates to *external* counsel.

## 3. Basis downgrade (recorded)

The documented legal basis is downgraded **permitted → tolerated risk-acceptance.**

"Tolerated" here means: metered subscription use that Anthropic's own (paused) article
describes as still drawing from subscription limits — no explicit blessing, and no
explicit prohibition for owner-self-use. The construct that remains clearly prohibited is
pooling / sharing / serving runs to anyone other than the token's owner — which the
owner-only routing guardrail blocks in code. The basis is therefore: **tolerated / metered
subscription use; owner-only, no-share enforced in code; operator-borne risk-acceptance.**

## 4. Recommended actions

| Action | Status | Owner |
|--------|--------|-------|
| Correct `byok-lease.ts` comments (spent-date-gate framing, drop "policy gate"/"legal floor"/"becomes permitted") | this PR | eng |
| Correct `.env.example` `CC_OAUTH_ENABLED` basis (tolerated risk-acceptance, not June-15 permission) | this PR | eng |
| Supersede the brainstorm CLO verdict in place (do not delete the historical record) | this PR | eng |
| Record this audit | this PR | clo |
| Keep `CC_OAUTH_ENABLED=1` in Doppler dev+prd | already set out-of-band | operator |
| Keep owner-only routing guardrail (`OauthDelegationForbiddenError`) fail-closed | unchanged (no action) | eng |
| Re-review on un-pause / article amendment / any non-owner extension | watch | clo |

## 5. Disclaimer

This assessment addresses only the operator's own ToS posture for owner-self-use of the
operator's own Claude subscription via the Agent SDK. It does not opine on any
customer-facing, delegated, or pooled use (all of which remain prohibited and would
require fresh review, including licensed external counsel). It is a draft internal
attestation and **not a substitute for licensed external counsel.**
