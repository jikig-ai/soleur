---
title: "feat: add pluggable web agent engines"
date: 2026-09-11
slug: feat-pluggable-web-agent-engines
branch: feat-pluggable-web-agent-engines
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Define and implement the first extensible Soleur Web agent runtime: Claude Code
and Codex adapters behind a common engine contract, a workspace default for new
conversations, and explicit capability and authorization checks that can support
future local or remote engines such as Grok Build and Devin.

## User-Brand Impact

**Artifact:** Soleur Web agent-engine selection and execution.
**Vector:** An incorrectly adapted engine could expose a user's repository or
credentials, perform an unauthorized action, lose conversation continuity, or
incur unreported cost.
**Threshold:** single-user incident.
**Required signoff:** CPO, CTO, CLO, and CMO before public rollout. CPO and CMO
reviews completed for this plan; CTO's bounded review completed during the brief;
CLO review remains a work-phase gate.

## Worst-Case User Outcome

If the change fails silently, one user could have conversation context or scoped
credentials sent to the wrong engine, or could be charged for work whose status
and usage were not recorded. The design therefore pins every conversation to an
engine, resolves authorization and credentials at execution time, fails closed on
missing capability or qualification, and makes uncertain remote cancellation and
cost visible.

## Research Insights

### Repository evidence

- `apps/web-platform/server/soleur-go-runner.ts` exposes `QueryFactory`, but its
  `QueryFactoryArgs` and async iterator are Claude SDK-shaped (`SDKUserMessage`,
  `SDKMessage`, and `Query`). The first implementation must extract a neutral
  contract while retaining a Claude adapter behind it.
- `apps/web-platform/server/cc-dispatcher.ts` creates the platform MCP server with
  `createSdkMcpServer` and imports Anthropic's `sdkQuery`; platform tools and
  approvals therefore need an adapter translation boundary rather than a second
  UI-specific path.
- `apps/web-platform/server/agent-runner-query-options.ts` and
  `apps/web-platform/server/permission-callback.ts` are the current policy seams.
  The shared policy decision must stay outside any vendor protocol.
- `apps/web-platform/server/byok-lease.ts`, `byok-resolver.ts`, and
  `agent-env.ts` currently resolve Anthropic credentials. `apps/web-platform/lib/types.ts`
  has no OpenAI/Codex provider and `Conversation` has `session_id` but no engine
  binding, so both the provider union and persistence model need deliberate
  widening with a consumer grep.
- Workspace settings are rendered by
  `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx` and
  `apps/web-platform/components/settings/settings-content.tsx`; this is the
  existing surface for the workspace default selector and credential status.
- Conversation creation and routing are spread across `ws-handler.ts`,
  `conversation-writer.ts`, `agent-runner.ts`, and `cc-dispatcher.ts`. The plan
  must cover all creation paths, including support and workspace-owned routines,
  before making the engine column required for new rows.
- Existing learnings require abort-before-replace for session races, rethrowing
  resume failures so fallback can be explicit, and capability declarations in
  the baseline prompt. They also distinguish a plugin `Harness` (invocation
  surface) from an execution engine; the new registry must not widen that union.

### External qualification evidence

