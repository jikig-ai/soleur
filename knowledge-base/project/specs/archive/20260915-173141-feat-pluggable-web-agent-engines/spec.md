---
title: "Pluggable agent engines for Soleur Web"
date: 2026-09-11
branch: feat-pluggable-web-agent-engines
lane: cross-domain
brand_survival_threshold: single-user incident
status: agreed-direction
---

# Pluggable agent engines for Soleur Web

## Problem Statement

Soleur Web needs to support Claude Code and Codex initially, with an architecture
that accommodates Grok Build, potentially Devin, and other agent engines later.
The user approved this direction and selected one default engine per workspace.
This brief captures that agreement; it is not an implementation-ready plan or
evidence that any new engine is production-qualified.

An engine is an agent system with its own execution lifecycle, tools, sessions,
and workspace behavior. It is distinct from the model or inference provider it
uses. Supporting another inference endpoint alone does not integrate that engine.

## Agreed Product Behavior

1. A workspace selects its default engine. New conversations inherit it.
2. Conversations retain their original engine and a non-secret configuration
   snapshot. Changing the default does not migrate existing engine transcripts.
3. The repository, knowledge base, and approved artifacts remain shared Soleur
   product state. Native session state belongs to the selected engine.
4. Claude Code and Codex are the initial implementations. Extensibility for Grok
   Build, Devin, and others is a first-release architectural requirement.
5. Missing capabilities are visible. An engine cannot run a workflow when a
   required control is unsupported or unverified.
6. Engine-specific models and authentication options live under the engine
   configuration. Credential ownership and workspace defaults are separate:
   choosing an engine never grants access to another person's credential.
7. Engine unavailability, disablement, or lost qualification never triggers silent
   fallback to another engine. Preserve the conversation binding, report the
   failure, and require an authorized explicit choice before sharing context with
   another provider. Any later transfer creates a new engine-bound conversation.

## Current Evidence

The existing [harness adapter](../../../../plugins/soleur/lib/harness.ts) and
[ADR-215](../../../engineering/architecture/decisions/ADR-215-codex-plugin-reuses-canonical-soleur-components.md)
already cover plugin-level Claude, Grok, and Codex compatibility. ADR-215 explicitly
limits its verification to discovery and does not claim workflow or hook parity.

The web runtime's
[QueryFactory](../../../../apps/web-platform/server/soleur-go-runner.ts) still uses
Claude SDK message and query types. The
[dispatcher](../../../../apps/web-platform/server/cc-dispatcher.ts) constructs a
Claude SDK MCP server for platform tools. The
[permission callback](../../../../apps/web-platform/server/permission-callback.ts),
[query options](../../../../apps/web-platform/server/agent-runner-query-options.ts),
and [credential lease](../../../../apps/web-platform/server/byok-lease.ts) identify
security and lifecycle boundaries that need explicit adaptation.

Evidence checked on 2026-09-11:

| Engine | Observed integration surface | Remaining qualification |
|--------|------------------------------|-------------------------|
| Claude Code | Existing web SDK runtime and platform tools | Preserve current behavior through extraction |
| Codex | Official App Server documents threads, approvals, streamed events, and authentication | Prove Soleur authorization, isolation, recovery, and workflow compatibility |
| Grok Build | Installed `grok 1.0.29` help exposes `agent stdio`, `agent serve`, headless modes, session resume, and sandbox options | Verify protocol semantics and enforcement; CLI options alone do not prove parity |
| Devin | Official v3 API documents remote session creation, session IDs, repository selection, messages, and termination endpoints | Verify applicable account access, event delivery, artifact exchange, approval controls, and cancellation semantics |

