---
vendor: OpenAI
role: proposed processor for Codex web-agent customer-content processing
status_snapshot_date: 2026-09-21
customer_content_status: blocked
clo_disposition: pending
user_owned_provider_path: documented-in-product; vendor-account-terms-apply
---

# OpenAI — Codex vendor and DPA snapshot

This is an evidence record for the Codex web-agent integration. It is not a
signed agreement and does not itself approve customer-content processing. The
runtime remains synthetic-only until the open conditions below are discharged
for each authentication mode.

## Public evidence reviewed

| Field | API-key mode | Managed ChatGPT sign-in |
|---|---|---|
| Public business privacy statement | OpenAI says business/API inputs and outputs are not used to train models by default and that qualifying customers can configure retention controls | The statement covers ChatGPT Business/Enterprise, but the exact managed account and agreement used by the integration must be identified |
| DPA scope | The current DPA, effective 2026-01-01, supplements the OpenAI Services Agreement; the actual API organization and accepting entity still need identification | No approval is inferred for a personal or otherwise unidentified ChatGPT account; identify the workspace, plan, and applicable agreement |
| Retention evidence | API abuse-monitoring logs may be retained up to 30 days by default; Zero Data Retention or Modified Abuse Monitoring requires eligibility and approval, and endpoint application-state rules still apply | Workspace retention and administrator controls must be evidenced from the specific Business/Enterprise agreement |
| Transfer geography | The current DPA provides SCC or adequacy safeguards for EEA/Swiss transfers; the public subprocessor list names processing locations across several regions. The tenant's selected region and actual transfer path remain unverified | Same unresolved tenant-specific location and transfer path, plus account-region and administrator-control confirmation |
| Remote erasure | The adapter requires an exact provider delete acknowledgement and resets the next thread, but provider-side retention/deletion terms still need contractual evidence | Same requirement, with managed-account deletion semantics confirmed separately |

## Current public evidence and its limits

The [current OpenAI DPA](https://openai.com/policies/data-processing-addendum/) is effective 2026-01-01; the earlier February 2024 page previously cited below is historical. Section 4 describes SCC or adequacy safeguards for EEA/Swiss transfers, and Section 2.11 addresses return or deletion after agreement expiry or termination. Neither proves this tenant's agreement, region, retention configuration, or deletion of a specific Codex thread. The [subprocessor list](https://openai.com/policies/sub-processor-list/) names infrastructure and processing locations; a tenant-specific path is still unknown.

OpenAI's [API data controls](https://platform.openai.com/docs/models/default-usage-policies-by-endpoint) describe default abuse-log retention of up to 30 days, approval requirements for Modified Abuse Monitoring or Zero Data Retention, and endpoint-specific application-state exceptions. The actual API project settings are unverified. [OpenAI billing guidance](https://help.openai.com/en/articles/9039756) states that API and ChatGPT billing are separate; [Codex plan guidance](https://help.openai.com/en/articles/20001275/) assigns ChatGPT sign-in to the ChatGPT plan and API-key use to API pricing. The contracting and paying entities for either proposed Soleur mode remain unverified.

For Enterprise accounts, [workspace administrators control Codex access and permissions](https://help.openai.com/en/articles/8411955), and [managed-account administrators may access, export, retain, and delete account data](https://help.openai.com/en/articles/20001067-data-access-for-your-managed-chatgpt-account). These public capabilities do not establish the controls or retention policy of the account currently signed in on this machine. The [OpenAI Services Agreement](https://openai.com/policies/services-agreement/) states that the customer retains input rights and owns output as between the parties, subject to applicable law; the actual applicable agreement must be confirmed.

The mode-specific decision request and evidence checklist are in `knowledge-base/project/specs/feat-one-shot-codex-web-rollout/clo-decision-packet.md`. Its status is **pending CLO disposition**, not approval.

## Required CLO disposition

Before customer repository content is enabled, record all of the following:

1. The executed OpenAI DPA or incorporated business terms and the contracting
   entity/account that covers this integration.
2. Processing locations, onward subprocessors, and the Chapter V transfer
   mechanism for the tenant.
3. The configured API retention control (preferably approved ZDR where the
   selected endpoints support it), endpoint application-state exceptions, and
   the managed-account retention policy where applicable.
4. Provider-side deletion/erasure behavior, including any safety or abuse-log
   exceptions that Soleur cannot delete on demand.
5. Auth-mode-specific billing, ownership, administrator access, and data
   control terms.

Until those fields are evidenced, the only permitted use is synthetic or
explicitly redacted internal qualification under the default-off
`codex-engine` flag.

## User-owned provider path

The web app's `api-key` mode is user-owned: the request is sent under the
connected user's OpenAI/Codex credential rather than a Soleur-managed OpenAI
credential. The user's account agreement, retention settings, processing
locations, administrator controls, and deletion terms govern OpenAI's copy.
This does not approve the restricted Soleur-managed path or authorize a user
to submit data they do not control. The product discloses the provider-account
boundary and requires users to submit only data they are authorized to share.

Soleur remains responsible for application-side processing of prompts,
outputs, credentials, and audit records, and shared workspaces must not fall
back to a managed credential when a user-owned binding is selected.

## Sources

- <https://openai.com/business-data/>
- <https://openai.com/policies/data-processing-addendum/>
- <https://openai.com/policies/services-agreement/>
- <https://openai.com/policies/sub-processor-list/>
- <https://platform.openai.com/docs/models/default-usage-policies-by-endpoint>
- <https://help.openai.com/en/articles/9039756>
- <https://help.openai.com/en/articles/20001275/>
