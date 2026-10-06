---
title: Codex Web public sources and account evidence guide
date: 2026-10-06
source_sha: 696a76dfb04726b68dfaa4d9edd87c328270fa87
status: pending-no-live-authorization
---

# Public sources and account evidence

Scoped internal assessment by `soleur:legal:clo` (`/root/public_clo`),
against the source SHA above. This supplements the
[mode audit](../../../legal/audits/2026-10-03-codex-web-mode-authorization.md)
and [public-source reassessment](../feat-one-shot-codex-web-rollout/clo-decision-packet.md#public-source-clo-reassessment--2026-10-05).
It changes no published legal document and grants no live authorization.

## Published evidence and existing owner statement

The [Services Agreement](https://openai.com/policies/services-agreement/),
effective January 1, 2026, permits API integration into customer applications
(§2.2), incorporates the DPA (§5.3), and restricts API-key transfers involving
third parties (§3.3(g)). The
[DPA](https://openai.com/policies/data-processing-addendum/) allows acceptance
through the applicable agreement or service use and supplies SCC/adequacy
safeguards for covered EEA/Swiss onward transfers (§4.1). The request to find
these public documents is discharged; account applicability remains distinct.
A separately signed private DPA is not inherently required.

Retain the existing operator statement that Jikigai/Soleur owns and accepts
the agreement for the nominated account. It can serve as owner attestation
for narrow internal assessment; do not repeatedly request the same statement.
The smallest novel contract fact is whether a separate order form, reseller
arrangement or negotiated amendment changes the standard terms for that API
organization. A sanitized owner confirmation can establish that internal
record absent contradictory evidence. An organization name is
[only a display label](https://help.openai.com/en/articles/9106908-how-can-i-change-my-api-platforms-org-name);
billing attribution alone also does not prove acceptance.

Using the same entity's own API credential on its own backend can be assessed
conditionally as same-entity custody. The
[key-safety guidance](https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety)
supports keeping one's key on one's backend. This does not authorize hosting
other customers' credentials or settle the App Server authentication route.
`codex-credential-provider.ts` › `createCodexApiKeyProviderForUser()` loads
the authenticated user's encrypted setting; `createCodexApiKeyProvider()`
decrypts it server-side. This application has credential custody.

## Exact provider route

[App Server guidance](https://learn.chatgpt.com/docs/app-server) still states
a commercial/hosted authentication restriction before describing its modes.
Generic API integration permission does not conclusively settle the proposed
hosted API-key `account/login/start` flow. That RPC is a provider-permission
question, not an authentication path verified as implemented in this branch.
Keep the existing managed hosted authentication path blocked.

[Sign in with ChatGPT plan usage](https://developers.openai.com/siwc/token-sharing-open-source)
documents open-source/local applications and directs paid or remotely hosted
applications to an interest form.
[Commercial client registration](https://developers.openai.com/siwc/request-client-id)
is offered to selected partners. Registration interest, identity-only login
and local configuration are not hosted inference permission. The
[preview's storage requirements](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
apply to that documented route, not automatically to this branch's current
API-key implementation.

The [commercial interest form](https://openai.com/form/sign-in-with-chatgpt-interest/)
distinguishes identity-only sign-in from sign-in with ChatGPT-plan AI requests.
The latter is the relevant requested capability for hosted plan-backed
inference. The form requests contact/company details and a product description;
no submission occurred. It is a route to request permission, not a permission
already held by Soleur.

Prepared provider clarification, not sent:

> We operate Soleur, a remotely hosted commercial application. For an internal
> synthetic test, the API customer and application operator are the same legal
> entity. We are considering Codex App Server's `account/login/start` with
> `type:"apiKey"` on that entity's backend using its own project credential.
> Is this permitted for our hosted application?
> Please clarify the commercial/hosted authentication restriction and identify
> a supported API-funded configuration. Separately, which approval is required
> for hosted ChatGPT-plan-backed inference? We are not requesting browser/session
> credential reuse or custody of other customers' keys.

## Data baseline and implementation boundary

[API data controls](https://developers.openai.com/api/docs/guides/your-data)
establish no model training by default unless opted in, default abuse-log
retention up to 30 days with exceptions, and Responses application-state
retention of at least 30 days for default/`store:true` behavior. MAM/ZDR need
approval. Regional storage and processing differ, and residency excludes
system/account metadata. The reported “Global” region proves no confinement.

The developer must verify actual endpoint, model, request storage and
attachment/tool behavior. At this source, `codex-conversation-runtime.ts` ›
`codexConversationRuntime()` declares `https://api.openai.com/v1`, no accepted
data classes, unverified DPA and unknown transfer/deletion support, with no
approved launcher. This is fail-closed configuration, not an observed provider
request or a regional/storage guarantee. Account settings alone cannot qualify
the runtime or determine its actual `store` behavior.

## Read-only account guide

Use the regular browser where the operator already reports account access.
These are requested guidance and optional evidence checks, not agent claims
that the controls were inspected. Existing authentication-call and challenge-
retry restrictions prohibit an authenticated automation attempt in this turn.
No setting change, key creation, provider request or form submission is implied.

| Fact | Where to look | Safe result |
|---|---|---|
| Selected account/project and authority | API dashboard → Settings → Organization/Project → Members; [project guide](https://help.openai.com/en/articles/9186755-managing-projects-in-the-api-platform) | Owner role and safe account/project aliases; omit IDs/emails |
| Billing context | Organization → Billing → Preferences; [billing guide](https://help.openai.com/en/articles/9038389) | Whether the billing attribution matches recorded Jikigai ownership; omit addresses/payment details |
| Standard terms or override | Existing onboarding/purchase records or OpenAI sales agreement, if any | Standard terms with no known override, or a safe agreement-reference name |
| Training sharing | Organization → Data controls → Sharing; [sharing guide](https://help.openai.com/en/articles/10306912-sharing-feedback-evaluation-and-fine-tuning-data-and-api-inputs-and-outputs-with-openai) | Disabled/enabled and whether the nominated project is included |
| Retention | Organization → Data controls → Data Retention, if available; [controls guide](https://developers.openai.com/api/docs/guides/your-data) | Standard baseline or approved MAM/ZDR; project inherit/override. Absence of the tab does not prove ZDR |
| Region | Selected project's General/settings information | Retain the existing “Global” report unless new evidence changes it; no EEA-only claim |
| Spend | Project → Limits → Spend; [spend guide](https://developers.openai.com/api/docs/guides/spend-limits) | Retain reported US$5 enforced limit, or report whether enforcement is enabled; inspect only |

OpenAI documents enforced monthly hard limits at project and organization
levels. The US$5 report is compatible with that feature; alerts differ.
Enforcement lag can allow slight overspend, and monthly reset does not enforce
seven-day expiry. The reported maximum key lifetime proves neither key
creation nor an actual test deadline. No credential value is needed for any
check above; redact identifiers and unrelated content from evidence.

## Disposition

API key remains **PENDING — no live authorization**. Existing managed hosted
auth remains **BLOCKED — provider-permitted integration required**. Remaining
gaps are precise route permission, any contract override, actual request/data
controls, bounded execution and deadline evidence, and independent Web
qualification. Customer content remains blocked; PR #9051 stays draft and
Codex default-off. Recovery, screenshots, routine execution and full-branch
review are independent incomplete gates.