- [Codex App Server](https://learn.chatgpt.com/docs/app-server) documents threads,
  resumptions, streamed events, approval requests, permissions, and token usage.
  [Codex authentication](https://learn.chatgpt.com/docs/auth) supports API-key and
  ChatGPT subscription sign-in with different billing and data controls. API-key
  authentication is the proposed first-release path; subscription login is a
  separate product decision.
- The installed `grok 1.0.29` CLI exposes stdio, headless, WebSocket, resume,
  sandbox, and permission modes. CLI help proves an integration surface only;
  protocol and enforcement remain unqualified.
- [Devin's v3 session API](https://docs.devin.ai/api-reference/v3/sessions/post-organizations-sessions)
  exposes remote session creation, repository and secret selection, resumability,
  messages, status, and ACU limits. It does not yet prove artifact provenance,
  approval parity, event delivery, or cancellation semantics for Soleur.
- Existing [Grok epic #6547](https://github.com/jikig-ai/soleur/issues/6547)
  remains OPEN and retains its dogfood measurements and CPO/CLO prerequisites.
  This plan does not change that epic or promise Grok production support.

### Domain review

- **CPO:** Building/early-beta maturity; large (week+). Signoff requires clear
  default and conversation-binding UX, explicit Codex auth scope, qualification
  metrics, and no automatic transfer on failure.
- **CMO:** Direction fits Soleur's device-agnostic “Company-as-a-Service” frame.
  Public copy must lead with shared organization and approvals, use a capability
  matrix, qualify Claude Code-only claims, and avoid parity claims for Grok/Devin.
- **CTO:** The brief's fallback invariant is binding: preserve the selected
  conversation, surface failure, and require an authorized explicit new
  engine-bound conversation before context transfer.
- **CLO:** Required before rollout because credentials, repository content, and
  possible cross-border remote processing are in scope.

### Research limitations and recovery

The planned repository and learning fan-out agents both hit the current agent
usage limit before returning results. Functional-discovery fan-out was therefore
not independently available; local `rg`/`cat` inspection covered runtime,
settings, schema, tests, learnings, and existing issue overlap. The result is a
bounded local inventory, not an assertion that no other consumer exists. The
Pencil dependency check found a headless CLI but failed authentication, so the
required `.pen` wireframe is a hard-block until an authenticated Pencil source is
available.

Because the brand-survival threshold is a single-user incident, run
`/soleur:deepen-plan` against this artifact before `/work`. The normal parallel
deepening fan-out was unavailable in this session because of the recorded agent
usage limit; the deepening gate remains open rather than being treated as
complete.

## Mechanism Minimality

### Properties to preserve

1. Every new conversation dispatches through its persisted workspace default.
2. Existing conversations keep their engine and native session handle.
3. Chat rendering and lifecycle consumers read a normalized event contract.
4. Soleur authorization, tenant isolation, credential ownership, and spend caps
   apply to every adapter.
5. Local and remote asynchronous execution are represented honestly.
6. An unavailable, disabled, or unqualified engine cannot silently fall back.
7. Usage provenance, recovery, and reconciliation survive restarts and disconnects.

### Deliberate cuts

- A general transport framework is cut; adapters may use subprocess, stdio,
  WebSocket, or remote HTTP directly until two implementations justify shared
  transport code.
- Customer-uploaded executable adapters are cut; the registry is a reviewed,
  server-deployed allowlist.
- A provider-level model selector as the primary abstraction is cut; model,
  authentication, and entitlement are engine configuration.
- Synthetic token streaming for remote jobs is cut; remote progress is coarse and
  honest.
- In-place migration of old transcripts between engines is cut; transfer creates
  a new engine-bound conversation only after explicit authorization.
- Subscription-based Codex sign-in is cut from the first release pending product,
  account, and data-handling review.

## Research Reconciliation — Spec vs. Codebase

| Spec assumption | Codebase reality | Plan response |
|---|---|---|
| `QueryFactory` is a generic extension point | It imports Claude SDK message and query types | Define a neutral `AgentEngine` contract and wrap current Claude behavior first |
| Platform tools are shared through MCP | `cc-dispatcher.ts` constructs a Claude-specific MCP server | Move tool definitions/policy to a neutral layer and translate per adapter |
| Credentials are provider-specific | BYOK lease and env resolution are Anthropic-only | Add engine/provider credential descriptors and preserve per-user lease ownership |
| Workspace defaults and conversation binding exist | `conversations` has `session_id`, but no engine/default columns | Add migration, RLS-safe read/write helpers, and backfill legacy rows to Claude |
| Remote engines fit the same lifecycle | Current runtime is local Claude with native streaming | Add a deterministic remote test adapter before Codex to force honest states |

## Implementation Plan

### Phase 0 — Contract and inventory (TDD first)

1. Add failing contract tests for registry lookup, capability evidence,
   conversation binding, no-fallback behavior, event normalization, idempotent
   event sequencing, and current-authorization resolution.
2. Inventory every `conversations` creation/update path, `session_id` consumer,
   tool/approval dispatch, cost writer, attachment path, restart/reconnect path,
   and Anthropic-only auxiliary call. Classify each as user workload, platform
   job, or auxiliary model call.
3. Define neutral types: `AgentEngineId`, engine definition, capability status
   (`unsupported`, `supported`, `verified`), opaque native session handle,
   normalized lifecycle/event union, usage provenance, and explicit transfer
   command. Keep `Harness` unchanged.
4. Define `EngineAdapter` operations for start, continue, send, cancel,
   reconcile, and dispose. Adapters own protocol translation; shared policy owns
   authorization decisions and platform-tool execution.

### Phase 1 — Claude extraction and persistence

1. Add a migration after 137 (use the next repository migration number after
   confirming no concurrent migration) that adds `workspaces.default_engine_id`,
   `conversations.engine_id`, and a non-secret `engine_config_snapshot` JSONB
   containing version/model/capability evidence. Annotate lawful basis and
   retention intent; keep credential values out of the snapshot. Backfill legacy
   conversations to Claude and enforce engine binding for new rows after the
   backfill check.
2. Add workspace-scoped helpers and RLS tests. Owner/admin may change the
   workspace default; members may read it. Conversation engine binding is
   immutable after first dispatch except through an explicit transfer operation.
3. Extract current Claude SDK code from `soleur-go-runner.ts`, `cc-dispatcher.ts`,
   and `agent-runner-query-options.ts` into a Claude adapter. Preserve existing
   permission callback, session resume, abort-before-replace, worktree lease,
   MCP tool, and Sentry behavior through the adapter boundary.
4. Keep `permission-callback.ts` as the shared policy decision point. Add adapter
   translation tests proving a deny is enforced both before a native approval and
   at platform-tool execution.

### Phase 2 — Deterministic remote adapter and registry

1. Implement a test-only remote asynchronous adapter with queued/running/waiting/
   terminal states, no live streaming, delayed cancellation acknowledgement,
   duplicate/out-of-order events, uncertain dispatch, and missing monetary usage.
2. Register it through the same reviewed registry path as real adapters. Its tests
   must pass without touching network, credentials, or a real paid service.
3. Add reconciliation records and idempotency keys so restart/disconnect recovery
   never blindly starts a second uncertain remote job.

### Phase 3 — Codex adapter and workspace UX

1. Add the Codex adapter using the selected authentication path (API key for the
   first release unless product review changes it). Map App Server thread start/
   resume, streamed events, approval requests, permission scopes, cancellation,
   and token usage into the neutral contract. Do not expose protocol objects to
   client code.
2. Extend provider and lease resolution for Codex/OpenAI credentials. Reuse the
   current encrypted storage and zeroization boundary; never read a user's key
   from another workspace or freeze it in conversation config.
3. Add a “Default agent engine for new conversations” section to the existing
   workspace settings page. Show engine availability, required credential state,
   capability gaps, and the rule that existing conversations keep their engine.
   The API must validate ownership, engine qualification, and credential presence
   independently of the UI.
4. Create and commit the required Pencil `.pen` wireframe before implementation
   of this UI. The dependency check currently hard-blocks this deliverable due to
   missing Pencil authentication; resolve that block before `/work` Phase 2.

### Phase 4 — Qualification and rollout

1. Run both real adapters through the same matrix: authorized platform tool,
   approval denial, restart recovery, cancellation, cross-workspace isolation,
   revoked credential, usage attribution, attachment handling, and capability
   mismatch. Bound live usage and record the measured results.
2. Add a feature flag for Codex dispatch and roll out to an internal cohort first.
   Keep Claude as the default until Codex qualification passes; never use a flag
   as a substitute for capability or authorization checks.
3. Publish a capability matrix and update Claude Code-only public claims only after
   CMO/CLO signoff. Keep Grok Build and Devin in the registry design/future scope
   until their own qualification gates pass.

## Acceptance Criteria

- The neutral contract tests pass for Claude, Codex, and the deterministic remote
  adapter; adding a fourth adapter changes only registration, adapter code, and
  adapter tests.
- New conversations inherit the workspace default; existing rows retain their
  engine and native session binding across default changes and restarts.
- An unavailable, disabled, or unqualified selected engine produces a visible
  failure, invokes no alternate adapter, and sends no context to another provider.
- All adapters enforce current membership, credential validity, revocation,
  permission decisions, spend authorization, and platform-tool policy.
- Queued remote work, absent streaming, duplicate events, uncertain dispatch,
  delayed cancellation, and estimated/unavailable usage have deterministic tests
  and honest client states.
- Native usage units and provenance remain distinct from monetary cost; no
  unverified value is stored or displayed as zero.
- Restart and disconnect recovery is idempotent, and a cancellation request is
  not marked complete until reconciliation confirms termination.
- The first-release inventory names every remaining Anthropic-dependent auxiliary
  call and states its user-visible implication before Codex rollout.
- Workspace settings explain default scope, existing-conversation continuity,
  missing credentials, and capability gaps; the committed `.pen` wireframe exists
  and matches the shipped flow.

## Files to Edit

- `apps/web-platform/lib/types.ts`
- `apps/web-platform/server/soleur-go-runner.ts`
- `apps/web-platform/server/cc-dispatcher.ts`
- `apps/web-platform/server/agent-runner-query-options.ts`
- `apps/web-platform/server/permission-callback.ts`
- `apps/web-platform/server/byok-lease.ts`
- `apps/web-platform/server/byok-resolver.ts`
- `apps/web-platform/server/agent-env.ts`
- `apps/web-platform/server/ws-handler.ts`
- `apps/web-platform/server/conversation-writer.ts`
- `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx`
- `apps/web-platform/components/settings/settings-content.tsx`
- `apps/web-platform/package.json`, `apps/web-platform/Dockerfile` (only if the
  chosen Codex transport requires a pinned runtime executable)
- `apps/web-platform/supabase/migrations/<next>_agent_engine_binding.sql`
- Existing adapter, dispatcher, permission, BYOK, conversation, and WebSocket
  test files identified by the Phase 0 consumer inventory.

## Files to Create

- `apps/web-platform/server/agent-engine-contract.ts`
- `apps/web-platform/server/agent-engine-registry.ts`
- `apps/web-platform/server/agent-engine-policy.ts`
- `apps/web-platform/server/agent-engine-remote-test-adapter.ts`
- `apps/web-platform/server/codex-agent-adapter.ts`
- `apps/web-platform/components/settings/agent-engine-settings.tsx`
- `apps/web-platform/test/agent-engine-contract.test.ts`
- `apps/web-platform/test/agent-engine-registry.test.ts`
- `apps/web-platform/test/agent-engine-routing.test.ts`
- `apps/web-platform/test/agent-engine-remote-reconciliation.test.ts`
- `apps/web-platform/test/codex-agent-adapter.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-<next>-pluggable-web-agent-runtime.md`
- `knowledge-base/product/design/agent-engine-selection/<wireframe>.pen`

## Observability

**Liveness signal:** Emit structured `engine_dispatch_started`,
`engine_dispatch_progress`, `engine_dispatch_completed`, and
`engine_session_reconciled` events for every execution. Durable conversation
status and existing WebSocket lifecycle remain the product signal; a watchdog
marks queued/running/waiting jobs whose heartbeat or reconciliation deadline
passes.

**Error reporting:** Use structured pino logs and `reportSilentFallback` to Sentry
for adapter startup, auth/credential, permission, reconciliation, cancellation,
and usage failures. Selected-engine failure is fail-loud and never invokes a
silent fallback path.

**Failure modes and layers:**

| Failure mode | Detection and response | Observability layer |
|---|---|---|
| Adapter unavailable/disabled/unqualified | Registry eligibility check; durable conversation failure; no fallback | Sentry exception + pino + `engine_dispatch_*` event |
| Permission or platform-tool denial | Shared policy decision and audit event; native adapter deny | Permission audit row + Sentry for unexpected errors |
| Remote timeout or uncertain cancellation | Reconciliation deadline; honest waiting/unknown state; retry requires idempotency key | Durable job/conversation state + watchdog event + Sentry |
| Duplicate or out-of-order event | Sequence/idempotency guard; ignore duplicate and record anomaly | Event ledger + pino warning + Sentry anomaly |
| Missing or estimated usage | Preserve native units/provenance and mark unavailable/estimated | Cost writer + usage event + Sentry on writer failure |
| Cross-workspace credential/session lookup | RLS and lease-owner checks fail closed | Auth audit row + Sentry + test fixture |

**Logs:** Pino structured fields include `engine_id`, `conversation_id`,
`workspace_id`, `adapter_version`, `event_id`, `native_session_ref_hash`, and
`failure_class`; never log prompts, credentials, native handles, or remote
payloads. Durable product state stores normalized lifecycle, approval, usage,
and reconciliation metadata with existing retention/deletion paths.

**Discoverability test:** After implementation, run
`rg -n "engine_dispatch_started|engine_dispatch_failed|engine_session_reconciled" apps/web-platform/server apps/web-platform/lib`
and require one start, one failure, and one reconciliation instrumentation site
plus tests that assert each marker is emitted without credentials.

## GDPR Gate

The plan touches provider credentials, authentication routes, schema migrations,
and remote customer-content handling. The advisory gate was invoked against
representative migration/API/BYOK paths and reported:

- `gdpr-gate rules 124 days stale` and `POSTURE_FAIL` (last verified 2026-05-10);
  findings are advisory and the corpus needs refresh before relying on a clean
  result.
- `3 examined, 2 matched` regulated-data paths; run `/soleur:gdpr-gate` again at
  work Phase 2 exit after the concrete migration and routes exist.

Implementation must add lawful-basis and retention annotations to the migration,
preserve erasure/export coverage for engine snapshots and event records, document
the Codex vendor/DPA and any Chapter-V transfer, and obtain CLO review. No prompt,
credential, or remote row value may be sent to the gate or committed to fixtures.

## Architecture Deliverables

- ADR documenting the engine-versus-harness boundary, adapter ownership,
  workspace/conversation binding, authorization and credential trust boundaries,
  local/remote lifecycle, and no-fallback rule.
- Update `knowledge-base/engineering/architecture/diagrams/model.c4` and regenerate
  `model.likec4.json` with `bash scripts/regenerate-c4-model.sh`. Model the neutral
  engine registry, Claude/Codex adapters, remote execution boundary, and their
  relationships to workspace state, session storage, credentials, and observability.
- Keep the existing `Harness` union and ADR-215 plugin compatibility decision
  unchanged; this plan concerns Web execution engines.

## Scope, Risks, and Rollout

**Estimate:** large, week+; split into contract/persistence, deterministic remote
adapter, Codex, and qualification slices. Do not merge a partial adapter that
can bypass shared policy.

**Primary risks:** Claude behavior regression during extraction; Codex approval or
resume semantics not matching assumptions; remote jobs duplicating paid work;
credential ownership crossing workspace boundaries; stale public claims; and
unmeasured vendor spend. Each risk has a deterministic test or a qualification
gate above.

**Rollout:** Keep Claude enabled and the workspace default unchanged while the
Codex flag is internal-only. Promote only after both adapters pass qualification,
GDPR/CLO review, CPO/CMO messaging review, the settings `.pen` gate, and QA with
restart/cancellation evidence. Grok Build and Devin remain future registry
entries until independently qualified.

## Open Decisions Before `/work`

1. Confirm API-key-only Codex authentication for the first release; subscription
   login remains out of scope unless product and data review changes it.
2. Decide whether workspace-owned routines inherit the default at creation or
   receive a persisted engine binding of their own.
3. Decide whether a future remote engine may be exposed for a restricted workflow
   subset when it cannot meet the full interactive contract.
4. Resolve Pencil authentication and commit the workspace-settings wireframe.
