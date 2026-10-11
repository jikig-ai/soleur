---
title: "Codex Web PR 9051 — remaining-AC mode reassessment"
date: 2026-10-11
actor: "soleur:legal:clo / Codex mode_disposition assessment"
attestation_authority: soleur-legal-clo-agent
reviewed_head: 3c3ba13b29053071b690598325362b343299bc1a
pr: 9051
status: blocked-live-authorization
api_key_live_disposition: pending-account-custody-and-provider-route-evidence
managed_hosted_auth_disposition: blocked-provider-permitted-integration
customer_content_status: blocked
decision_packet: knowledge-base/project/specs/feat-one-shot-codex-web-rollout/clo-decision-packet.md
prior_disposition: knowledge-base/legal/audits/2026-10-03-codex-web-mode-authorization.md
review_by: 2026-10-15
reevaluation_triggers:
  - "Sanitized account/agreement, custody, effective controls or provider-route permission evidence supplied"
  - "Change to authentication route, endpoint, cohort, data classes or request storage behavior"
  - "First arms-length user, EEA-out processing or regulated-industry use"
---

# Internal CLO continuation

**API key remains PENDING without live authorization. The existing managed
hosted-auth integration remains BLOCKED.** This attributable internal v1
disposition supplements the [decision packet](../../project/specs/feat-one-shot-codex-web-rollout/clo-decision-packet.md#public-source-clo-reassessment--2026-10-05)
and [prior mode audit](2026-10-03-codex-web-mode-authorization.md). It grants no
synthetic provider egress or customer-content authorization. The request to
continue remaining acceptance criteria supplies no new vendor permission or
account/control evidence. This is draft internal material requiring professional
legal review, not an executed agreement or external counsel opinion.

## Evidence inventory and artifact verdicts

| Artifact | Health / verdict | Action |
|---|---|---|
| Canonical T&C, Privacy Policy, GDPR Policy, Data Protection Disclosure, AUP, Cookie Policy, Disclaimer, individual and corporate CLA | Present; inventory records T&C/AUP dated 2026-10-08. Other listed dates are historical, not a new consistency attestation. | No published-document edits in this reassessment. Existing PR-conditioned amendments remain conditioned on merge/application. |
| [Compliance posture](../compliance-posture.md#agent-engine-processing-migration-138--pr-8082) and [OpenAI snapshot](../data-processing-agreements/openai.md) | Reviewed; provider processing remains gated. Public vendor record is not account-specific DPA acceptance. | Preserve processing and qualification holds. |
| Decision packet and 2026-10-03 mode audit | Reviewed; no evidence discharging either mode hold. | This dated audit is an append-only continuation; earlier measurements and dispositions retain their dates. |
| [2026-10-07 control intake](../../project/specs/feat-one-shot-codex-web-rollout/api-control-evidence-2026-10-07.md) | Reviewed; organization sharing selections persisted in operator-reported reload. Project sharing/inheritance, retention and configured storage/processing regions remain unknown. | Obtain project-bound, sanitized evidence; repeated storage-error screens establish no retention finding. |
| Current source named below | Reviewed for custody, mode selection and egress boundary; guarded, not live-qualified. | Engineering must establish exact route and independent recovery/Web qualification. |

## Fresh provider-source findings

Retrieved 2026-10-11: [ChatGPT plan-usage overview](https://developers.openai.com/siwc/token-sharing-open-source)
describes open-source and locally hosted applications and directs paid or
remotely hosted applications to an interest form. That public route is not
evidence of Soleur approval. The operator's 2026-10-07 absence report for hosted
permission remains the latest account-specific evidence; no form was submitted.

The [App Server auth documentation](https://learn.chatgpt.com/docs/app-server#auth-endpoints)
places a commercial/hosted authentication restriction before descriptions of
API-key, managed ChatGPT and experimental external-token modes. The presence of
`account/login/start` with `apiKey` or `chatgptAuthTokens` describes a protocol;
it supplies no provider permission for Soleur's hosted integration. **Internal
interpretation:** API-key App Server route permission remains unresolved rather
than established by generic API integration permission. Managed hosted auth
remains blocked; a permitted alternative requires its own evidence and review.

The [Services Agreement §§2.2, 3.3(g), 5.3](https://openai.com/policies/services-agreement/)
permits API integration into customer applications, restricts third-party API-key
transfers, and incorporates the DPA for personal-data processing. The
[DPA §§2.11, 4.1](https://openai.com/policies/data-processing-addendum/)
provides conditional deletion and EEA/Swiss onward-transfer mechanisms. These
texts establish available contractual mechanisms, not this nominated account's
accepting entity, acceptance, custody arrangement or effective configuration.
No separately signed DPA or approved ZDR is invented as an automatic prerequisite
for every synthetic-only decision; actual applicability and limitations still
need assessment.

## Current runtime findings

`codex-conversation-runtime.ts` › `codexConversationRuntime()` selects
`customer`, accepts no data classes, records an unverified DPA and unknown
transfer/deletion evidence, requires approval, and supplies no approved launcher.
`agent-engine-data-egress-policy.ts` › `authorizeEngineDataEgress()` requires
qualified data, verified DPA and known transfer evidence even for synthetic
requests; customer requests additionally require verified provider deletion.
Unknown evidence cannot be changed to verified to obtain a passing matrix.

`codex-credential-provider.ts` › `createCodexApiKeyProviderForUser()` loads the
user's encrypted Web-settings credential; `createCodexApiKeyProvider()` decrypts
it server-side. Soleur has custody. `codex-web-runtime.ts` ›
`createCodexWebEngineFactories()` selects the persisted mode without credential
fallback, requires an injected provider for managed mode, and requires a
transport or launcher composition for either mode.
`codex-app-server-launcher.ts` › `createCodexAppServerLauncher()` supplies a
caller-defined minimal environment; the exact live credential-delivery route is
not established by that seam. Source review proves none of account permission,
hosted-route permission or mode-specific Web qualification.

## Mode decisions and smallest safe evidence

| Mode | Internal decision | Evidence required for reassessment |
|---|---|---|
| User-owned API key | **PENDING — no live authorization; not a merits rejection.** | Bind safe account/project aliases to accepting entity and applicable agreement/DPA; establish account/admin/payer authority and same-entity custody or permission for the precise arrangement; resolve the exact hosted App Server authentication route; record effective project sharing/inheritance, retention, configured regions and endpoint/request storage/transfer limitations; establish actual test deadline and enforceable US$5 total bound. |
| Existing managed hosted auth | **BLOCKED — provider-permitted integration required.** | First supply provider approval or evidence permitting the exact alternative hosted route; then establish safe account/workspace/plan aliases, agreement, owner/admin/payer and plan-usage authority, effective controls and independent mode qualification. A successful login or experimental token method cannot discharge this block. |

Use sanitized references or a project-bound support response, never raw IDs,
emails, credentials, browser state or private agreements in Git. The previously
documented read-only project-metadata and project/organization-retention reads
are possible evidence sources only when authorized authentication is available;
none was executed here. Effective inheritance needs both project and organization
values. A configured region does not prove a particular request's processing
location; endpoint/model eligibility and routing must be assessed separately.
Disabled sharing, per-call logging and an absent region field establish no ZDR,
erasure or residency claim. A conservative baseline may support a future narrow
decision when applicability is evidenced, without pretending stronger controls.

The historical US$5 project setting and seven-day maximum key lifetime reports
do not establish a US$5 total test cap or the actual seven-day-after-setup expiry.
This audit neither renews that window nor authorizes key creation/inspection,
browser-auth copying, provider calls, shared writes, deployment or flag/cohort
changes. Recovery, authenticated screenshots, an eligible routine consumer and
separate Web matrices remain technical prerequisites, independent of this audit.

Priority is to resolve API account/custody/route evidence before egress, and
provider-permitted hosted integration before managed-mode qualification. The
CLO owns the next attributable legal decision; the CTO owns implementation and
qualification. Substantive vendor-term escalation has the existing
[AI vendor terms route](../recommended-tools.md#ai-vendor-terms); no specialist
dispatch or external message occurred. **Live-authorization gate: BLOCKED.**
Keep PR #9051 draft, auto-merge disarmed, Codex default-off and customer content
blocked. Public-source review and this audit do not satisfy the remaining live
acceptance criteria.
