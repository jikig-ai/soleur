---
vendor: OpenAI
role: proposed processor for Codex web-agent customer-content processing
status_snapshot_date: 2026-09-20
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
| DPA scope | OpenAI's DPA expressly covers API Services and ChatGPT Enterprise Services | No approval is inferred for a personal or otherwise unidentified ChatGPT account |
| Retention evidence | API abuse-monitoring logs may be retained up to 30 days by default; Zero Data Retention or Modified Abuse Monitoring requires eligibility and approval, and endpoint application-state rules still apply | Workspace retention and administrator controls must be evidenced from the specific Business/Enterprise agreement |
| Transfer geography | Not established by public pages for this tenant; CLO must record the applicable processing locations and transfer mechanism | Same unresolved item, plus account-region and administrator-control confirmation |
| Remote erasure | The adapter requires an exact provider delete acknowledgement and resets the next thread, but provider-side retention/deletion terms still need contractual evidence | Same requirement, with managed-account deletion semantics confirmed separately |

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
- <https://openai.com/policies/feb-2024-data-processing-addendum/>
- <https://platform.openai.com/docs/models/default-usage-policies-by-endpoint>
