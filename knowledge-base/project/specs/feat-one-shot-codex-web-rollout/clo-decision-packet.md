---
title: "Codex web engine — CLO decision packet"
date: 2026-09-21
status: pending-evidence-and-disposition
customer_content_status: blocked
---

# Codex web engine — CLO decision packet

## Decision requested

Issue a separate **approve, approve with restrictions, or reject** disposition for (1) a user-owned OpenAI API key and (2) a managed ChatGPT sign-in used by Soleur Web. For each mode, identify the exact account and agreement, permitted data classes and cohorts, geographic processing and transfer basis, retention and erasure limits, billing owner, and administrators. This packet records no approval. Customer repository content remains blocked by the runtime gate until the relevant disposition and live qualification both pass.

## Public evidence verified on 2026-09-21

| Question | API-key mode | Managed ChatGPT mode | Tenant evidence still needed |
|---|---|---|---|
| Applicable agreement and party | [Current DPA](https://openai.com/policies/data-processing-addendum/) supplements the [Services Agreement](https://openai.com/policies/services-agreement/); EEA customers contract through OpenAI Ireland under the DPA | The CLI reports only “Logged in using ChatGPT”; it does not identify whether the account is personal, Business, or Enterprise, or which agreement governs it | Account/workspace ID, plan, accepting entity, executed terms or order form, and DPA applicability for each mode |
| Processing and transfers | DPA §4 states SCC or adequacy safeguards for EEA/Swiss transfers; [subprocessor list](https://openai.com/policies/sub-processor-list/) names multiple processing regions | Same public list, but plan and workspace region are unknown | Actual API project and ChatGPT workspace regions, residency settings, transfer impact assessment, and onward processors used for this tenant |
| Retention | [API controls](https://platform.openai.com/docs/models/default-usage-policies-by-endpoint) state up to 30 days of default abuse logs, with ZDR/MAM only for approved eligible customers and endpoint state exceptions | Enterprise retention is workspace controlled; the currently signed-in plan and setting are unknown | Screenshots/export of API organization and project controls; ChatGPT workspace retention and Codex task history policy |
| Provider erasure | DPA §2.11 addresses data return/deletion after agreement end, subject to legal retention; API endpoint state and abuse logs have separate rules | [Enterprise compliance guidance](https://help.openai.com/en/articles/9261474) describes audit data that cannot be deleted through the Compliance API | Exact Codex thread deletion acknowledgement, residual logs/state, exceptions, and request path for erasure in each account |
| Billing | [Billing guidance](https://help.openai.com/en/articles/9039756) separates API from ChatGPT; API-key use has API pricing | [Codex plan guidance](https://help.openai.com/en/articles/20001275/) ties ChatGPT sign-in to plan allowance/credits | Paying entity, spending caps, cost attribution, and contract rate card |
| Ownership and administration | Services Agreement assigns input rights and output ownership to the customer as between the parties, subject to law; API org owner controls keys and billing | [Enterprise admins](https://help.openai.com/en/articles/8411955) can control Codex access; [managed-account notice](https://help.openai.com/en/articles/20001067-data-access-for-your-managed-chatgpt-account) describes admin access/export/retention | Identify the actual controllers, workspace owners/admins, user-account ownership, revocation, export, and audit controls |

## Observed qualification boundary

On 2026-09-21, the local Codex CLI v0.155.1 reported ChatGPT sign-in and completed one isolated, read-only, ephemeral synthetic text request. This confirms only basic account access and response. It does not qualify the Soleur Web transport, attachments, approvals, cancellation, reconciliation, provider deletion, usage accounting, or deployed application. Production Doppler has no `OPENAI_API_KEY` secret, so API-key live qualification remains unavailable through that path. No customer repository content was sent.

## Required disposition record

The CLO should record, for **each mode independently**: decision and date; account/agreement evidence reference; allowed data classes and cohort; location/transfer finding; retention and provider-erasure finding; billing and administrator owner; restrictions and review expiry. An internal synthetic-only allowance may be narrower than customer-content approval. Blank fields or public policy alone mean **pending**.
