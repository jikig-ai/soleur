---
title: "Codex web engine — CLO decision packet"
date: 2026-09-22
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

On 2026-09-22, the local Codex CLI v0.155.1 completed one isolated, read-only, ephemeral synthetic text request and returned the required sentinel. This confirms only basic account access and response. It does not qualify the Soleur Web transport, attachments, approvals, cancellation, reconciliation, provider deletion, usage accounting, or deployed application. Production Doppler has no `OPENAI_API_KEY` secret, so API-key live qualification remains unavailable until an authorized test workspace supplies a key through Web settings. No customer repository content was sent.

## Required disposition record

The CLO should record, for **each mode independently**: decision and date; account/agreement evidence reference; allowed data classes and cohort; location/transfer finding; retention and provider-erasure finding; billing and administrator owner; restrictions and review expiry. An internal synthetic-only allowance may be narrower than customer-content approval. Blank fields or public policy alone mean **pending**.

## Disposition status as of 2026-09-22

No CLO disposition has been received or recorded for either mode. This packet is
not an approval and cannot authorize customer-content processing. The exact
decision still required is one attributable CLO entry for API-key mode and one
for managed ChatGPT mode, each naming the agreement/account, permitted cohort
and data classes, processing locations and transfer basis, retention and
erasure limits, billing owner, administrators, restrictions, and review date.
Until those entries exist, the feature remains default-off and customer
processing remains blocked.
