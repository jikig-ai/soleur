---
title: "Codex Web PR 9051 — mode authorization paths"
date: 2026-10-03
actor: "soleur:legal:clo/current session"
attestation_authority: soleur-legal-clo-agent
reviewed_head: 1410146498b6a975e7628c0574b7ebc39615b915
pr: 9051
status: pending-mode-evidence
api_key_live_disposition: pending-account-permission-and-custody-evidence
managed_hosted_auth_disposition: blocked-provider-permitted-integration
customer_content_status: blocked
review_by: 2026-10-15
reevaluation_triggers:
  - "Account permission, agreement, custody or provider integration evidence supplied"
  - "Change to test data classes, cohort, provider route or account controls"
  - "First arms-length user or regulated-industry use"
---

# Current internal CLO disposition

The operator confirmed in this session that neither mode is authorized and
asked how to authorize them. This attributable internal v1 assessment records
no live authorization. The founder supplies account facts and permission to
use and pay for an account; the Soleur CLO agent evaluates that evidence and
issues the internal legal disposition. This is draft internal review, not an
executed vendor agreement or external counsel opinion. CLA representations
remain unconfirmed and are outside this authorization decision.

The operator subsequently nominated their own Soleur application account.
Record its safe alias as `operator-soleur-account`; the supplied email is not
retained here. This identifies the intended application member, not an OpenAI
API project, credential reference, account agreement or hosted-use permission.
The operator reports no known API project or secret reference and authorized
creating the needed setup through browser automation. Proposed synthetic API
qualification has an explicitly authorized US$5 maximum, expiring seven days
after setup. This does not authorize customer content or clear technical gates.
Project/secret references, actual agreement coverage and permitted custody
remain pending. No paid usage is authorized beyond that bound; a project budget
alert alone must not be described as a hard spending cap.

| Mode | Disposition | Evidence needed before a narrow synthetic-egress decision |
|---|---|---|
| User-owned API key | **PENDING — account permission and custody evidence.** | Safe API account/project reference, accepting entity and applicable agreement, account owner's permission for the precise hosted custody/use path, billing/admin owner, budget/expiry and actual data controls. No valid credential or account permission is inferred from prior workspace identification. |
| Existing managed ChatGPT hosted-auth path | **BLOCKED — provider-permitted integration required.** | Evidence permitting the exact hosted integration, followed by safe account/workspace and plan references, owner/admin permission, applicable agreement, usage authority and data controls. This is not rejection of every possible managed mode. |

Customer content remains blocked separately in both modes. Offline preparation
with wholly invented fixtures remains the only allowance under the existing
2026-10-01 disposition. No provider request, credential inspection, account
inspection, production write or flag/cohort change was performed for this audit.

## Provider permission findings — retrieved 2026-10-03

The [Services Agreement, §§2.2–3.3](https://openai.com/policies/services-agreement/)
permits API integration into customer applications but restricts transferring
API keys to third parties. A user-owned hosted custody arrangement therefore
needs assessment against its actual account agreement; API eligibility alone
does not approve this implementation. The [DPA](https://openai.com/policies/data-processing-addendum/)
is incorporated into the Services Agreement, effective January 1, 2026. Its
public availability does not identify this account or prove its coverage.

The [App Server authentication documentation](https://developers.openai.com/codex/app-server/)
states: “App-server authentication has never been permitted for commercial or
hosted services.” It distinguishes continuing local/open-source applications
from the supported Sign in with ChatGPT path. For Soleur hosted Web, founder
permission alone cannot establish provider permission for the existing managed
authentication proposal; neither local smoke success nor a login supplies it.

The [Sign in with ChatGPT quickstart](https://developers.openai.com/siwc/quickstart)
describes selected commercial partners in a limited trial and separately
authorized plan-backed inference. Identity-only login is insufficient. The
[authorized App Server configuration](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server)
uses an application-owned OAuth token authorized for ChatGPT plan usage with
the Responses provider; it requires no separate Codex sign-in. This supplies a
possible integration path, not evidence that Soleur has partner approval or
that any nominated account is eligible. Keep the existing hosted-auth path
blocked until a permitted alternative has evidence and engineering review;
do not repurpose the current session credential.

## Actual runtime boundary

`apps/web-platform/server/agent-engine-data-egress-policy.ts` ›
`authorizeEngineDataEgress()` requires an accepted data class, verified vendor
DPA evidence and a known transfer basis for **every** class, including
synthetic. Verified provider deletion support is additionally required for
`customer`; an approval-required path needs `approvalGranted: true`.

`apps/web-platform/server/codex-conversation-runtime.ts` ›
`codexConversationRuntime()` still selects `customer`, accepts no data classes,
and supplies unverified vendor, unknown transfer/deletion evidence and required
approval. A paper synthetic allowance cannot unlock this composition. Any
synthetic Web qualification must use a reviewed, bounded composition satisfying
the real gate; unknown findings cannot be relabeled verified. Migration 145's
race-safe guard/recovery, branch preview and authenticated screenshot QA,
routine-consumer qualification and each Web matrix remain independent gates.

## Smallest evidence template — complete separately for each mode

Use safe aliases and evidence-reference names only. Do not commit account IDs,
emails, tokens, credential values, private documents or screenshots containing
them. A blank/unknown field is not approval.

| Field | API key | Managed ChatGPT |
|---|---|---|
| Account/workspace and credential reference; accepting entity; agreement reference | PENDING | PENDING, plus hosted-integration permission/client approval reference |
| Account owner/admin authority and explicit test permission; payer; spending bound; expiry | PENDING | PENDING, including permitted plan usage |
| Cohort/data scope | Proposed: one internal synthetic workspace; invented prompts/attachments only | Same proposed limit; not currently approved |
| Actual metadata/basis; geography/transfer evidence; training/retention controls; erasure limitations | PENDING | PENDING |
| Internal CLO actor/date, decision, restrictions and review trigger | PENDING after evidence | BLOCKED for existing hosted-auth path; reassess permitted alternative |
| Exact preview/build and bounded qualification evidence reference | PENDING | PENDING independently |

A synthetic-only decision does not authorize customer repository content,
history or other people's data. Synthetic prompts do not remove personal account
or connection metadata from the assessment. Approved Zero Data Retention and
customer-content deletion qualification are not additional synthetic-only
requirements merely by analogy; record the applicable limitations. The
implementation's DPA and transfer gate still applies. Customer authorization
requires the full account/agreement, transfer, retention/erasure, billing and
administration findings plus its independent qualification chain.

## Setup observation — 2026-10-03

The operator reports enabling credits on the OpenAI API account and confirms
Jikigai / Soleur as its owning and agreement-accepting entity. These facts are
operator-reported, not dashboard/agreement-verified by this audit. Browser preparation
reached repeated human verification at the official API and MFA pages; one
retry and the normal dashboard route did not reach an authenticated project
surface. The regular desktop browser was opened separately without copying
browser state. No project or credential was created, no secret was inspected,
and no inference call occurred. The US$5 maximum and seven-day expiry after
setup still apply; project/credential references and hard-cap enforcement
remain pending. API-key disposition therefore remains PENDING.