Sources: [Codex App Server](https://learn.chatgpt.com/docs/app-server),
[Devin v3 session API](https://docs.devin.ai/api-reference/v3/sessions/post-organizations-sessions).
Grok evidence came from read-only `grok --version`, `grok --help`, and
`grok agent --help` probes; no paid agent sessions were started.

Existing [Grok product epic #6547](https://github.com/jikig-ai/soleur/issues/6547)
was verified OPEN on 2026-09-11. This proposal supplements that work, rather than
claiming its dogfood measurements or CPO/CLO prerequisites have been satisfied.
No change to that issue's scope or re-evaluation criteria is implied.

## Architecture Requirements

### Engine registry and adapters

Use a reviewed registry of engine definitions and their adapters. Each definition
provides an identifier, configuration and authentication schemas, supported
capabilities, and its implementation. Registration is a platform deployment
concern, not permission for customers to upload executable adapters.

Normalize session start, continuation, status, cancellation, and recovery, plus
events for text, progress, approvals, artifacts, usage, and errors. Keep native
handles opaque and bound to a tenant, conversation, and engine. The contract must
not expose Claude SDK types, Codex protocol objects, process IDs, or local paths
as mandatory application-level session fields.

### Capabilities with evidence

Declare capabilities such as live text streaming, interactive approvals,
platform tools, durable continuation, cancellation, attachments, workspace
access, and usage reporting. Treat unsupported, supported, and verified-for-this-
deployment as different facts. Effective capabilities depend on engine version,
deployment configuration, and account entitlement as applicable.

Soleur workflow requirements determine eligibility before dispatch. Prompt text
asking an engine to respect a policy is not enforcement evidence. Unsupported
features cannot silently bypass approvals, spend controls, or tenant isolation.

### Local and remote execution

Keep execution transport separate from the product-facing engine contract. Allow
adapters backed by local subprocesses, stdio protocols, WebSocket connections, or
remote APIs. Reuse transport code only when actual implementations justify it;
do not build a general transport framework in advance.

A remote engine may report coarse progress or complete artifacts. Do not invent
tool events or render synthetic token streaming to make it resemble a local
engine. Represent queued/running/waiting/terminal states honestly. A cancellation
request is not confirmed cancellation: reconcile remote state and disclose
uncertainty until termination is confirmed.

### Shared authorization and workspace ownership

Soleur owns policy decisions, permission scope, credential access, audit records,
and spending authorization. Adapters translate enforceable decisions into native
mechanisms. Policy must also apply to platform-tool execution, not merely to UI
approval prompts or adapter declarations.

Each execution receives only authorized workspace resources and scoped secrets.
Per-tenant configuration, credential caches, and session storage must remain
isolated. Remote integrations additionally need explicit rules for source
revision selection, artifact provenance, conflict handling, retention, deletion,
and what customer content may leave Soleur's environment. Importing an artifact
does not authorize publishing, merging, or deploying it.

Do not freeze credential values or authorization grants in conversation snapshots.
Resolve current authorization, membership, credential validity, and revocation on
every execution. A stale snapshot must not resurrect a revoked grant.

### Usage and reliability

Keep native usage units and their provenance; tokens, provider credits, and money
are not interchangeable. Preserve unavailable or estimated cost as such instead
of recording zero or presenting an estimate as a final charge.

Define retry and reconciliation behavior for uncertain dispatch outcomes,
duplicate/out-of-order events, restarts, and disconnects. Never restart an
uncertain remote job blindly and risk duplicate paid work or external actions.
Prefer existing Soleur conversation/event infrastructure where it provides these
properties; detailed design must verify the current consumers before extraction.

## Initial Delivery Scope

1. Inventory runtime, tool, authorization, credential, session, cost, background-job,
   attachment, and observability consumers that assume Claude. Distinguish
   workspace user workloads from platform-owned jobs and auxiliary model calls.
2. Define the smallest common contract and extract the current Claude behavior
   behind its first adapter.
3. Add a deterministic third test adapter representing a remote asynchronous
   engine with limited capabilities. Use it to challenge local-process and
   complete-parity assumptions before the Codex integration fixes the contract.
4. Add Codex, workspace default selection, conversation binding, provider-specific
   credential handling, and usage reporting.
5. Qualify both real engines against the same product and security requirements,
   then roll out through the existing feature-flag and deployment mechanisms.

API-key authentication is the proposed Codex starting point, not a separately
confirmed user decision. Subscription login needs its own product, account, and
data-handling assessment. No new provider expense or customer data transfer is
authorized by this brief.

Grok and Devin production adapters are future integration work. Their delivery
depends on product demand and successful qualification; neither identical feature
parity nor production availability is promised by the registry design.

## Acceptance Criteria for the Future Implementation

- Both initial engines complete a conversation using Soleur context and an
  authorized platform tool, recover after a runtime restart, support cancellation,
  and report usage with correct attribution.
- Changing a workspace default changes new conversations only. Tests prove
  existing conversations keep the correct engine and native session binding.
- A selected engine becoming unavailable, disabled, or unqualified produces a
  visible failure. A deterministic test proves no alternate adapter is invoked
  and no conversation context is sent to another provider.
- Adding the third test adapter requires only an adapter, registration, and its
  tests/configuration. Chat rendering, conversation routing, and core policy code
  require no engine-specific branches or modifications.
- Deterministic tests exercise a queued remote job, missing streaming, denied or
  unavailable mandatory approval controls, duplicate events, uncertain dispatch,
  and cancellation acknowledgement delayed beyond the request.
- Cross-workspace access, revoked credentials, stale permissions, and unauthorized
  platform actions remain denied for every enabled adapter.
- Native usage without a verified monetary value is displayed as unavailable or
  estimated, never fabricated as zero cost.
- The first release inventories any remaining Anthropic-dependent auxiliary calls
  and workloads and states their user-visible implications before Codex rollout.

The third adapter proves interface extensibility, not production readiness of a
real third-party service. Real engine qualification remains mandatory.

## User-Brand Impact

**Artifact:** Soleur Web agent-engine selection and execution.
**Vector:** An incorrectly adapted engine could expose a user's repository or
credentials, perform an unauthorized action, lose conversation continuity, or
incur unreported cost.
**Threshold:** single-user incident.

## Required Design Work Before Implementation

- Technical plan with a concrete migration strategy and consumer inventory.
- CPO/CTO/CLO assessment of customer impact and engine eligibility; CMO review of
  user-facing capability claims. A bounded CTO review of this brief ran and its
  engine-fallback finding is incorporated. Full domain sign-off remains pending.
- ADR and C4 update recording the resulting ownership and trust boundaries.
- Workspace-settings wireframe, including who controls the default, missing
  credentials, existing conversations, and unavailable capabilities.
- GDPR gate for provider credentials and remote customer-content handling.
- Observability design mapping start failures, permission failures, recovery,
  cancellation uncertainty, and usage gaps to existing logs, Sentry, and durable
  product state, including automated probes that require no host login.
- Live integration proof in an isolated development environment, with a bounded
  usage budget, before replacing the preliminary engineering estimate.

## Open Product Decisions

1. Confirm API-key-only Codex authentication for the first release versus including
   subscription login.
2. Confirm whether workspace-owned routines inherit the default immediately or
   receive their own persisted engine binding when created.
3. Decide whether future remote engines can be offered for a restricted workflow
   subset when they cannot meet the full interactive engine contract.

These questions do not change the approved requirement that the architecture
accommodate additional local and remote engines.
