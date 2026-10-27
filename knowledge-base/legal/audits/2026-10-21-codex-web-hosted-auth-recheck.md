---
title: "Codex Web PR 9051 — hosted authentication source recheck"
date: 2026-10-21
actor: soleur:legal:clo
attestation_authority: soleur-legal-clo-agent
reviewed_head: da4b1b80a53538f7509993f4c30f7d9e05d54e18
provider_document_retrieval_date: 2026-10-21
pr: 9051
status: blocked-live-authorization
api_key_app_server_auth_disposition: blocked-documented-hosted-auth-restriction
managed_app_server_auth_disposition: blocked-documented-hosted-auth-restriction
alternative_api_funded_route_disposition: pending-exact-route-review
customer_content_status: blocked
prior_audit: knowledge-base/legal/audits/2026-10-12-codex-web-hosted-auth-restriction.md
reevaluation_triggers:
  - Provider evidence permitting the precise proposed hosted authentication arrangement
  - A concrete alternative API-funded integration specified for independent review
  - Changed account, agreement, custody, controls, cohort or data classes
---

# Internal v1 CLO assessment

**Both proposed hosted App Server authentication modes remain BLOCKED. A distinct
API-funded integration remains PENDING exact-route review, without live
authorization.** This fresh internal v1 assessment supplements the
[October 12 restriction audit](2026-10-12-codex-web-hosted-auth-restriction.md).
It is draft internal material requiring professional legal review, not external
counsel advice, an executed agreement or provider permission.

The operator's October 21 approval for all remaining work removes repeated
owner-permission prompts within that authorized scope. It supplies no new
provider permission, account-control fact, mode qualification or customer-data
disposition. This assessment performed read-only source/document review; it made
no provider inference request, credential/account inspection, external message,
flag/cohort change or production write.

## Provider documents rechecked on October 21

