---
title: "Codex Web PR 9051 — exact-route and account-access delta"
date: 2026-10-22
actor: soleur:legal:clo
attestation_authority: soleur-legal-clo-agent
reviewed_head: ae4a0777d98bc6226b6eee1ea88fcc1646297e25
provider_document_retrieval_date: 2026-10-22
pr: 9051
status: blocked-live-authorization
api_key_app_server_auth_disposition: blocked-documented-hosted-auth-restriction
managed_app_server_auth_disposition: blocked-documented-hosted-auth-restriction
alternative_api_funded_route_disposition: pending-concrete-implementation-and-account-review
customer_content_status: blocked
prior_audit: knowledge-base/legal/audits/2026-10-21-codex-web-hosted-auth-recheck.md
reevaluation_triggers:
  - Provider permission covering the precise hosted App Server authentication route
  - CTO-reviewed alternative integration with pinned transport and preserved lifecycle requirements
  - Effective account controls observed through authorized access or attributable provider evidence
---

# Internal v1 CLO delta assessment

Both hosted App Server authentication proposals remain **BLOCKED**. This review
identifies a documented API-funded alternative worth technical assessment; it
does not authorize a live request or substitute that alternative for retained
feature phases. This is internal v1 draft material requiring professional legal
review. The [October 21 audit](2026-10-21-codex-web-hosted-auth-recheck.md),
[OpenAI snapshot](../data-processing-agreements/openai.md) and
[compliance posture](../compliance-posture.md#agent-engine-processing-migration-138--pr-8082)
remain the controlling record; no published legal text changes here.

## Exact implemented boundary

These findings concern the reviewed source, not a deployed build:

| Boundary | Actual implementation and evidentiary limit |
|---|---|
| Endpoint | `codex-conversation-runtime.ts` › `codexConversationRuntime()` supplies `https://api.openai.com/v1` and a host allowlist as admission evidence, but installs no launcher. This is neither an HTTP request nor proof that a provider process would use that endpoint. |
| API-key custody | `codex-credential-provider.ts` › `createCodexApiKeyProviderForUser()` selects the authenticated user's encrypted OpenAI settings row; `createCodexApiKeyProvider()` decrypts it server-side and issues a short lease. Soleur would have custody; the lease TTL is not provider-key expiration. |
| Credential delivery | `codex-app-server-launcher.ts` › `createCodexAppServerLauncher()` starts `app-server --stdio` with an injected environment function. Production composition supplies neither that environment nor an approved launcher. The inspected Codex server modules implement no `account/login/start` request; the proposed restricted authentication RPC must not be described as an executed or completed implementation. |
| Storage, tools and network | `codex-app-server-protocol.ts` › `createCodexThreadStartRequest()` sets only optional working directory; `createCodexTurnStartRequest()` sets thread identity and text input. These builders establish no model, provider HTTP route, request storage setting, tool policy, provider-home retention or effective network enforcement. Those facts must come from a pinned launcher/runtime configuration and evidence. |
| Transfer decision | `agent-engine-data-egress-policy.ts` › `authorizeEngineDataEgress()` still rejects unqualified data classes or unknown agreement/transfer evidence; customer processing also requires verified deletion support. Current composition accepts no data classes. No field was relabelled to obtain authorization. |

## Public-document conclusions

| Question | Disposition and current primary evidence |
|---|---|
| Hosted App Server API-key authentication | **BLOCKED.** The [App Server authentication section](https://learn.chatgpt.com/docs/app-server#auth-endpoints) places its hosted/commercial restriction before both API-key and managed-mode descriptions. API funding alone supplies no exception. This is a restriction on the authentication arrangement, not a blanket prohibition on hosting the executable. |
| Hosted managed/ChatGPT authentication | **BLOCKED.** The same restriction applies; the [plan-usage overview](https://developers.openai.com/siwc/token-sharing-open-source) directs paid/remotely hosted offerings to an interest form. No Soleur-specific permission was obtained or enquiry sent. |
| Generic API integration permission | **DISCHARGED only as a public-text question.** [Services Agreement §2.2](https://openai.com/policies/services-agreement/) permits customer applications using the API; §3.3(g) separately restricts third-party API-key transfers. These clauses neither prove account applicability nor resolve the specific App Server route or other users' credential custody. |
| Distinct API-funded automation candidate | **PENDING exact-route review.** Official [Codex SDK documentation](https://learn.chatgpt.com/docs/codex-sdk#typescript-library) describes server-side TypeScript use, and the [environment reference](https://learn.chatgpt.com/docs/config-file/environment-variables#authentication-and-network) identifies `CODEX_API_KEY` for non-interactive exec and the TypeScript SDK. The [upstream `CodexExec.run()` implementation](https://github.com/openai/codex/blob/main/sdk/typescript/src/exec.ts) constructs an exec process and passes an explicit API key through that environment variable. This is a concrete route for CTO assessment rather than an invented exemption for App Server authentication. |

The TypeScript candidate has not been installed or run by this assessment. Its
moving upstream source is discovery evidence, not a pinned implementation
attestation. The SDK documentation separately describes Python as wrapping App
Server; changing package names alone does not resolve the route. CTO review must
preserve the required approval, history, recovery, cancellation and erasure
behavior, and specify credential delivery, configuration, storage, tools and
network boundaries before CLO can assess the resulting integration.

For an alternative that uses Responses, [current data controls](https://developers.openai.com/api/docs/guides/your-data)
distinguish abuse logs from application state: standard abuse monitoring can
retain content for 30 days, default/stored Responses have at least 30 days of
state retention, and background operation, caches and tools have additional
rules. `store:false` alone proves neither ZDR nor zero retention. No request
behavior or regional guarantee is inferred for the current unconfigured seam.

## Read-only account-access result

Fresh tool discovery exposed no callable browser or Doppler MCP tool in this
agent context; the Doppler and agent-browser CLIs were present. Names-only
Doppler discovery succeeded for `soleur` configs `prd`, `dev`, `prd_terraform`
and `cli_ops`, returning zero reference names containing OpenAI or Codex.
Neither checked admin-key environment reference was present. This establishes
the checked access-reference limit, not absence of a key from every account or
secret store; no secret value was requested.

Using the agent-browser skill, a new isolated session navigated to the official
organization settings page. A redacted accessibility snapshot showed a
Cloudflare human-verification challenge, not authenticated account controls.
No challenge interaction, retry, authentication-state copying or credential
entry occurred. The owned browser was closed successfully. Thus this browser
attempt supplies no account settings or permission evidence.

An additional existing-session check returned no active agent-browser sessions.
Same-user process metadata identified a Chrome browser using remote-debugging
pipes, with no advertised debugging port; the common local debugging TCP ports
also had no listeners. No callable browser MCP tool or skill-supported CDP
endpoint for that browser was established. Its authenticated state was not
assessed, and its process, profile and owning automation connection were left
intact. No profile/cookie copying or pipe hijacking was attempted.

The broader names-only Doppler review inspected all 183 distinct reference
names across those four configs, including possible indirect admin, AI, model,
provider and credential references. Application-admin, database and BYOK
encryption references exist; their names do not identify OpenAI Admin API
access, and no stored user key was decrypted or database credential used to
search customer records. No suitable provider-admin reference was established
from this inventory. This is a bounded access-discovery finding, not a claim
that every possible indirect credential location was exhausted or that no
OpenAI account key exists.

Official read-only APIs still document [project residency](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/projects/methods/retrieve),
[project retention](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/projects/subresources/data_retention/methods/retrieve)
and [organization retention](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/data_retention/methods/retrieve).
The project can inherit organization retention; omission of residency or an
API error cannot establish a regional configuration. No suitable admin access
was established, so no authenticated Admin API request was attempted.

## What changes the disposition

For the restricted hosted App Server route, the missing external fact is actual
provider permission covering that arrangement. Another internal approval or
dashboard setting cannot supply it. Existing unsent requests in the
[account guide](../../project/specs/feat-one-shot-codex-web-live-paths/account-evidence-guide-2026-10-06.md#exact-provider-route)
and [control intake](../../project/specs/archive/20261013-051752-feat-one-shot-codex-web-rollout/api-control-evidence-2026-10-07.md#missing-control-evidence-prepared-support-request)
remain unsent; duplicating them creates no evidence.

For a distinct documented API integration, the present next dependency is a
concrete CTO-reviewed implementation rather than a blanket demand for a vendor
exception. An attributable mode-specific CLO decision still needs the effective
account/project controls and applicable agreement, custody, permitted cohort,
storage/erasure limits, transfer basis, spending bound and actual test deadline.
Preserve the existing entity/acceptance, US$5, seven-day maximum lifetime and
sharing reports with their original limits; do not ask the operator to repeat
them. None proves newly observed project inheritance or a particular test-key
deadline.

No inference, provider job, external message, key/account mutation, customer
content processing, activation or shipping clearance resulted. The original
qualification and legal phases remain required. Independent non-provider
technical work may continue within its existing containment and authorization.
