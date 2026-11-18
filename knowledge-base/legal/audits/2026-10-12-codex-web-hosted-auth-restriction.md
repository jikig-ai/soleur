---
title: "Codex Web PR 9051 — scope of hosted App Server authentication restriction"
date: 2026-10-12
actor: "soleur:legal:clo / Codex mode_disposition assessment"
attestation_authority: soleur-legal-clo-agent
reviewed_head: 2b826822c086d4348ada891e15fde2aa7b62eac3
reviewed_workspace: "HEAD plus uncommitted application fixes; authentication launcher/protocol unchanged"
pr: 9051
status: blocked-planned-hosted-app-server-authentication
api_key_app_server_auth_disposition: blocked-documented-hosted-auth-restriction
managed_app_server_auth_disposition: blocked-documented-hosted-auth-restriction
alternative_api_funded_route_disposition: pending-exact-route-review
customer_content_status: blocked
prior_audit: knowledge-base/legal/audits/2026-10-11-codex-web-mode-continuation.md
review_by: 2026-10-15
reevaluation_triggers:
  - "Provider evidence permitting the exact hosted authentication route"
  - "A different API-funded integration is concretely specified for independent review"
  - "Changed account, agreement, custody, processing controls or cohort"
---

# Hosted-authentication supplement

**Internal CLO decision: the proposed hosted App Server authentication route is
BLOCKED for both API-key and managed authentication.** An alternative API-funded
integration remains separately PENDING, without live authorization. This
supplements the [2026-10-11 audit](2026-10-11-codex-web-mode-continuation.md);
that record remains historical and unchanged. This is draft internal review,
not an external counsel opinion or executed provider agreement.

## What the primary sources establish

OpenAI's [App Server documentation, Auth endpoints](https://learn.chatgpt.com/docs/app-server#auth-endpoints),
retrieved 2026-10-12, states:

> App-server authentication has never been permitted for commercial or hosted services.

That restriction precedes the authentication-mode descriptions, including
API-key authentication and experimental externally supplied ChatGPT tokens.
The documented `account/login/start` API-key method is therefore not evidence
of an exception for a hosted service. **Internal interpretation:** apply that
documented restriction to the proposed hosted API-key authentication RPC as
well as managed authentication; do not infer an exemption from payment by API
key or from experimental external-token support.

The [ChatGPT plan-usage overview](https://developers.openai.com/siwc/token-sharing-open-source),
also retrieved 2026-10-12, covers open-source and locally hosted applications
and directs paid or remotely hosted applications to its interest form. This
identifies a permission-request route, not existing Soleur permission. No
exception or provider approval has been supplied. Owner approval cannot grant
rights withheld by the provider, and no support request or form was sent here.

The [Services Agreement §§2.2 and 3.3(g)](https://openai.com/policies/services-agreement/),
retrieved 2026-10-12, permits API integration into customer applications and
restricts third-party API-key transfers. **This review does not establish a
blanket T&C clause prohibiting hosting the App Server binary.** The specific
evidence is a published authentication restriction; generic API integration
permission does not establish permission for that restricted authentication
route. Binary execution, the provider's authentication route and account/key
custody are separate questions. An environment-delivered key is not an
automatic exemption from the restriction.

## Actual source and proposed-method proof

The [account evidence guide](../../project/specs/feat-one-shot-codex-web-live-paths/account-evidence-guide-2026-10-06.md#exact-provider-route)
explicitly proposes hosted `account/login/start` with `type:"apiKey"`, and
explicitly says that RPC is not verified as implemented in this branch. It
is this proposed App Server authentication route that receives the BLOCKED
finding above; the guide is not evidence that a live RPC already occurs.

Current `codex-app-server-launcher.ts` › `createCodexAppServerLauncher()` starts
`app-server --stdio` and injects a caller-defined `environment(lease)`.
`codex-app-server-stdio.ts` › `createCodexAppServerStdio()` passes the lease to
that launcher. `codex-app-server-handshake.ts` › `createCodexAppServerHandshake()`
sends only `initialize` and `initialized`; `codex-app-server-protocol.ts` exposes
lifecycle requests, with no login builder. A targeted read/search of current
`server/codex-*` files found no `account/login/start`, `chatgptAuthTokens`,
`OPENAI_API_KEY` or `CODEX_API_KEY` authentication construction. Consequently,
the source proves a credential-delivery seam, not an implemented, permitted
API-only alternative. `codexConversationRuntime()` still supplies no approved
launcher or accepted data classes and retains unverified transfer evidence.

## Consequence for remaining acceptance criteria

| Route | Internal disposition | Required change in evidence |
|---|---|---|
| Proposed hosted API-key App Server authentication RPC | **BLOCKED** | Provider evidence permitting this precise hosted route, or a separately specified and reviewed alternative. |
| Managed hosted App Server authentication, including a proposed external-token substitute | **BLOCKED** | Provider-permitted hosted integration, plus independent account, agreement, controls and qualification evidence. |
| Different API-funded integration that avoids the restricted route | **PENDING** | Concrete authentication/endpoint/custody design and evidence establishing permitted use; account/data controls and Web qualification still apply. No automatic exemption is attested. |

Neither mode gains live permission. Project sharing/inheritance, retention and
configured regions remain unresolved; historical spending and key-lifetime
reports remain bounded observations. This supplement authorizes no credential
or account inspection, provider call, browser-auth reuse, shared write,
deployment or flag/cohort change. Keep PR #9051 draft, auto-merge disarmed,
Codex default-off and customer content blocked. Recovery, screenshot QA and
offline tests do not discharge the provider-authentication restriction.