The [official App Server authentication documentation](https://learn.chatgpt.com/docs/app-server#auth-endpoints)
continues to exclude commercial or hosted services from App Server
authentication. This restriction precedes the API-key and ChatGPT authentication
mode descriptions. **Internal interpretation:** preserve the block for the
proposed hosted API-key authentication RPC and managed authentication alike.
Protocol availability, experimental external-token support and API funding do
not establish an exception. This is a finding about the authentication route,
not a blanket prohibition on distributing or hosting the executable.

The [official ChatGPT plan-usage overview](https://developers.openai.com/siwc/token-sharing-open-source)
continues to describe open-source/local applications and directs paid or
remotely hosted offerings to an interest form. This identifies a route to seek
permission; it establishes neither Soleur approval nor automatic eligibility.
No form or provider enquiry was submitted by this assessment.

## Reviewed implementation and evidence

Code findings below are tied to the reviewed head, not an assertion about a
deployed build or subsequent changes.

| Artifact or boundary | Finding |
|---|---|
| [Compliance posture](../compliance-posture.md#agent-engine-processing-migration-138--pr-8082) and PR-conditioned migration amendments | Provider processing remains gated; proposed rights/schema disclosures do not authorize transfer. |
| [Archived decision packet](../../project/specs/archive/20261013-051752-feat-one-shot-codex-web-rollout/clo-decision-packet.md) and [October 7 control intake](../../project/specs/archive/20261013-051752-feat-one-shot-codex-web-rollout/api-control-evidence-2026-10-07.md) | Preserve their dated owner/entity, sharing, spending and lifetime reports and their stated evidentiary limits; no new account/control evidence was collected here. |
| `apps/web-platform/server/codex-conversation-runtime.ts` › `codexConversationRuntime()` | Selects customer data, accepts no data classes, records an unverified DPA and unknown transfer/deletion support, requires approval and supplies only the user identity as runtime input, without an approved launcher. |
| `apps/web-platform/server/agent-engine-reviewed-definitions.ts` › `reviewedEngineRegistry` | Codex is disabled for new and existing runs and has no qualification entries. This is source configuration, not a fresh live flag observation. |
| `apps/web-platform/server/agent-engine-data-egress-policy.ts` › `authorizeEngineDataEgress()` | Synthetic requests also require a qualified class, verified DPA and known transfer evidence; customer requests additionally require verified provider deletion. Unknown evidence cannot be relabelled verified to obtain a passing matrix. |
| `apps/web-platform/server/codex-credential-provider.ts` › `createCodexApiKeyProviderForUser()` / `createCodexApiKeyProvider()` | Loads and decrypts the authenticated user's stored Web-settings credential server-side. This proves a custody design, not account permission for that design. |
| `apps/web-platform/server/codex-web-runtime.ts` › `createCodexWebEngineFactories()` | Selects the persisted mode without credential fallback and requires supplied managed credentials and a transport/launcher composition. These seams establish no permitted live provider route. |
| `apps/web-platform/test/server/ws-handler-codex-production-boundary.test.ts` › `assertNoExecution()` and both-mode rejection cases | Test source expects rejection before credentials, execution attempts, transcript reads, process spawn or Claude fallback. Tests were inspected, not rerun by this assessment. |

## Remaining facts and valid disposition path

The existing owner statement that Jikigai/Soleur owns and accepts the nominated
account's agreement, the reported absence of a custom override, the US$5 project
setting, seven-day maximum key lifetime and reloaded organization sharing
selections remain dated evidence. Do not ask the founder to repeat them or
convert those reports into stronger independent verification.

Reassessment still needs the following genuine facts, bound to safe aliases
rather than public identifiers or credential values:

- Provider permission for this precise hosted authentication arrangement, or a
  separately specified alternative with its endpoint, credential delivery and
  custody, request storage behavior and network path reviewed independently.
- Applicable account/project/workspace and agreement/DPA coverage, with
  owner/administrator/payer authority and same-entity custody or permission for
  the actual arrangement established to the degree needed for its cohort.
- Effective project retention and organization inheritance, configured regions
  and endpoint/model exclusions, actual request storage/tool behavior and
  retention/erasure limits. Disabled sharing and a failed storage panel prove
  neither ZDR nor a region. A separately signed DPA or ZDR is not a universal
  prerequisite for every narrow synthetic decision.
- An actual test deadline and adequate spending enforcement for the authorized
  total bound; historical monthly-limit and maximum-lifetime reports do not
  establish a particular key's deadline or a renewed test window.
- Separate authenticated Web evidence on the exact served build for each
  permitted mode, using trusted expiring synthetic workspace/user boundaries,
  server-marked conversations and fixed inputs, with ordinary customer chats
  excluded. Local transport smokes and mocked runtime tests do not supply it.

Use authorized read-only APIs or an available authenticated automation surface
for account evidence; do not hand the founder a dashboard-reading task.
Permission and support replies must actually come from the provider, and private
account facts must actually be observed or attested with their limits. Internal
CLO review cannot manufacture them. An external enquiry requires explicit
communication authorization; generic approval to complete technical work is not
a sent message or a provider response.

After the relevant route/account evidence exists, CLO owns an attributable
mode-specific decision naming permitted cohort/data classes, transfer mechanism,
retention/erasure limits, billing/admin ownership, restrictions and review expiry.
The CTO owns the exact integration and technical qualification. A synthetic-only
allowance is distinct from customer-content approval. The existing specialist
escalation route is [AI vendor terms](../recommended-tools.md#ai-vendor-terms).

## Work that may continue and shipping limit

Non-provider synthetic source work, acquisition evidence review, constrained
image/profile preparation, isolated build/database/recovery rehearsals, rendered
implementation QA, main reconciliation, CI, independent review, GDPR/preflight
and public-source research may proceed within their technical containment and
applicable authorization. None discharges hosted authentication, account
permission or live-mode qualification. Do not activate a prohibited route or
replace the actual egress evidence with invented verified values.

The authentication restriction does not itself forbid distributing inert guarded
source. Nevertheless, **this assessment grants no default-off shipping clearance
for PR #9051**. The existing attributable audit holds the PR draft/disarmed, and
its migration, recovery, security, review, QA and privacy gates remain independent.
A source-only release would require a recorded replacement CTO/CPO/CLO scope
disposition, verified no-transfer behavior, completion of those applicable gates
and accurate disclosure of unavailable functionality. It would ship guarded
infrastructure, not establish live Codex qualification. Preserve the retained
feature phases and acceptance requirements; do not silently remove them to claim
completion. No merge, deployment, flag change or customer-processing approval is
asserted here.
