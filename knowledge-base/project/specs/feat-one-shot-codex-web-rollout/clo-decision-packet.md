---
title: "Codex web engine — CLO decision packet"
date: 2026-09-23
status: pending-mode-specific-clo-disposition
customer_content_status: blocked
---

# Codex web engine — CLO decision packet

## Decision requested

Issue a separate **approve, approve with restrictions, or reject** disposition for (1) a user-owned OpenAI API key and (2) a managed ChatGPT sign-in used by Soleur Web. For each mode, identify the exact account and agreement, permitted data classes and cohorts, geographic processing and transfer basis, retention and erasure limits, billing owner, and administrators. This packet records no approval. Customer repository content remains blocked by the runtime gate until the relevant disposition and live qualification both pass.

## Public evidence verified on 2026-09-22

| Question | API-key mode | Managed ChatGPT mode | Tenant evidence still needed |
|---|---|---|---|
| Applicable agreement and party | [OpenAI DPA effective 2026-01-01](https://openai.com/policies/data-processing-addendum/) supplements the OpenAI Services Agreement; the DPA names OpenAI OpCo, LLC, or OpenAI Ireland Ltd. for EEA/Swiss customers | The CLI smoke only proves a ChatGPT login; it does not identify whether the account is personal, Business, or Enterprise, or which agreement governs it | Account/workspace ID, plan, accepting entity, executed terms or order form, and DPA applicability for each mode |
| Processing and transfers | OpenAI states eligible API customers may select U.S. or Europe processing on supported endpoints; the [subprocessor list](https://openai.com/policies/sub-processor-list/) names API and ChatGPT processing locations | [Managed-account guidance](https://help.openai.com/en/articles/20001067-data-access-for-your-managed-chatgpt-account) confirms the organization controls data and services, but the test account’s region and plan are unknown | Actual API project and ChatGPT workspace regions, residency settings, transfer impact assessment, and onward processors used for this tenant |
| Retention | [Business data guidance](https://openai.com/business-data/) says eligible API customers can configure retention, including ZDR; endpoint and abuse-monitoring exceptions still apply | [Business residency guidance](https://help.openai.com/en/articles/20001418) says non-U.S. workspaces still keep safety/abuse-monitoring data in the U.S.; Enterprise/Edu have separate policies | Screenshots/export of API organization and project controls; ChatGPT workspace retention and Codex task-history policy |
| Provider erasure | DPA §2.11 addresses return/deletion after expiry or termination, subject to legal retention; abuse-monitoring and endpoint-state exceptions must be identified | Managed-account administrators may access, export, retain, or delete account data; exact Codex deletion and audit-log behavior is unverified | Exact Codex thread deletion acknowledgement, residual logs/state, exceptions, and request path for erasure in each account |
| Billing | [Billing guidance](https://help.openai.com/en/articles/9039756) separates API from ChatGPT; API-key use has API pricing | [Codex plan guidance](https://help.openai.com/en/articles/20001275/) ties ChatGPT sign-in to plan allowance/credits | Paying entity, spending caps, cost attribution, and contract rate card |
| Ownership and administration | Services Agreement assigns input rights and output ownership to the customer as between the parties, subject to law; API org owner controls keys and billing | [Enterprise admins](https://help.openai.com/en/articles/8411955) can control Codex access; [managed-account notice](https://help.openai.com/en/articles/20001067-data-access-for-your-managed-chatgpt-account) describes admin access/export/retention | Identify the actual controllers, workspace owners/admins, user-account ownership, revocation, export, and audit controls |

## Observed qualification boundary

The 2026-09-22 local Codex CLI smoke and 2026-09-23 local App Server/transport probes completed isolated read-only synthetic text turns. The latter confirmed a terminal response, neutral usage event, and unique event IDs through the local Soleur transport. `thread/delete` returned an empty acknowledgement, and a later `thread/read` returned `thread not loaded`; these observations do not establish provider-side erasure or retention. They do not qualify authenticated Soleur Web conversation or routine execution, attachments, approvals, cancellation, reconciliation, usage persistence, or the deployed application. API-key live qualification remains unavailable until an authorized synthetic test workspace supplies a key through Web settings; no global Soleur API key is required. No customer repository content was sent.

## Required disposition record

The CLO should record, for **each mode independently**: decision and date; account/agreement evidence reference; allowed data classes and cohort; location/transfer finding; retention and provider-erasure finding; billing and administrator owner; restrictions and review expiry. An internal synthetic-only allowance may be narrower than customer-content approval. Blank fields or public policy alone mean **pending**.

## Disposition status as of 2026-09-23

No CLO disposition has been received or recorded for either mode. This packet is
not an approval and cannot authorize customer-content processing. The exact
decision still required is one attributable CLO entry for API-key mode and one
for managed ChatGPT mode, each naming the agreement/account, permitted cohort
and data classes, processing locations and transfer basis, retention and
erasure limits, billing owner, administrators, restrictions, and review date.
Until those entries exist, the feature remains default-off and customer
processing remains blocked.

## CLO assessment — 2026-09-27

The operator identified **Soleur Workspace** and its owner as the authorized
synthetic test workspace. A read-only production lookup verified that
relationship; the owner's email is omitted from this public repository. This
does not identify or prove the contract, account, or administrative
relationship with OpenAI for either auth mode. A read-only production
credential check on 2026-09-27 found no valid OpenAI API-key credential for
this workspace. No provider request was made.

| Mode | CLO disposition | Evidence and limit | Internal synthetic cohort |
|---|---|---|---|
| User-owned API key | **PENDING — no authorization.** This is not a merits rejection. | Soleur Workspace and its owner are identified, but no valid OpenAI key is configured. The API organization/project, accepting entity and applicable agreement, selected region, retention settings, erasure exceptions, billing owner, and provider administrators are not evidenced. The local CLI/App Server probes are not API-key-mode evidence. | **Not qualified.** There is no credential with which to run the Web matrix. |
| Managed ChatGPT sign-in | **PENDING — no authorization.** This is not a merits rejection. | The local CLI/App Server synthetic probes establish only that a signed-in local session could answer synthetic prompts. They do not tie that account to Soleur Workspace or establish account type, ChatGPT workspace ID/owner, agreement, region, retention, deletion behavior, billing owner, or administrators. In the current worktree, `codexConversationRuntime()` sets `vendorDpaStatus: "unverified"`, `transferGeography: "unknown"`, `acceptedDataClasses: []`, and `approvalRequired: true`; it intentionally cannot authorize live egress. | **Not qualified.** Neither account-level evidence nor authenticated Soleur Web qualification is present. |

For both modes, the requested API-key / managed account facts remain
unresolved, and the synthetic workspace identity alone is insufficient to
establish a permitted provider relationship or processing path. Keep
`codex-engine` default-off; neither mode is currently authorized for an
internal synthetic cohort. Reassess the applicable mode when its account and
agreement facts are evidenced, before any cohort enablement. Customer-content
processing remains blocked pending the full mode-specific disposition and
qualification gates. This assessment records no account, agreement, transfer,
retention, billing, administrator, or CLO approval fact beyond the evidence
stated above.

## Current mode authorization addendum — 2026-10-03

The operator confirms neither mode is authorized. The attributable
[current CLO audit](../../../legal/audits/2026-10-03-codex-web-mode-authorization.md)
records **API key: PENDING account permission and custody evidence** and
**existing managed hosted-auth path: BLOCKED provider-permitted integration**.
The latter is not a blanket rejection of managed modes: a permitted Sign in
with ChatGPT integration or explicit provider permission requires separate
assessment. The audit supplies a safe-reference evidence template and
distinguishes founder account/spending permission from internal CLO attestation.

> **Superseded 2026-10-03 (PR #9051):** The 2026-09-27 managed-mode PENDING
> classification is historical. Current official provider guidance identifies
> a hosted-auth integration restriction requiring the BLOCKED finding above.
> Prior smoke measurements remain unchanged and do not authorize Web use.

No synthetic provider egress or customer-content authorization is granted.
The actual runtime requires verified DPA and known transfer evidence even for
synthetic data, while the current Web composition selects unqualified customer
data. Keep the PR draft and feature default-off; migration, preview/QA, routine
and per-mode Web qualification gates remain independent.
